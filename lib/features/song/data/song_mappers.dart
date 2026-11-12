import '../../../core/network/json_utils.dart';
import '../domain/song.dart';

/// 酷狗各接口的歌曲 JSON → [Song] 统一映射。
///
/// 一份代码要对齐六种来源（搜索 / 歌单 / 专辑 / 歌手 / 榜单 / 每日推荐），
/// 字段命名完全不同，踩坑要点：
/// - hash：`hash` / `FileHash`，都缺时可退 `hash_128`；
/// - 歌名：`songname` / `SongName` / `audio_name` / `filename`（格式"歌手 - 歌名"）；
/// - 歌手：`author_name` / `SingerName`，或数组 `authors` / `singerinfo`；
/// - 时长：`timelen`（毫秒）与 `Duration`（秒）混用，交给 [JsonUtils.duration]；
/// - 封面：`cover` 常只有文件名，真正可用的是 `sizable_cover` / `Image` 模板串。
class SongMappers {
  const SongMappers._();

  static const List<String> _hashKeys = <String>[
    'hash',
    'FileHash',
    'hash_128',
    'HQFileHash',
    'Hash',
  ];

  static const List<String> _titleKeys = <String>[
    'songname',
    'SongName',
    'audio_name',
    'ori_audio_name',
    'song_name',
    'name',
    'filename',
  ];

  static const List<String> _artistKeys = <String>[
    'author_name',
    'SingerName',
    'singername',
    'singer_name',
    'singername_full',
  ];

  static const List<String> _albumKeys = <String>[
    'album_name',
    'AlbumName',
    'albumname',
  ];

  static const List<String> _albumIdKeys = <String>[
    'album_id',
    'AlbumID',
    'albumid',
  ];

  static const List<String> _durationKeys = <String>[
    'timelen',
    'timelength',
    'time_length',
    'timelength_320',
    'Duration',
    'duration',
    'interval',
  ];

  static const List<String> _coverKeys = <String>[
    // 真实位置勘误：歌手/专辑/歌单里的歌，封面多数只出现在
    // `trans_param.union_cover` 或 `album_info.sizable_cover`，
    // 顶层没有 `cover`，漏了这两个键会导致整片列表无封面。
    'union_cover',
    'sizable_cover',
    'Image',
    'img',
    'imgurl',
    'cover_url',
    'sizable_avatar',
    'album_img',
    'cover',
    'album_cover',
  ];

  /// 单条 JSON → [Song]；缺 hash 的条目（无音源）返回 null。
  static Song? fromJson(Map<String, dynamic> json) {
    final String hash = JsonUtils.str(
      JsonUtils.pick(json, _hashKeys),
    );
    if (hash.isEmpty) {
      return null;
    }

    String title = JsonUtils.str(JsonUtils.pick(json, _titleKeys));
    String artist = _artistText(json);
    final String filename = JsonUtils.str(JsonUtils.pick(json, const <String>['filename']));
    if (title.contains(' - ') && filename.isNotEmpty) {
      title = title.split(' - ').last.trim();
    }
    if (artist.isEmpty && filename.contains(' - ')) {
      artist = filename.split(' - ').first.trim();
    }

    final int privilege = JsonUtils.integer(
      JsonUtils.pick(json, const <String>['privilege', 'Privilege', 'pay_type']),
    );

    return Song(
      id: JsonUtils.str(
        JsonUtils.pick(json, const <String>[
          'mixsongid',
          'MixSongID',
          'album_audio_id',
          'audio_id',
          'Audioid',
          'songid',
        ]),
        fallback: hash,
      ),
      title: title.isEmpty ? '未知歌曲' : title,
      artist: artist.isEmpty ? '未知歌手' : artist,
      artistId: _artistId(json),
      album: JsonUtils.str(JsonUtils.pick(json, _albumKeys)),
      albumId: JsonUtils.str(JsonUtils.pick(json, _albumIdKeys)),
      duration: JsonUtils.duration(JsonUtils.pick(json, _durationKeys)),
      coverUrl: JsonUtils.cover(JsonUtils.pick(json, _coverKeys)),
      hash: hash,
      isVip: privilege == 0 || privilege == 8,
    );
  }

  /// 列表 JSON → `List<Song>`，自动剔除无 hash 的脏数据。
  static List<Song> listFrom(
    Object? raw, {
    bool dedupe = false,
  }) {
    final List<Song> songs = <Song>[];
    final Set<String> seen = <String>{};
    for (final Map<String, dynamic> item in JsonUtils.asMapList(raw)) {
      final Song? song = fromJson(item);
      if (song == null) {
        continue;
      }
      if (dedupe && !seen.add(song.hash)) {
        continue;
      }
      songs.add(song);
    }
    return songs;
  }

  /// 歌手名：优先扁平字段，其次 `authors` / `singerinfo` 数组。
  static String _artistText(Map<String, dynamic> json) {
    final String flat = JsonUtils.str(JsonUtils.pick(json, _artistKeys));
    if (flat.isNotEmpty) {
      return flat;
    }
    for (final String key in const <String>['authors', 'singerinfo', 'singers']) {
      final Object? raw = json[key];
      if (raw is! List) {
        continue;
      }
      final List<String> names = <String>[];
      for (final Map<String, dynamic> singer in JsonUtils.asMapList(raw)) {
        final String name = JsonUtils.str(
          JsonUtils.pick(singer, const <String>['name', 'author_name', 'singer_name']),
        );
        if (name.isNotEmpty) {
          names.add(name);
        }
      }
      if (names.isNotEmpty) {
        return names.join('、');
      }
    }
    return '';
  }

  /// 歌手 ID：用于跳转歌手详情。
  static String _artistId(Map<String, dynamic> json) {
    final String flat = JsonUtils.str(
      JsonUtils.pick(json, const <String>['author_id', 'SingerId', 'singerid']),
    );
    if (flat.isNotEmpty) {
      return flat;
    }
    for (final String key in const <String>['authors', 'singerinfo', 'singers']) {
      final Object? raw = json[key];
      if (raw is! List) {
        continue;
      }
      for (final Map<String, dynamic> singer in JsonUtils.asMapList(raw)) {
        final String id = JsonUtils.str(
          JsonUtils.pick(singer, const <String>['id', 'author_id', 'singer_id']),
        );
        if (id.isNotEmpty) {
          return id;
        }
      }
    }
    return '';
  }
}
