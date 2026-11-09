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
  Future<List<Song>> songs(
    String id, {
    int page = 1,
    int pageSize = 100,
  }) async {
    if (id.isEmpty) {
      return const <Song>[];
    }
    final Map<String, dynamic> json = await _client.getJson(
      '/artist/audios',
      query: <String, dynamic>{'id': id, 'page': page, 'pagesize': pageSize},
    );
    return SongMappers.listFrom(json['data'], dedupe: true);
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
