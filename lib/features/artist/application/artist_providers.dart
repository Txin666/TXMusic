import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/kugou_providers.dart';
import '../../album/domain/album.dart';
import '../../song/domain/song.dart';
import '../domain/artist.dart';

/// 歌手详情（`/artist/detail`）。
final artistDetailProvider = FutureProvider.family<Artist?, String>(
  (Ref ref, String id) => ref.watch(kugouArtistApiProvider).detail(id),
);

/// 歌手歌曲（`/artist/audios`）。
final artistSongsProvider = FutureProvider.family<List<Song>, String>(
  (Ref ref, String id) => ref.watch(kugouArtistApiProvider).songs(id),
);

/// 歌手专辑（`/artist/albums`）。
final artistAlbumsProvider = FutureProvider.family<List<Album>, String>(
  (Ref ref, String id) => ref.watch(kugouArtistApiProvider).albums(id),
);
