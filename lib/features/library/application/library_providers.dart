import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../song/domain/song.dart';
import '../data/fake_library_data.dart';

/// 我的音乐：收藏 / 最近播放。
/// TODO(storage): 接入本地 DAO 后改为 AsyncNotifier，并支持收藏/取消收藏写操作。
final favoriteSongsProvider = Provider<List<Song>>(
  (Ref ref) => FakeLibraryData.favoriteSongs,
);

final recentSongsProvider = Provider<List<Song>>(
  (Ref ref) => FakeLibraryData.recentSongs,
);
