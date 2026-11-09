import '../../../core/network/json_utils.dart';

/// 领域实体：专辑。
class Album {
  const Album({
    required this.id,
    required this.title,
    required this.artist,
    this.artistId = '',
    this.releaseDate = '',
    this.intro = '',
    this.coverUrl,
    this.playCount = 0,
    this.trackCount = 0,
    this.songIds = const <String>[],
  });

  final String id;
  final String title;
  final String artist;
  final String artistId;
  final String releaseDate;
  final String intro;
  final String? coverUrl;
  final int playCount;
  final int trackCount;
  final List<String> songIds;

  int get songCount => trackCount > 0 ? trackCount : songIds.length;

  static Album? fromJson(Map<String, dynamic> json) {
    final String id = JsonUtils.str(
      JsonUtils.pick(json, const <String>['album_id', 'albumid', 'AlbumID', 'id']),
    );
    if (id.isEmpty) {
      return null;
    }
    return Album(
      id: id,
      title: JsonUtils.str(
        JsonUtils.pick(json, const <String>['album_name', 'albumname', 'AlbumName', 'name']),
        fallback: '未知专辑',
      ),
      artist: JsonUtils.str(
        JsonUtils.pick(json, const <String>[
          'author_name',
          'singername',
          'singer_name',
          'SingerName',
        ]),
      ),
      artistId: JsonUtils.str(
        JsonUtils.pick(json, const <String>['author_id', 'singer_id']),
      ),
      releaseDate: JsonUtils.str(
        JsonUtils.pick(json, const <String>['publish_date', 'publish_time', 'publishtime']),
      ),
      intro: JsonUtils.str(
        JsonUtils.pick(json, const <String>['intro', 'description']),
      ),
      coverUrl: JsonUtils.cover(
        JsonUtils.pick(json, const <String>['sizable_cover', 'imgurl', 'cover', 'img']),
        size: 480,
      ),
      playCount: JsonUtils.integer(
        JsonUtils.pick(json, const <String>['heat', 'play_count', 'playcount']),
      ),
      trackCount: JsonUtils.integer(
        JsonUtils.pick(json, const <String>['song_count', 'songcount', 'count']),
      ),
    );
  }
}
