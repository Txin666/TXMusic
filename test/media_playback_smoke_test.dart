import 'dart:async';
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
/// 需要先把 `build\windows\x64\runner\Debug`（含 libmpv-2.dll）加入 PATH，否则
/// media_kit 找不到本地库：
/// ```
/// $env:PATH = "$PWD\build\windows\x64\runner\Debug;$env:PATH"
/// flutter test test/media_playback_smoke_test.dart
/// ```
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // flutter_test 默认接管 HttpClient（一律返回 400），这里恢复真实网络。
  setUpAll(() => HttpOverrides.global = null);

  test('media_kit 能真实播放解析出的 mp3 且进度推进', () async {
    MediaKit.ensureInitialized();

    final KugouSession session = await KugouSession.load();
    final KugouClient client = KugouClient(session: session);
    final KugouSongApi api = KugouSongApi(client);
    final Player player = Player();

    final List<Duration> positions = <Duration>[];
    final List<String> errors = <String>[];
    final StreamSubscription<Duration> sub =
        player.stream.position.listen(positions.add);
    final StreamSubscription<String> errSub =
        player.stream.error.listen(errors.add);

    try {
      final List<Song> songs = await api.search('晴天 周杰伦', pageSize: 5);
      final ResolvedAudio audio = await SongUrlResolver(client).resolve(songs.first);

      await player.open(Media(audio.url.toString()), play: true);
      await Future<void>.delayed(const Duration(seconds: 6));

      // ignore: avoid_print
      print('[playback] duration=${player.state.duration} '
          'positions=${positions.map((Duration p) => p.inMilliseconds).toList()} '
          'errors=$errors');

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
  }, timeout: const Timeout(Duration(seconds: 120)));
}
