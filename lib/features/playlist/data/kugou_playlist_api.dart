import '../../../core/network/json_utils.dart';
import '../../../core/network/kugou_client.dart';
import '../../song/data/song_mappers.dart';
import '../../song/domain/song.dart';
import '../domain/playlist.dart';

/// 歌单接口：推荐歌单、歌单详情、歌单曲目。
///
/// 关键约束（实测，见 docs/API联调记录.md）：
/// - `/playlist/detail` 与 `/playlist/track/all` 的 ID 必须传
///   `global_collection_id`（形如 `collection_3_949485588_10_0`）；
/// - 传 `specialid` 时详情返回空 `data: {}`，曲目接口直接 HTTP 502；
/// - 因此 [Playlist.fromJson] 优先取 `global_collection_id`，拿不到时
///   详情降级为 null、曲目降级为空列表，而不是把整页打成错误态。
class KugouPlaylistApi {
  KugouPlaylistApi(this._client);

  final KugouClient _client;

  /// 推荐歌单（`/top/playlist`），发现页与"歌单广场"共用。
  Future<List<Playlist>> topPlaylists({
    int page = 1,
    int pageSize = 20,
  }) async {
    final Map<String, dynamic> json = await _client.getJson(
      '/top/playlist',
      query: <String, dynamic>{'page': page, 'pagesize': pageSize},
    );
    final Map<String, dynamic>? data = JsonUtils.asMap(json['data']);
    final Object? raw =
        data?['special_list'] ?? data?['info'] ?? json['special_list'];
    return JsonUtils.asMapList(raw)
        .map(Playlist.fromJson)
        .whereType<Playlist>()
        .toList(growable: false);
  }

  /// 歌单详情（`/playlist/detail?ids=<global_collection_id>`）。
  ///
  /// 接口返回 `data` 为数组；`ids` 不是 `global_collection_id` 时返回
  /// `data: {}`，此时返回 null，页面按"歌单不存在"降级展示。
  Future<Playlist?> detail(String id) async {
    final String collectionId = normalizeCollectionId(id);
    if (collectionId.isEmpty) {
      return null;
    }
    final Map<String, dynamic> json;
    try {
      json = await _client.getJson(
        '/playlist/detail',
        query: <String, dynamic>{'ids': collectionId},
      );
    } on KugouApiException catch (error) {
      // 502 = 当前 ID 不是可用的 global_collection_id（如误传 specialid）。
      if (error.code == 502) {
        return null;
      }
      rethrow;
    }
    final Object? data = json['data'];
    final List<Map<String, dynamic>> list = JsonUtils.asMapList(data);
    if (list.isNotEmpty) {
      return Playlist.fromJson(list.first);
    }
    final Map<String, dynamic>? map = JsonUtils.asMap(data);
    if (map == null || map.isEmpty) {
      return null;
    }
    return Playlist.fromJson(map);
  }

  /// 歌单曲目（`/playlist/track/all?id=<global_collection_id>`）。
  Future<List<Song>> songs(
    String id, {
    int page = 1,
    int pageSize = 100,
  }) async {
    final String collectionId = normalizeCollectionId(id);
    if (collectionId.isEmpty) {
      return const <Song>[];
    }
    final Map<String, dynamic> json;
    try {
      json = await _client.getJson(
        '/playlist/track/all',
        query: <String, dynamic>{
          'id': collectionId,
          'page': page,
          'pagesize': pageSize,
        },
      );
    } on KugouApiException catch (error) {
      // 传错 ID（如 specialid）会 502：降级为空曲目，由页面提示暂无曲目。
      if (error.code == 502) {
        return const <Song>[];
      }
      rethrow;
    }
    final Map<String, dynamic>? data = JsonUtils.asMap(json['data']);
    if (data == null) {
      return const <Song>[];
    }
    return SongMappers.listFrom(data['songs'], dedupe: true);
  }

  /// 统一 ID 形态：只保留 `global_collection_id`。
  ///
  /// 推荐歌单与搜索结果里的 `global_collection_id` 已由 [Playlist.fromJson]
  /// 收敛进 `Playlist.id`；这里再兜一层，避免上层误把 specialid 传进来
  /// 导致接口空数据或 502。
  static String normalizeCollectionId(String id) {
    final String value = id.trim();
    if (value.isEmpty) {
      return '';
    }
    return value.startsWith('collection_') ? value : '';
  }
}
