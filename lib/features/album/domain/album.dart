/// 领域实体：专辑。
class Album {
  const Album({
    required this.id,
    required this.title,
    required this.artist,
    this.releaseDate = '',
    this.songIds = const <String>[],
    this.coverUrl,
    this.playCount = 0,
  });

  final String id;
  final String title;
  final String artist;
  final String releaseDate;
  final List<String> songIds;
  final String? coverUrl;
  final int playCount;

  int get songCount => songIds.length;
}
