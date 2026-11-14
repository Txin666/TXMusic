import '../../../core/network/json_utils.dart';
import '../../../core/network/kugou_client.dart';
import '../../album/domain/album.dart';
import '../../song/data/song_mappers.dart';
import '../../song/domain/song.dart';
import '../domain/artist.dart';

/// 歌手接口：详情、歌曲、专辑。
class KugouArtistApi {
  KugouArtistApi(this._client);

  final KugouClient _client;

  Future<Artist?> detail(String id) async {
    if (id.isEmpty) {
      return null;
    }
    final Map<String, dynamic> json = await _client.getJson(
      '/artist/detail',
      query: <String, dynamic>{'id': id},
    );
    final Object? data = json['data'];
    final Map<String, dynamic>? map = JsonUtils.asMap(data);
    if (map != null) {
      return Artist.fromJson(map);
    }
    final List<Map<String, dynamic>> list = JsonUtils.asMapList(data);
    return list.isEmpty ? null : Artist.fromJson(list.first);
  }

  /// 歌手歌曲（`/artist/audios`，扁平结构，hash 字段直接可用）。
  ///
  /// **翻页约束（实测）**：`pagesize` 实际支持到 1000（50 / 100 / 200 / 500 /
  /// 1000 实测都按需返回），但上游**不返回 `total`**，所以只能靠「本页不满
  /// 即到底」判断结束；页码越界或参数非法时上游报 502，同样视为列表结束。
  /// `fetchAll: true`（默认）时单页固定 [_maxPageSize]、逐页递增，
  /// 跨页按 hash 去重。
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
      final List<Map<String, dynamic>> raw = await _fetchPage(id, page, pageSize);
      return SongMappers.listFrom(raw, dedupe: true);
    }

    final List<Song> songs = <Song>[];
    final Set<String> seen = <String>{};
    for (int current = 1; current <= _maxPages; current++) {
      final List<Map<String, dynamic>> raw = await _fetchPage(
        id,
        current,
        _maxPageSize,
      );
      if (raw.isEmpty) {
        break;
      }
      final List<Song> pageSongs = SongMappers.listFrom(raw);
      if (pageSongs.isEmpty) {
        break;
      }
      for (final Song song in pageSongs) {
        if (seen.add(song.hash)) {
          songs.add(song);
        }
      }
      // 本页不满一页说明已经到底（上游没有 total 字段）。
      if (pageSongs.length < _maxPageSize) {
        break;
      }
    }
    return songs;
  }

  /// 单页上限：实测 1000 仍可返回，取 500 控制单次响应体大小与耗时。
  static const int _maxPageSize = 500;

  /// 翻页保护上限（500 × 20 = 10000 首），防止上游异常时无限请求。
  static const int _maxPages = 20;

  /// 拉单页；页码越界时上游报 502，这里收敛成空列表表示"没有更多了"。
  Future<List<Map<String, dynamic>>> _fetchPage(
    String id,
    int page,
    int pageSize,
  ) async {
    try {
      final Map<String, dynamic> json = await _client.getJson(
        '/artist/audios',
        query: <String, dynamic>{'id': id, 'page': page, 'pagesize': pageSize},
      );
      return JsonUtils.asMapList(json['data']);
    } on KugouApiException catch (error) {
      if (error.code == 502) {
        return const <Map<String, dynamic>>[];
      }
      rethrow;
    }
  }

  /// 歌手专辑（`/artist/albums`）。
  Future<List<Album>> albums(
    String id, {
    int page = 1,
    int pageSize = 50,
  }) async {
    if (id.isEmpty) {
      return const <Album>[];
    }
    final Map<String, dynamic> json = await _client.getJson(
      '/artist/albums',
      query: <String, dynamic>{'id': id, 'page': page, 'pagesize': pageSize},
    );
    return JsonUtils.asMapList(json['data'])
        .map(Album.fromJson)
        .whereType<Album>()
        .toList(growable: false);
  }
}
