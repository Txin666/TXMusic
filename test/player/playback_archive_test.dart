import 'package:flutter_test/flutter_test.dart';
import 'package:txmusic/features/player/data/playback_archive.dart';
import 'package:txmusic/features/player/domain/playback_state.dart';
import 'package:txmusic/features/song/domain/song.dart';

const Song _songA = Song(
  id: 'a',
  title: '第一首',
  artist: '歌手甲',
  hash: 'hashA',
  albumId: 'album1',
  duration: Duration(seconds: 200),
);

const Song _songB = Song(
  id: 'b',
  title: '第二首',
  artist: '歌手乙',
  hash: 'hashB',
  duration: Duration(seconds: 300),
);

void main() {
  group('PlaybackArchive 序列化', () {
    test('写入 JSON 再读回，曲目 / 队列 / 进度 / 偏好都保持', () {
      const PlaybackArchive archive = PlaybackArchive(
        song: _songB,
        queue: <Song>[_songA, _songB],
        queueIndex: 1,
        position: Duration(seconds: 75),
        duration: Duration(seconds: 300),
        volume: 0.35,
        muted: true,
        repeatMode: RepeatMode.one,
      );

      final Map<String, dynamic> json = archive.toJson();
      final PlaybackArchive? restored = PlaybackArchive.fromJson(json);

      expect(restored, isNotNull);
      expect(restored!.song.id, _songB.id);
      expect(restored.song.title, _songB.title);
      expect(restored.queue.length, 2);
      expect(restored.queue.first.id, _songA.id);
      expect(restored.queueIndex, 1);
      expect(restored.position, const Duration(seconds: 75));
      expect(restored.duration, const Duration(seconds: 300));
      expect(restored.volume, closeTo(0.35, 0.0001));
      expect(restored.muted, isTrue);
      expect(restored.repeatMode, RepeatMode.one);
    });

    test('队列按 queueLimit 截断，避免存档无限膨胀', () {
      final List<Song> big = <Song>[
        for (int i = 0; i < PlaybackArchive.queueLimit + 20; i++)
          Song(id: '$i', title: '歌 $i', artist: '歌手', hash: 'h$i'),
      ];
      final PlaybackArchive archive = PlaybackArchive(song: big.first, queue: big);

      final Object? rawQueue = archive.toJson()['queue'];
      expect(rawQueue, isA<List<dynamic>>());
      expect((rawQueue! as List<dynamic>).length, PlaybackArchive.queueLimit);
    });

    test('缺失歌曲或 hash 为空时解析返回 null（按空态处理）', () {
      expect(PlaybackArchive.fromJson(<String, dynamic>{}), isNull);
      expect(
        PlaybackArchive.fromJson(<String, dynamic>{
          'song': const Song(id: 'x', title: 'x', artist: 'x').toJson(),
        }),
        isNull,
      );
    });

    test('队列索引越界时按歌曲 hash 重新定位', () {
      final PlaybackArchive? parsed = PlaybackArchive.fromJson(<String, dynamic>{
        'song': _songB.toJson(),
        'queue': <dynamic>[_songA.toJson(), _songB.toJson()],
        'queueIndex': 99,
      });

      expect(parsed, isNotNull);
      final PlaybackArchive restored = parsed!;
      expect(restored.queueIndex, 1);
    });

    test('队列为空时自动补上当前曲目', () {
      final PlaybackArchive? parsed = PlaybackArchive.fromJson(<String, dynamic>{
        'song': _songA.toJson(),
      });

      expect(parsed, isNotNull);
      final PlaybackArchive restored = parsed!;
      expect(restored.queue.single.id, _songA.id);
      expect(restored.queueIndex, 0);
    });
  });

  group('PlaybackArchive.resumePosition', () {
    test('正常进度原样保留', () {
      const PlaybackArchive archive = PlaybackArchive(
        song: _songA,
        position: Duration(seconds: 42),
        duration: Duration(seconds: 200),
      );
      expect(archive.resumePosition, const Duration(seconds: 42));
    });

    test('距结尾不足 endTolerance 视为听完，从 0 开始', () {
      final PlaybackArchive archive = PlaybackArchive(
        song: _songA,
        position: const Duration(seconds: 200) - PlaybackArchive.endTolerance,
        duration: const Duration(seconds: 200),
      );
      expect(archive.resumePosition, Duration.zero);
    });

    test('负数与零进度归零', () {
      const PlaybackArchive negative = PlaybackArchive(
        song: _songA,
        position: Duration(seconds: -5),
        duration: Duration(seconds: 200),
      );
      const PlaybackArchive zero = PlaybackArchive(song: _songA);

      expect(negative.resumePosition, Duration.zero);
      expect(zero.resumePosition, Duration.zero);
    });

    test('存档没记时长时退回歌曲自带的时长判断', () {
      const PlaybackArchive archive = PlaybackArchive(
        song: _songA,
        position: Duration(seconds: 198),
      );
      expect(archive.resumePosition, Duration.zero);
    });
  });
}
