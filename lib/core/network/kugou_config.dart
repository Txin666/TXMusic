import 'dart:io';

/// KuGouMusicApi 本地服务配置（文档 §5 数据层 / API 联调记录）。
///
/// 约定：
/// - 服务地址默认由内嵌服务在运行时注入（见 [KugouApiService]），端口不写死；
///   开发态可用环境变量 `KUGOU_API_BASE_URL` 直连手工启动的 KuGouMusicApi；
/// - 用户数据（登录态 / 收藏 / 播放进度）落在 `%APPDATA%\TXMusic`，安装到
///   `C:\Program Files` 这类只读目录时也能正常写入；
/// - 所有请求必须带 `dfid` cookie，否则接口返回 error_code 152。
class KugouConfig {
  const KugouConfig._();

  /// 未注入运行时地址时的兜底值（等价于手工执行 `node app.js`）。
  static const String defaultBaseUrl = 'http://localhost:3000';

  /// 单次 HTTP 请求超时：/song/url 解析较慢，给足余量。
  static const Duration requestTimeout = Duration(seconds: 20);

  /// 服务端有 2 分钟结果缓存，统一追加毫秒时间戳规避（联调记录 §2）。
  static String get cacheBuster =>
      DateTime.now().millisecondsSinceEpoch.toString();

  static String? _runtimeBaseUrl;

  /// 由内嵌服务启动后注入真实端口；传 null 恢复默认。
  static void setRuntimeBaseUrl(String? url) {
    final String? trimmed = url?.trim();
    _runtimeBaseUrl = (trimmed == null || trimmed.isEmpty)
        ? null
        : trimmed.replaceAll(RegExp(r'/+$'), '');
  }

  /// 显式配置了外部服务地址（开发态手工起服务 / CI 联调）。
  static bool get hasExplicitBaseUrl {
    final String? fromEnv = Platform.environment['KUGOU_API_BASE_URL'];
    return fromEnv != null && fromEnv.trim().isNotEmpty;
  }

  static String get baseUrl {
    final String? fromEnv = Platform.environment['KUGOU_API_BASE_URL'];
    if (fromEnv != null && fromEnv.trim().isNotEmpty) {
      return fromEnv.trim().replaceAll(RegExp(r'/+$'), '');
    }
    final String? runtime = _runtimeBaseUrl;
    if (runtime != null && runtime.isNotEmpty) {
      return runtime;
    }
    return defaultBaseUrl;
  }

  /// 用户数据目录：Windows 用 `%APPDATA%\TXMusic`（可写）；
  /// 其它平台兜底到 `$HOME/.txmusic`。
  static String get dataDirectoryPath {
    final String? override = Platform.environment['TXMUSIC_DATA_DIR'];
    if (override != null && override.trim().isNotEmpty) {
      return override.trim();
    }
    if (Platform.isWindows) {
      final String appData = Platform.environment['APPDATA'] ?? '';
      if (appData.isNotEmpty) {
        return '$appData${Platform.pathSeparator}TXMusic';
      }
    }
    final String home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
    if (home.isNotEmpty) {
      return '$home${Platform.pathSeparator}.txmusic';
    }
    return '${Directory.current.path}${Platform.pathSeparator}.local';
  }

  /// 历史数据目录（工程内 `.local/`）：dev 态已有数据时继续复用，避免升级后
  /// 用户突然变成游客态。
  ///
  /// 探测起点必须是 **exe 所在目录**，不能是 `Directory.current`：
  /// 发布给别人的版本由资源管理器/快捷方式启动时，工作目录未必等于安装目录
  /// （可能是 System32、桌面或父进程带来的任意目录），跟着 cwd 走会把新
  /// 机器的数据目录误判到某个无关位置。
  static String? get legacyDataDirectoryPath {
    Directory dir;
    try {
      dir = File(Platform.resolvedExecutable).parent;
    } on Object catch (_) {
      dir = Directory.current;
    }
    // 只有「工程根」（含 pubspec.yaml）里的 .local 才算历史目录：
    // dev 态 exe 在 build\windows\x64\runner\Debug，向上能找到工程根；
    // 发布包所在目录不是工程，因此绝不会被上级目录里无关的 .local 带偏。
    for (int depth = 0; depth < 9; depth++) {
      final String base = dir.path;
      final bool isProjectRoot =
          File('$base${Platform.pathSeparator}pubspec.yaml').existsSync();
      if (isProjectRoot) {
        final Directory local = Directory(
          '$base${Platform.pathSeparator}.local',
        );
        return local.existsSync() ? local.path : null;
      }
      final Directory parent = dir.parent;
      if (parent.path == dir.path) {
        break;
      }
      dir = parent;
    }
    return null;
  }

  /// cookie 文件候选路径：环境变量 → 用户数据目录 → 历史 `.local/`。
  static List<String> get cookieFileCandidates {
    final List<String> candidates = <String>[];
    final String? fromEnv = Platform.environment['KUGOU_COOKIE_FILE'];
    if (fromEnv != null && fromEnv.trim().isNotEmpty) {
      candidates.add(fromEnv.trim());
    }
    candidates.add(
      '$dataDirectoryPath${Platform.pathSeparator}kugou_cookie.json',
    );
    final String? legacy = legacyDataDirectoryPath;
    if (legacy != null) {
      candidates.add('$legacy${Platform.pathSeparator}kugou_cookie.json');
    }
    return candidates;
  }

  /// 写入 cookie 的首选路径：环境变量指定则用之，否则写用户数据目录
  /// （安装目录通常无写权限）。
  static String get primaryCookieFile {
    final String? fromEnv = Platform.environment['KUGOU_COOKIE_FILE'];
    if (fromEnv != null && fromEnv.trim().isNotEmpty) {
      return fromEnv.trim();
    }
    return '$dataDirectoryPath${Platform.pathSeparator}kugou_cookie.json';
  }
}
