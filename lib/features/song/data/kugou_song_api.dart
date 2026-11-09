import '../../../core/network/json_utils.dart';
import '../../../core/network/kugou_client.dart';
import '../domain/song.dart';
import 'song_mappers.dart';

/// 歌曲接口：关键字搜歌。
///
/// 与 [SongMappers] 分工：这里只负责"调接口 + 取列表"，字段收敛统一由映射层做。
class KugouSongApi {
  KugouSongApi(this._client);

  final KugouClient _client;

  /// 关键字搜索歌曲（`/search/song`，扁平字段，映射层已做兼容）。
  Future<List<Song>> search(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  }) async {
    final String key = keyword.trim();
    if (key.isEmpty) {
      return const <Song>[];
    }
    final Map<String, dynamic> json = await _client.getJson(
      '/search/song',
      query: <String, dynamic>{
        'keywords': key,
        'page': page,
        'pagesize': pageSize,
      },
    );
    final Map<String, dynamic>? data = JsonUtils.asMap(json['data']);
    if (data == null) {
      return const <Song>[];
    }
    return SongMappers.listFrom(data['lists']);
  }
}
