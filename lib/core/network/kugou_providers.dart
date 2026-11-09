import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/i_audio_engine.dart';
import '../audio/media_kit_audio_engine.dart';
import '../../features/player/data/song_url_resolver.dart';
import '../../features/song/data/kugou_song_api.dart';
import 'kugou_client.dart';
import 'kugou_session.dart';

/// 登录态：启动时在 `main()` 中加载，并通过 `ProviderScope.overrides` 注入。
///
/// 默认值是游客态，保证未执行 main bootstrap 的单元测试也能跑通。
final Provider<KugouSession> kugouSessionProvider =
    Provider<KugouSession>((Ref ref) => KugouSession.guest);

/// 接口客户端：持有 dfid / cookie，负责时间戳与错误码收敛。
final Provider<KugouClient> kugouClientProvider = Provider<KugouClient>(
  (Ref ref) {
    final KugouSession session = ref.watch(kugouSessionProvider);
    final KugouClient client = KugouClient(session: session);
    ref.onDispose(client.dispose);
    return client;
  },
);

/// 歌曲接口（搜索等）。
final Provider<KugouSongApi> kugouSongApiProvider = Provider<KugouSongApi>(
  (Ref ref) => KugouSongApi(ref.watch(kugouClientProvider)),
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
