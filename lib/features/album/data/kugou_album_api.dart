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
  Future<List<Song>> songs(String id) async {
    if (id.isEmpty) {
      return const <Song>[];
    }
    final Map<String, dynamic> json = await _client.getJson(
      '/album/songs',
      query: <String, dynamic>{'id': id, 'page': 1, 'pagesize': 100},
    );
    final Map<String, dynamic>? data = JsonUtils.asMap(json['data']);
    if (data == null) {
      return const <Song>[];
    }
    return SongMappers.listFrom(data['songs'], dedupe: true);
  }
}
