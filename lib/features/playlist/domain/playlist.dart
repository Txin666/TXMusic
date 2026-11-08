/// 领域实体：歌单。
class Playlist {
  const Playlist({
    required this.id,
    required this.title,
    this.creator = '',
    this.description = '',
    this.songIds = const <String>[],
    this.playCount = 0,
    this.coverUrl,
    this.tags = const <String>[],
  });

  final String id;
  final String title;
  final String creator;
  final String description;
  final List<String> songIds;
  final int playCount;
  final String? coverUrl;
  final List<String> tags;

  int get songCount => songIds.length;
}
