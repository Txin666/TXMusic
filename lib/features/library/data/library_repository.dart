import '../../../core/storage/local_store.dart';
import '../../song/domain/song.dart';

/// 收藏 / 最近播放的本地持久化（`.local/favorites.json`、`.local/recent.json`）。
///
/// 不引入 Hive/数据库，纯 JSON 落盘，与登录态同目录，方便直接查看与备份。
class LibraryRepository {
  const LibraryRepository();

  static const String favoritesFile = 'favorites.json';
  static const String recentFile = 'recent.json';

  /// 最近播放最多保留条数。
  static const int recentLimit = 100;

  Future<List<Song>> loadFavorites() => _load(favoritesFile);

  Future<List<Song>> loadRecent() => _load(recentFile);

  /// 收藏 / 取消收藏，返回最新收藏列表。
  Future<List<Song>> toggleFavorite(Song song) async {
    final List<Song> favorites = await loadFavorites();
    final bool exists = favorites.any((Song item) => item.hash == song.hash);
    final List<Song> next = exists
        ? favorites.where((Song item) => item.hash != song.hash).toList()
        : <Song>[song, ...favorites];
    await _save(favoritesFile, next);
    return next;
  }

  /// 记录最近播放（去重后置顶，超限截断）。
  Future<List<Song>> pushRecent(Song song) async {
    final List<Song> recent = await loadRecent();
    final List<Song> next = <Song>[
      song,
      ...recent.where((Song item) => item.hash != song.hash),
    ].take(recentLimit).toList(growable: false);
    await _save(recentFile, next);
    return next;
  }

  Future<void> clearRecent() async {
    await LocalStore.writeJson(recentFile, <String, dynamic>{'songs': <Object>[]});
  }

  Future<List<Song>> _load(String name) async {
    final Map<String, dynamic> json = await LocalStore.readJson(name);
    final Object? raw = json['songs'];
    if (raw is! List) {
      return const <Song>[];
    }
    final List<Song> songs = <Song>[];
    for (final Object? item in raw) {
      final Song? song = Song.fromJson(item);
      if (song != null) {
        songs.add(song);
      }
    }
    return songs;
  }

  Future<void> _save(String name, List<Song> songs) async {
    await LocalStore.writeJson(name, <String, dynamic>{
      'songs': songs.map((Song song) => song.toJson()).toList(),
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }
}
