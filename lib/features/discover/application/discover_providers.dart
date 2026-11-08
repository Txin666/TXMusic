import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../album/domain/album.dart';
import '../../artist/domain/artist.dart';
import '../../playlist/domain/playlist.dart';
import '../../song/domain/song.dart';
import '../data/fake_discover_data.dart';
import '../domain/discover_banner.dart';

/// 发现页各区块数据。
/// 骨架期直接返回假数据；接入接口后改为 `FutureProvider` / `AsyncNotifierProvider`（见文档 §9.2）。
final discoverBannersProvider = Provider<List<DiscoverBanner>>(
  (Ref ref) => FakeDiscoverData.banners,
);

final recommendedPlaylistsProvider = Provider<List<Playlist>>(
  (Ref ref) => FakeDiscoverData.recommendedPlaylists,
);

final recommendedAlbumsProvider = Provider<List<Album>>(
  (Ref ref) => FakeDiscoverData.recommendedAlbums,
);

final recommendedArtistsProvider = Provider<List<Artist>>(
  (Ref ref) => FakeDiscoverData.recommendedArtists,
);

final newSongsProvider = Provider<List<Song>>(
  (Ref ref) => FakeDiscoverData.newSongs,
);
