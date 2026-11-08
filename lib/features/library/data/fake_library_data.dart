import '../../song/data/fake_song_data.dart';
import '../../song/domain/song.dart';

/// 骨架期假数据：我的音乐（收藏 / 最近播放）。
///
/// TODO(storage): 接入 `services/storage/dao/history_dao.dart`、`playlist_dao.dart`
/// 后替换为 `LibraryController`（见文档 §8 本地持久化）。
class FakeLibraryData {
  const FakeLibraryData._();

  static List<Song> get favoriteSongs => FakeSongs.slice(0, 6);

  static List<Song> get recentSongs => FakeSongs.slice(5, 6);

  /// 最近播放的播放时间（用于列表右侧展示）。
  static DateTime recentTimeAt(int index) =>
      DateTime.now().subtract(Duration(hours: 2 + index * 5));
}
