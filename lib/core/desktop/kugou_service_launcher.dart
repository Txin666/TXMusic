import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../diagnostics/boot_log.dart';
import '../network/kugou_config.dart';
import '../storage/local_store.dart';

/// 内嵌 KuGouMusicApi 服务的管理器。
///
/// 背景：客户端本身只是本地 Node 服务（KuGouMusicApi）的前端壳。为了让
/// 发布包在别人的电脑上「装完就能用」，安装目录里随包附带 node 运行时与
/// 服务代码，启动时由本类拉起子进程，退出时回收，用户零配置。
///
/// 端口策略：**不写死 3000**，优先复用上次仍在运行的实例，否则挑一个空闲
/// 端口重启，避免与用户机器上的其它服务抢端口。端口记录在
/// `%APPDATA%\TXMusic\kugou_api.json`，下次启动直接复用。
///
/// 绑定策略：固定 `HOST=127.0.0.1`，只监听回环地址，既不会被防火墙拦，
/// 也不会把本地代理暴露到局域网。
class KugouApiService {
  KugouApiService._({
    required this.port,
    this.process,
    required this.managedByUs,
    required this.directory,
  });

  /// 服务监听端口。
  final int port;

  /// 是否是本进程拉起的（复用已有实例时为 false，退出时不去杀别人的进程）。
  final bool managedByUs;

  /// 服务目录（含 app.js、node.exe）。
  final String directory;

  /// 随包拉起的 node 进程；复用已有实例时为 null。
  Process? process;

  String get baseUrl => 'http://127.0.0.1:$port';

  static KugouApiService? _current;

  /// 已就绪的实例；未启动时为 null。
  static KugouApiService? get current => _current;

  static const String _stateFileName = 'kugou_api.json';
  static const String _logFileName = 'kugou_api.log';

  /// 启动等待上限：冷启动解压 + node 加载模块大约 1~3 秒，给 25 秒兜底。
  static const Duration _bootTimeout = Duration(seconds: 25);

  /// 确保本地服务可用并把结果写进 [KugouConfig]。
  ///
  /// 幂等：重复调用返回同一实例。失败时抛出 [KugouServiceException]，
  /// 由调用方决定是降级为游客还是提示用户。
  static Future<KugouApiService> ensureRunning() async {
    final KugouApiService? started = _current;
    if (started != null) {
      return started;
    }

    // 1) 开发态：显式指定外部服务地址（例如手动 `node app.js`），直接透传。
    if (KugouConfig.hasExplicitBaseUrl) {
      final Uri? uri = Uri.tryParse(KugouConfig.baseUrl);
      final int externalPort = uri?.hasPort == true
          ? uri!.port
          : (uri?.scheme == 'https' ? 443 : 80);
      bootLog('[kugou] 使用外部服务 ${KugouConfig.baseUrl}');
      return _current = KugouApiService._(
        port: externalPort,
        process: null,
        managedByUs: false,
        directory: '',
      );
    }

    final String? dir = _resolveDirectory();
    if (dir == null) {
      throw const KugouServiceException(
        '未找到内嵌的 KuGouMusicApi 服务目录（kugou_api），'
        '请检查安装是否完整。',
      );
    }

    // 2) 上次的实例还活着就直接复用，避免重复拉起与端口漂移。
    final int? alivePort = await _reuseExisting();
    if (alivePort != null) {
      bootLog('[kugou] 复用已运行的服务 127.0.0.1:$alivePort');
      return _current = KugouApiService._(
        port: alivePort,
        process: null,
        managedByUs: false,
        directory: dir,
      );
    }

    // 3) 拉起新进程。
    final String? nodeExe = _resolveNodeExecutable(dir);
    if (nodeExe == null) {
      throw const KugouServiceException(
        '未找到随包的 node 运行时（kugou_api\\node.exe），请重新安装。',
      );
    }

    final int port = await _pickFreePort();
    final Process process = await _spawn(
      nodeExe: nodeExe,
      directory: dir,
      port: port,
    );

    final KugouApiService service = KugouApiService._(
      port: port,
      process: process,
      managedByUs: true,
      directory: dir,
    );

    final bool ready = await service._waitUntilReady();
    if (!ready) {
      await service.shutdown();
      throw KugouServiceException(
        '本地音乐服务启动超时（端口 $port），'
        '可查看日志：${service.logFile.path}',
      );
    }

    await _writeState(port, process.pid);
    bootLog('[kugou] 服务就绪 $baseUrlOf(port)（pid=${process.pid}）');
    return _current = service;
  }

  /// 退出前回收：只杀自己拉起的进程。
  Future<void> shutdown() async {
    final Process? node = process;
    process = null;
    if (managedByUs && node != null) {
      try {
        node.kill();
        await node.exitCode.timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            try {
              node.kill(ProcessSignal.sigkill);
            } on Object catch (_) {}
            return -1;
          },
        );
      } on Object catch (error) {
        debugPrint('回收本地音乐服务失败: $error');
      }
    }
    if (identical(_current, this)) {
      _current = null;
      await _clearState();
    }
  }

  /// 同步回收：进程被强制结束时的兜底（`onBeforeQuit` 已经 await 过异步版）。
  static void shutdownSync() {
    final KugouApiService? service = _current;
    if (service == null) {
      return;
    }
    final Process? node = service.process;
    if (service.managedByUs && node != null) {
      try {
        node.kill();
      } on Object catch (_) {}
    }
    service.process = null;
    _current = null;
  }

  static String baseUrlOf(int port) => 'http://127.0.0.1:$port';

  // --------------------------------------------------------------- 目录定位

  /// 服务目录候选：环境变量优先，其次 exe 同目录（发布包），最后向上找
  /// 工程根下的 `dist/kugou_api`（dev 态 `flutter run` 时 cwd 在 build 目录）。
  static String? _resolveDirectory() {
    final List<String> candidates = <String>[];

    final String? fromEnv = Platform.environment['KUGOU_API_DIR'];
    if (fromEnv != null && fromEnv.trim().isNotEmpty) {
      candidates.add(fromEnv.trim());
    }

    if (!kIsWeb) {
      try {
        candidates.add(
          '${File(Platform.resolvedExecutable).parent.path}'
          '${Platform.pathSeparator}kugou_api',
        );
      } on Object catch (_) {}
    }

    // 从 exe 所在目录向上找（dev 态落到工程根的 dist/kugou_api）。
    // 不用 Directory.current：发布包被快捷方式/资源管理器启动时 cwd 不可靠。
    Directory dir;
    try {
      dir = File(Platform.resolvedExecutable).parent;
    } on Object catch (_) {
      dir = Directory.current;
    }
    for (int depth = 0; depth < 9; depth++) {
      candidates.add(
        '${dir.path}${Platform.pathSeparator}dist'
        '${Platform.pathSeparator}kugou_api',
      );
      final Directory parent = dir.parent;
      if (parent.path == dir.path) {
        break;
      }
      dir = parent;
    }

    for (final String path in candidates) {
      final File entry = File('$path${Platform.pathSeparator}app.js');
      if (entry.existsSync()) {
        return path;
      }
    }
    return null;
  }

  static String? _resolveNodeExecutable(String directory) {
    final String bundled =
        '$directory${Platform.pathSeparator}node.exe';
    if (File(bundled).existsSync()) {
      return bundled;
    }
    // 兜底：PATH 里的 node（开发机装了 Node.js 时也能跑）。
    return 'node';
  }

  // --------------------------------------------------------------- 进程管理

  static Future<Process> _spawn({
    required String nodeExe,
    required String directory,
    required int port,
  }) async {
    final File log = LocalStore.fileOf(_logFileName);
    try {
      final Directory parent = log.parent;
      if (!parent.existsSync()) {
        parent.createSync(recursive: true);
      }
      if (log.existsSync() && log.lengthSync() > 2 * 1024 * 1024) {
        // 超过 2 MB 就重开一份，避免无限增长。
        log.writeAsStringSync('');
      }
    } on Object catch (_) {}

    final Process process = await Process.start(
      nodeExe,
      <String>['app.js', '--port=$port'],
      workingDirectory: directory,
      environment: <String, String>{
        ...Platform.environment,
        // 只监听回环，避免防火墙弹窗与局域网暴露。
        'HOST': '127.0.0.1',
        'PORT': '$port',
        // node 侧不需要交互式颜色输出。
        'NO_COLOR': '1',
      },
      runInShell: false,
    );

    // 必须持续消费管道，否则缓冲区写满会让 node 阻塞在 stdout 上。
    try {
      final IOSink sink = log.openWrite(mode: FileMode.append);
      process.stdout.listen(
        (List<int> chunk) => sink.add(chunk),
        onError: (Object _) {},
        cancelOnError: false,
      );
      process.stderr.listen(
        (List<int> chunk) => sink.add(chunk),
        onError: (Object _) {},
        cancelOnError: false,
      );
      process.exitCode.whenComplete(() async {
        try {
          await sink.flush();
          await sink.close();
        } on Object catch (_) {}
      });
    } on Object catch (error) {
      debugPrint('挂接本地服务日志失败: $error');
      // 退化为直接丢弃输出，至少别让子进程卡死。
      process.stdout.drain<void>();
      process.stderr.drain<void>();
    }

    return process;
  }

  File get logFile => LocalStore.fileOf(_logFileName);

  Future<bool> _waitUntilReady() async {
    final DateTime deadline = DateTime.now().add(_bootTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await _probe(port, timeout: const Duration(milliseconds: 300))) {
        return true;
      }
      // 字段无法被类型提升，先取快照再判空。
      final Process? node = process;
      if (node != null) {
        // 进程提前退出就没必要再等了。
        final bool exited = await _hasExited(node);
        if (exited) {
          debugPrint('本地音乐服务启动即退出，详见 ${logFile.path}');
          return false;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return false;
  }

  static Future<bool> _hasExited(Process process) async {
    try {
      await process.exitCode.timeout(const Duration(milliseconds: 1));
      return true;
    } on TimeoutException {
      return false;
    }
  }

  static Future<bool> _probe(int port, {Duration? timeout}) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: timeout ?? const Duration(milliseconds: 400),
      );
      return true;
    } on Object catch (_) {
      return false;
    } finally {
      socket?.destroy();
    }
  }

  static Future<int> _pickFreePort() async {
    final ServerSocket socket = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final int port = socket.port;
    await socket.close();
    return port;
  }

  // --------------------------------------------------------------- 状态文件

  static Future<int?> _reuseExisting() async {
    try {
      final File file = LocalStore.fileOf(_stateFileName);
      if (!await file.exists()) {
        return null;
      }
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        return null;
      }
      final Object? rawPort = decoded['port'];
      final int? port = rawPort is int ? rawPort : int.tryParse('$rawPort');
      if (port == null || port <= 0 || port > 65535) {
        return null;
      }
      return await _probe(port) ? port : null;
    } on Object catch (_) {
      return null;
    }
  }

  static Future<void> _writeState(int port, int pid) async {
    await LocalStore.writeJson(_stateFileName, <String, dynamic>{
      'port': port,
      'pid': pid,
      'started_at': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> _clearState() async {
    await LocalStore.delete(_stateFileName);
  }
}

/// 内嵌服务不可用（目录缺失 / 运行时缺失 / 启动超时）。
class KugouServiceException implements Exception {
  const KugouServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
