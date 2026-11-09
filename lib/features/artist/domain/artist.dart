import '../../../core/network/json_utils.dart';

/// 领域实体：歌手。
class Artist {
  const Artist({
    required this.id,
    required this.name,
    this.bio = '',
    this.avatarUrl,
    this.fansCount = 0,
    this.songCount = 0,
    this.albumCount = 0,
    this.songIds = const <String>[],
    this.albumIds = const <String>[],
  });

  final String id;
  final String name;
  final String bio;
  final String? avatarUrl;
  final int fansCount;
  final int songCount;
  final int albumCount;
  final List<String> songIds;
  final List<String> albumIds;

  static Artist? fromJson(Map<String, dynamic> json) {
    final String id = JsonUtils.str(
      JsonUtils.pick(json, const <String>[
        'author_id',
        'AuthorId',
        'singerid',
        'id',
        'singermid',
      ]),
    );
    if (id.isEmpty) {
      return null;
    }
    return Artist(
      id: id,
      name: JsonUtils.str(
        JsonUtils.pick(json, const <String>[
          'author_name',
          'AuthorName',
          'singername',
          'singer_name',
          'name',
        ]),
        fallback: '未知歌手',
      ),
      bio: JsonUtils.str(
        JsonUtils.pick(json, const <String>['intro', 'profile', 'bio']),
      ),
      avatarUrl: JsonUtils.cover(
        JsonUtils.pick(json, const <String>[
          'sizable_avatar',
          'Avatar',
          'avatar',
          'imgurl',
          'img',
        ]),
        size: 240,
      ),
      fansCount: JsonUtils.integer(
        JsonUtils.pick(json, const <String>['fansnums', 'fans', 'fanscount']),
      ),
      songCount: JsonUtils.integer(
        JsonUtils.pick(json, const <String>['song_count', 'audio_count', 'AudioCount']),
      ),
      albumCount: JsonUtils.integer(
        JsonUtils.pick(json, const <String>['album_count', 'AlbumCount']),
      ),
    );
  }
}
