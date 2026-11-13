import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:txmusic/core/network/kugou_client.dart';
import 'package:txmusic/core/network/kugou_session.dart';
import 'package:txmusic/features/player/data/song_url_resolver.dart';
import 'package:txmusic/features/song/data/kugou_song_api.dart';
import 'package:txmusic/features/song/domain/song.dart';

/// 真实音频解码冒烟测试：搜索 → 解析音源 → media_kit 实际出声（只验证播放位置推进）。
///
/// 该用例依赖两样本机资源，缺任意一样都会**优雅跳过**而不是失败：
/// 1. `libmpv-2.dll`（media_kit Windows 解码库）；
/// 2. 本机运行的 KuGouMusicApi HTTP 服务（真实酷狗接口）。
///
/// 需要实际执行时，把解码库所在目录加入 PATH：
/// ```
/// $env:PATH = "$PWD\build\windows\x64\runner\Debug;$env:PATH"
/// flutter test test/media_playback_smoke_test.dart
/// ```
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final String? libmpvPath = _usableLibmpv();

  test(
    'media_kit 能真实播放解析出的 mp3 且进度推进',
    () async {
      // flutter_test 默认接管 HttpClient（一律返回 400），这里恢复真实网络。
      HttpOverrides.global = null;

      MediaKit.ensureInitialized();

      final KugouSession session = await KugouSession.load();
      final KugouClient client = KugouClient(session: session);
      final KugouSongApi api = KugouSongApi(client);
      final Player player = Player();

      final List<Duration> positions = <Duration>[];
      final List<String> errors = <String>[];
      final StreamSubscription<Duration> sub = player.stream.position.listen(
        positions.add,
      );
      final StreamSubscription<String> errSub = player.stream.error.listen(
        errors.add,
      );

      try {
        final List<Song> songs = await api.search('晴天 周杰伦', pageSize: 5);
        final ResolvedAudio audio = await SongUrlResolver(client)
            .resolve(songs.first);

        await player.open(Media(audio.url.toString()), play: true);
        await Future<void>.delayed(const Duration(seconds: 6));

        // ignore: avoid_print
        print(
          '[playback] libmpv=$libmpvPath duration=${player.state.duration} '
          'positions=${positions.map((Duration p) => p.inMilliseconds).toList()} '
          'errors=$errors',
        );

        expect(player.state.duration.inSeconds, greaterThan(0));
        expect(positions, isNotEmpty);
        expect(positions.last.inMilliseconds, greaterThan(1000));
        expect(errors, isEmpty);
      } finally {
        await sub.cancel();
        await errSub.cancel();
        await player.dispose();
        client.dispose();
      }
    },
    // 缺少 libmpv-2.dll（CI / 干净虚拟机）时跳过：媒体能力属于本机环境依赖，
    // 不应让环境缺失被判定为代码失败。
    skip: libmpvPath == null
        ? '当前环境无法加载 libmpv-2.dll，跳过真实解码冒烟测试'
              '（把可用的 build\\windows\\x64\\runner\\Debug 加入 PATH 后可运行）'
        : null,
    timeout: const Timeout(Duration(seconds: 120)),
  );
}

/// 返回**可被实际加载**的 `libmpv-2.dll` 路径，无法加载时返回 null。
///
/// 只判断文件是否存在不够——构建目录里可能残留不可用的 DLL（依赖缺失 /
/// 架构不符），此时 media_kit 仍会在 `ensureInitialized` 抛异常。这里用
/// [DynamicLibrary.open] 做一次真实加载探测，与 media_kit 内部判定保持一致：
/// 探测失败即视为环境不具备解码能力，测试应跳过而不是失败。
String? _usableLibmpv() {
  if (!Platform.isWindows) {
    return null;
  }

  const String dllName = 'libmpv-2.dll';

  // 1) 走系统 DLL 搜索路径（与 media_kit 的行为一致）。
  try {
    DynamicLibrary.open(dllName);
    return dllName;
  } on ArgumentError {
    // 继续尝试显式路径。
  }

  // 2) 显式路径探测：PATH + 常见构建产物目录。
  final String cwd = Directory.current.path;
  final List<String> candidates = <String>[
    cwd,
    '$cwd\\build\\windows\\x64\\runner\\Debug',
    '$cwd\\build\\windows\\x64\\runner\\Release',
    '$cwd\\build\\windows\\x64\\runner\\Profile',
  ];

  final String? pathEnv = Platform.environment['PATH'];
  if (pathEnv != null && pathEnv.isNotEmpty) {
    candidates.addAll(
      pathEnv.split(';').where((String entry) => entry.trim().isNotEmpty),
    );
  }

  for (final String dir in candidates) {
    final String normalized = dir.trim().replaceAll(RegExp(r'[\\/]+$'), '');
    if (normalized.isEmpty) {
      continue;
    }
    final String candidate = '$normalized\\$dllName';
    try {
      if (!File(candidate).existsSync()) {
        continue;
      }
      DynamicLibrary.open(candidate);
      return candidate;
    } on FileSystemException {
      continue;
    } on ArgumentError {
      continue;
    }
  }
  return null;
}
