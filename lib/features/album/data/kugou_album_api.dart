import '../../../core/network/json_utils.dart';
import '../../../core/network/kugou_client.dart';
import '../../song/data/song_mappers.dart';
import '../../song/domain/song.dart';
import '../domain/album.dart';

/// 专辑接口：专辑详情 + 专辑歌曲。
class KugouAlbumApi {
  KugouAlbumApi(this._client);

  final KugouClient _client;

  Future<Album?> detail(String id) async {
    if (id.isEmpty) {
      return null;
    }
    final Map<String, dynamic> json = await _client.getJson(
      '/album/detail',
      query: <String, dynamic>{'id': id},
    );
    final Object? data = json['data'];
    final List<Map<String, dynamic>> list = JsonUtils.asMapList(data);
    if (list.isNotEmpty) {
      return Album.fromJson(list.first);
    }
    final Map<String, dynamic>? map = JsonUtils.asMap(data);
    return map == null ? null : Album.fromJson(map);
  }

  /// 专辑歌曲（`/album/songs`，字段嵌在 `base` / `audio_info` 里，靠映射层收敛）。
  ///
  /// **翻页约束（实测）**：`pagesize` 超过 50 上游直接返回 502，因此单页固定
  /// [_maxPageSize] = 50；`fetchAll: true`（默认）时按 `data.total` 翻页拉全，
  /// 跨页按 hash 去重。曲目多的合辑 / 精选集在旧实现（固定 pagesize 100）
  /// 下会被上游拒绝或静默截断。
  Future<List<Song>> songs(
    String id, {
    int page = 1,
    int pageSize = _maxPageSize,
    bool fetchAll = true,
  }) async {
    if (id.isEmpty) {
      return const <Song>[];
    }
    if (!fetchAll) {
      final Map<String, dynamic>? data = await _fetchPage(id, page, pageSize);
      if (data == null) {
        return const <Song>[];
      }
      return SongMappers.listFrom(data['songs'], dedupe: true);
    }

    final List<Song> songs = <Song>[];
    final Set<String> seen = <String>{};
    int total = 0;
    for (int current = 1; current <= _maxPages; current++) {
      final Map<String, dynamic>? data = await _fetchPage(
        id,
        current,
        _maxPageSize,
      );
      if (data == null) {
        break;
      }
      total = JsonUtils.integer(
        JsonUtils.pick(data, const <String>['total', 'count', 'song_count']),
        fallback: total,
      );
      final List<Song> pageSongs = SongMappers.listFrom(data['songs']);
      if (pageSongs.isEmpty) {
        break;
      }
      for (final Song song in pageSongs) {
        if (seen.add(song.hash)) {
          songs.add(song);
        }
      }
      if (total > 0 && current >= (total / _maxPageSize).ceil()) {
        break;
      }
      if (total <= 0 && pageSongs.length < _maxPageSize) {
        break;
      }
    }
    return songs;
  }

  /// 上游单页上限：`pagesize` 大于 50 会被上游拒绝（502），固定 50。
  static const int _maxPageSize = 50;

  /// 翻页保护上限，防止上游 `total` 异常时无限请求（50 × 20 = 1000 首）。
  static const int _maxPages = 20;

  Future<Map<String, dynamic>?> _fetchPage(
    String id,
    int page,
    int pageSize,
  ) async {
    final Map<String, dynamic> json = await _client.getJson(
      '/album/songs',
      query: <String, dynamic>{
        'id': id,
        'page': page,
        'pagesize': pageSize,
      },
    );
    return JsonUtils.asMap(json['data']);
  }
}
