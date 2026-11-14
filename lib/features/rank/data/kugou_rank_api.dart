import '../../../core/network/json_utils.dart';
import '../../../core/network/kugou_client.dart';
import '../../song/data/song_mappers.dart';
import '../../song/domain/song.dart';
import '../domain/rank_item.dart';

/// 排行榜接口：榜单列表 + 榜单歌曲。
class KugouRankApi {
  KugouRankApi(this._client);

  final KugouClient _client;

  Future<List<RankItem>> list() async {
    final Map<String, dynamic> json = await _client.getJson('/rank/list');
    final Map<String, dynamic>? data = JsonUtils.asMap(json['data']);
    final Object? raw = data?['info'] ?? json['info'];
    return JsonUtils.asMapList(raw)
        .map(RankItem.fromJson)
        .whereType<RankItem>()
        .toList(growable: false);
  }

  /// 榜单曲目（`/rank/audio?rankid=`，字段在 `audio_info` 嵌套层）。
  ///
  /// **翻页约束（实测）**：上游 `pagesize` 固定 100 时，曲目数超过 100 的榜单
  /// 会被静默截断（`data.total` 才是真实曲目数）。`fetchAll: true`（默认）时
  /// 按 `total` 自动翻页拉全，单页上限 [_maxPageSize]（实测 1000 仍有效，
  /// 保守取 500），并跨页按 hash 去重。
  Future<List<Song>> songs(
    String rankId, {
    int page = 1,
    int pageSize = 100,
    bool fetchAll = true,
  }) async {
    if (rankId.isEmpty) {
      return const <Song>[];
    }
    if (!fetchAll) {
      final Map<String, dynamic>? data = await _fetchPage(rankId, page, pageSize);
      if (data == null) {
        return const <Song>[];
      }
      return SongMappers.listFrom(_songListOf(data), dedupe: true);
    }

    final List<Song> songs = <Song>[];
    final Set<String> seen = <String>{};
    int total = 0;
    for (int current = 1; current <= _maxPages; current++) {
      final Map<String, dynamic>? data = await _fetchPage(
        rankId,
        current,
        _maxPageSize,
      );
      if (data == null) {
        break;
      }
      total = JsonUtils.integer(
        JsonUtils.pick(data, const <String>['total', 'song_count', 'count']),
        fallback: total,
      );
      final List<Song> pageSongs = SongMappers.listFrom(_songListOf(data));
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
      // total 缺失时靠"本页不满"与空页兜底。
      if (total <= 0 && pageSongs.length < _maxPageSize) {
        break;
      }
    }
    return songs;
  }

  /// 上游单页上限：`pagesize` 实测支持到 1000，保守取 500 控制单次响应体积。
  static const int _maxPageSize = 500;

  /// 翻页保护上限，防止上游 `total` 异常时无限请求。
  static const int _maxPages = 20;

  static Object? _songListOf(Map<String, dynamic> data) =>
      data['songlist'] ?? data['songs'] ?? data['info'];

  Future<Map<String, dynamic>?> _fetchPage(
    String rankId,
    int page,
    int pageSize,
  ) async {
    final Map<String, dynamic> json = await _client.getJson(
      '/rank/audio',
      query: <String, dynamic>{
        'rankid': rankId,
        'page': page,
        'pagesize': pageSize,
      },
    );
    return JsonUtils.asMap(json['data']);
  }
}
