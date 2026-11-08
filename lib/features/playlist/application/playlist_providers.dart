import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/fake_playlist_data.dart';
import '../domain/playlist.dart';

/// 歌单列表 / 歌单详情（骨架期假数据，按 id 参数化）。
/// 接入接口后改为 `FutureProvider.family` 或 `autoDispose` 的 controller（文档 §9.2）。
final playlistListProvider = Provider<List<Playlist>>(
  (Ref ref) => FakePlaylists.all,
);

final playlistDetailProvider = Provider.family<Playlist, String>(
  (Ref ref, String id) => FakePlaylists.byId(id),
);
