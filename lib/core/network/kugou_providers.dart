import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/album/data/kugou_album_api.dart';
import '../../features/artist/data/kugou_artist_api.dart';
import '../../features/auth/data/kugou_login_api.dart';
import '../../features/discover/data/kugou_discover_api.dart';
import '../../features/lyric/data/kugou_lyric_api.dart';
import '../../features/player/data/song_url_resolver.dart';
import '../../features/playlist/data/kugou_playlist_api.dart';
import '../../features/rank/data/kugou_rank_api.dart';
import '../../features/search/data/kugou_search_api.dart';
import '../../features/song/data/kugou_song_api.dart';
import '../audio/i_audio_engine.dart';
import '../audio/media_kit_audio_engine.dart';
import 'kugou_client.dart';
import 'kugou_session.dart';

/// 登录态控制器。
///
/// 启动时由 `main()` 加载 `.local/kugou_cookie.json` 并注入初始值；
/// 扫码登录成功 / 退出登录都通过它改写，[kugouClientProvider] 会随之重建，
/// 保证后续请求立刻带上新 cookie。
class KugouSessionController extends Notifier<KugouSession> {
  KugouSessionController([this._initial = KugouSession.guest]);

  final KugouSession _initial;

  @override
  KugouSession build() => _initial;

  /// 登录成功后落库并切换运行期登录态。
  Future<void> signIn(KugouSession session) async {
    final KugouSession merged = session.copyWith(
      baseUrl: state.baseUrl,
      dfid: session.dfid.isNotEmpty ? session.dfid : state.dfid,
    );
    await merged.persist();
    state = merged;
  }

  /// 退出登录：删本地 cookie，退回游客态（保留 dfid 以便继续浏览）。
  Future<void> signOut() async {
    await KugouSession.clearPersisted();
    state = KugouSession.guest.copyWith(
      dfid: state.dfid,
      baseUrl: state.baseUrl,
    );
  }
}

/// 登录态：默认游客态，`main()` 通过 `overrideWith` 注入真实值。
final NotifierProvider<KugouSessionController, KugouSession>
    kugouSessionProvider =
    NotifierProvider<KugouSessionController, KugouSession>(
  KugouSessionController.new,
);

/// 接口客户端：持有 dfid / cookie，负责时间戳与错误码收敛。
final Provider<KugouClient> kugouClientProvider = Provider<KugouClient>(
  (Ref ref) {
    final KugouSession session = ref.watch(kugouSessionProvider);
    final KugouClient client = KugouClient(session: session);
    ref.onDispose(client.dispose);
    return client;
  },
);

/// 歌曲接口（搜索歌曲 / 歌曲映射）。
final Provider<KugouSongApi> kugouSongApiProvider = Provider<KugouSongApi>(
  (Ref ref) => KugouSongApi(ref.watch(kugouClientProvider)),
);

/// 聚合搜索（歌曲 + 歌单 + 歌手 + 专辑 + 热搜词）。
final Provider<KugouSearchApi> kugouSearchApiProvider =
    Provider<KugouSearchApi>(
  (Ref ref) => KugouSearchApi(ref.watch(kugouClientProvider)),
);

/// 歌单接口。
final Provider<KugouPlaylistApi> kugouPlaylistApiProvider =
    Provider<KugouPlaylistApi>(
  (Ref ref) => KugouPlaylistApi(ref.watch(kugouClientProvider)),
);

/// 专辑接口。
final Provider<KugouAlbumApi> kugouAlbumApiProvider = Provider<KugouAlbumApi>(
  (Ref ref) => KugouAlbumApi(ref.watch(kugouClientProvider)),
);

/// 歌手接口。
final Provider<KugouArtistApi> kugouArtistApiProvider =
    Provider<KugouArtistApi>(
  (Ref ref) => KugouArtistApi(ref.watch(kugouClientProvider)),
);

/// 排行榜接口。
final Provider<KugouRankApi> kugouRankApiProvider = Provider<KugouRankApi>(
  (Ref ref) => KugouRankApi(ref.watch(kugouClientProvider)),
);

/// 发现页接口（每日推荐等）。
final Provider<KugouDiscoverApi> kugouDiscoverApiProvider =
    Provider<KugouDiscoverApi>(
  (Ref ref) => KugouDiscoverApi(ref.watch(kugouClientProvider)),
);

/// 歌词接口。
final Provider<KugouLyricApi> kugouLyricApiProvider = Provider<KugouLyricApi>(
  (Ref ref) => KugouLyricApi(ref.watch(kugouClientProvider)),
);

/// 扫码登录接口。
final Provider<KugouLoginApi> kugouLoginApiProvider = Provider<KugouLoginApi>(
  (Ref ref) => KugouLoginApi(ref.watch(kugouClientProvider)),
);

/// 音源解析器。
final Provider<SongUrlResolver> songUrlResolverProvider =
    Provider<SongUrlResolver>(
  (Ref ref) => SongUrlResolver(ref.watch(kugouClientProvider)),
);

/// 音频引擎：全局单例，生命周期跟随 ProviderScope。
final Provider<AudioEngine> audioEngineProvider = Provider<AudioEngine>(
  (Ref ref) {
    final MediaKitAudioEngine engine = MediaKitAudioEngine();
    ref.onDispose(engine.dispose);
    return engine;
  },
);
