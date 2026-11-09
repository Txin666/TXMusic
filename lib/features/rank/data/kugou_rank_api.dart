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
  Future<List<Song>> songs(
    String rankId, {
    int page = 1,
    int pageSize = 100,
  }) async {
    if (rankId.isEmpty) {
      return const <Song>[];
    }
    final Map<String, dynamic> json = await _client.getJson(
      '/rank/audio',
      query: <String, dynamic>{
        'rankid': rankId,
        'page': page,
        'pagesize': pageSize,
      },
    );
    final Map<String, dynamic>? data = JsonUtils.asMap(json['data']);
    final Object? raw = data?['songlist'] ?? data?['songs'] ?? data?['info'];
    return SongMappers.listFrom(raw, dedupe: true);
  }
}
