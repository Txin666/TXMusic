import '../../../core/network/kugou_client.dart';
import '../domain/song.dart';

/// 歌曲接口 DTO → Entity 映射（`/search/song`、后续榜单/歌单复用）。
///
/// 真实字段踩坑记录：
/// - 时长字段是 `Duration`（秒），不是毫秒；
/// - 封面 `Image` 是模板串 `http://imge.kugou.com/stdmusic/{size}/xx.jpg`，
///   必须把 `{size}` 换成具体尺寸（这里用 480）；
/// - `FileHash` 用于音源解析，`AlbumID` 用于 `/song/url` 的 album_id 参数。
class KugouSongApi {
  KugouSongApi(this._client);

  final KugouClient _client;

  static const String _coverSize = '480';

  /// 关键字搜索歌曲。
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
    final Object? data = json['data'];
    if (data is! Map<String, dynamic>) {
      return const <Song>[];
    }
    final Object? lists = data['lists'];
    if (lists is! List) {
      return const <Song>[];
    }
    return lists
        .whereType<Map<String, dynamic>>()
        .map(mapSong)
        .where((Song song) => song.canResolve)
        .toList(growable: false);
  }

  /// 单条歌曲 JSON → [Song]。
  static Song mapSong(Map<String, dynamic> json) {
    final String hash = _str(json['FileHash']);
    final String id = _str(json['MixSongID']).isNotEmpty
        ? _str(json['MixSongID'])
        : (_str(json['Audioid']).isNotEmpty ? _str(json['Audioid']) : hash);
    final int seconds = _int(json['Duration'], fallback: 0);
    final int privilege = _int(json['Privilege'], fallback: 0);

    return Song(
      id: id,
      title: _str(json['SongName'], fallback: '未知歌曲'),
      artist: _str(json['SingerName'], fallback: '未知歌手'),
      album: _str(json['AlbumName']),
      albumId: _str(json['AlbumID']),
      duration: Duration(seconds: seconds),
      coverUrl: normalizeCover(_str(json['Image'])),
      hash: hash,
      // Privilege 为 0/8 通常表示无版权或需付费；登录后仍可能受限。
      isVip: privilege == 0 || privilege == 8,
    );
  }

  /// 补全封面模板串中的 `{size}`。
  static String? normalizeCover(String raw) {
    if (raw.isEmpty) {
      return null;
    }
    return raw
        .replaceAll('{size}', _coverSize)
        .replaceFirst('http://', 'https://');
  }

  static String _str(Object? value, {String fallback = ''}) {
    if (value == null) {
      return fallback;
    }
    final String text = value.toString();
    return text.isEmpty ? fallback : text;
  }

  static int _int(Object? value, {int fallback = 0}) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse('${value ?? ''}') ?? fallback;
  }
}
