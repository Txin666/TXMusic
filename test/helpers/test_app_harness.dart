import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:txmusic/core/audio/i_audio_engine.dart';
import 'package:txmusic/core/network/kugou_providers.dart';
import 'package:txmusic/core/network/kugou_session.dart';
import 'package:txmusic/features/discover/application/discover_providers.dart';
import 'package:txmusic/features/library/application/library_providers.dart';
import 'package:txmusic/features/playlist/domain/playlist.dart';
import 'package:txmusic/features/rank/application/rank_providers.dart';
import 'package:txmusic/features/rank/domain/rank_item.dart';
import 'package:txmusic/features/search/application/search_controller.dart';
import 'package:txmusic/features/song/domain/song.dart';

/// 测试专用桩数据与 Provider 覆盖集合。
///
/// 设计约束（与业务代码解耦）：
/// - 不引用任何 `fake_*_data.dart`（那些文件已下线，测试数据只存在于 test 目录）；
/// - 不触碰 media_kit / libmpv / 真实网络，全部通过 [ProviderScope] overrides 注入；
/// - 覆盖项只替换「数据来源」与「音频引擎」，不改动 lib 下的业务逻辑。

/// 假音频引擎：只记录调用，不加载任何原生解码库。
class FakeAudioEngine implements AudioEngine {
  final StreamController<AudioEngineEvent> _controller =
      StreamController<AudioEngineEvent>.broadcast();

  final List<Uri> openedUrls = <Uri>[];
  final List<double> volumes = <double>[];
  int playCount = 0;
  int pauseCount = 0;
  int stopCount = 0;
  int disposeCount = 0;
  Duration? lastSeek;

  @override
  Stream<AudioEngineEvent> get events => _controller.stream;

  /// 主动推送一个引擎事件，用于模拟播放进度 / 完成 / 错误。
  void emit(AudioEngineEvent event) {
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }

  @override
  Future<void> open(Uri url, {bool autoPlay = true}) async {
    openedUrls.add(url);
  }

  @override
  Future<void> play() async {
    playCount++;
  }

  @override
  Future<void> pause() async {
    pauseCount++;
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }

  @override
  Future<void> seek(Duration position) async {
    lastSeek = position;
  }

  @override
  Future<void> setVolume(double volume) async {
    volumes.add(volume);
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
    await _controller.close();
  }
}

/// 内存版音乐库：避免测试读写 `.local/` 下的真实 JSON 文件。
class FakeLibraryController extends LibraryController {
  @override
  LibraryState build() => const LibraryState(isLoading: false);

  @override
  Future<void> refresh() async {}

  @override
  Future<void> toggleFavorite(Song song) async {}

  @override
  Future<void> recordPlayed(Song song) async {}

  @override
  Future<void> clearRecent() async {}
}

/// 榜单桩数据（标题与真实接口命名一致，便于断言）。
const List<RankItem> kTestRanks = <RankItem>[
  RankItem(
    id: '8888',
    title: 'TX 飙升榜',
    subtitle: '飙升最快的歌曲',
    updateNote: '每日更新',
    intro: '根据播放量涨幅实时更新',
    playCount: 1234567,
  ),
  RankItem(
    id: '6666',
    title: 'TX 热歌榜',
    subtitle: '最热单曲',
    updateNote: '每周更新',
    intro: '一周内播放量最高的单曲',
    playCount: 7654321,
  ),
];

/// 歌曲桩数据：`coverUrl` 留空，避免测试触发网络图片请求。
const List<Song> kTestSongs = <Song>[
  Song(
    id: 'song-1',
    title: '晴天',
    artist: '周杰伦',
    album: '叶惠美',
    albumId: 'album-1',
    duration: Duration(minutes: 4, seconds: 29),
    hash: 'hash-1',
  ),
  Song(
    id: 'song-2',
    title: '稻香',
    artist: '周杰伦',
    album: '魔杰座',
    albumId: 'album-2',
    duration: Duration(minutes: 3, seconds: 43),
    hash: 'hash-2',
  ),
  Song(
    id: 'song-3',
    title: '夜曲',
    artist: '周杰伦',
    album: '十一月的萧邦',
    albumId: 'album-3',
    duration: Duration(minutes: 3, seconds: 46),
    hash: 'hash-3',
  ),
];

/// 歌单桩数据。
const List<Playlist> kTestPlaylists = <Playlist>[
  Playlist(
    id: 'playlist-1',
    title: '华语热歌',
    creator: '酷狗音乐',
    playCount: 9876543,
    trackCount: 50,
  ),
];

/// 发现页聚合桩数据。
const DiscoverFeed kTestDiscoverFeed = DiscoverFeed(
  dailySongs: kTestSongs,
  playlists: kTestPlaylists,
  ranks: kTestRanks,
);

/// 构造一组可复用的测试 overrides。
///
/// 覆盖内容：
/// - [audioEngineProvider] → [FakeAudioEngine]（不加载 libmpv / media_kit 原生库）
/// - [kugouSessionProvider] → 游客态（不读 `.local/kugou_cookie.json`）
/// - [libraryProvider] → [FakeLibraryController]（不读写本地 JSON）
/// - 各数据 FutureProvider → 桩数据（不发 HTTP 请求）
List<Override> buildTestOverrides({FakeAudioEngine? engine}) {
  final FakeAudioEngine fakeEngine = engine ?? FakeAudioEngine();

  return <Override>[
    audioEngineProvider.overrideWith((Ref ref) => fakeEngine),
    kugouSessionProvider.overrideWith(
      () => KugouSessionController(KugouSession.guest),
    ),
    libraryProvider.overrideWith(FakeLibraryController.new),
    discoverFeedProvider.overrideWith((Ref ref) async => kTestDiscoverFeed),
    rankListProvider.overrideWith((Ref ref) async => kTestRanks),
    rankItemProvider.overrideWith((Ref ref, String id) async {
      for (final RankItem item in kTestRanks) {
        if (item.id == id) {
          return item;
        }
      }
      return null;
    }),
    rankSongsProvider.overrideWith((Ref ref, String rankId) async => kTestSongs),
    hotKeywordsProvider.overrideWith(
      (Ref ref) async => const <String>['周杰伦', '晴天', '华语流行'],
    ),
  ];
}
