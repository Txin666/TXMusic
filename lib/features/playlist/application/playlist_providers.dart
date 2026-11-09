import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/kugou_providers.dart';
import '../../song/domain/song.dart';
import '../domain/playlist.dart';

/// 推荐 / 广场歌单列表（`/top/playlist`）。
final playlistFeedProvider = FutureProvider<List<Playlist>>(
  (Ref ref) => ref.watch(kugouPlaylistApiProvider).topPlaylists(),
);

/// 歌单详情（`/playlist/detail`）。
final playlistDetailProvider = FutureProvider.family<Playlist?, String>(
  (Ref ref, String id) => ref.watch(kugouPlaylistApiProvider).detail(id),
);

/// 歌单曲目（`/playlist/track/all`）。
final playlistSongsProvider = FutureProvider.family<List<Song>, String>(
  (Ref ref, String id) => ref.watch(kugouPlaylistApiProvider).songs(id),
);
