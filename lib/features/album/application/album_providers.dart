import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/kugou_providers.dart';
import '../../song/domain/song.dart';
import '../domain/album.dart';

/// 专辑详情（`/album/detail`）。
final albumDetailProvider = FutureProvider.family<Album?, String>(
  (Ref ref, String id) => ref.watch(kugouAlbumApiProvider).detail(id),
);

/// 专辑曲目（`/album/songs`）。
final albumSongsProvider = FutureProvider.family<List<Song>, String>(
  (Ref ref, String id) => ref.watch(kugouAlbumApiProvider).songs(id),
);
