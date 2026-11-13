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
///
/// 必须 `fetchAll: true`：上游分页，单页最多 300 首，歌单详情页只拿第一页会
/// 把大歌单（如 330 首的「我喜欢」）截断成 100 首。
final playlistSongsProvider = FutureProvider.family<List<Song>, String>(
  (Ref ref, String id) =>
      ref.watch(kugouPlaylistApiProvider).songs(id, fetchAll: true),
);
