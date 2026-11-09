import '../../../core/network/json_utils.dart';
import '../../../core/network/kugou_client.dart';
import '../../song/data/song_mappers.dart';
import '../../song/domain/song.dart';

/// 发现页接口：每日推荐等。
class KugouDiscoverApi {
  KugouDiscoverApi(this._client);

  final KugouClient _client;

  /// 每日推荐（`/everyday/recommend`，按用户口味下发，未登录为热播推荐）。
  Future<List<Song>> dailyRecommend() async {
    final Map<String, dynamic> json = await _client.getJson('/everyday/recommend');
    final Map<String, dynamic>? data = JsonUtils.asMap(json['data']);
    final Object? raw = data?['song_list'] ?? data?['songs'] ?? data?['info'];
    return SongMappers.listFrom(raw, dedupe: true);
  }
}
