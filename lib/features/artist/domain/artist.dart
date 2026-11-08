/// 领域实体：歌手。
class Artist {
  const Artist({
    required this.id,
    required this.name,
    this.bio = '',
    this.songIds = const <String>[],
    this.albumIds = const <String>[],
    this.avatarUrl,
    this.fansCount = 0,
  });

  final String id;
  final String name;
  final String bio;
  final List<String> songIds;
  final List<String> albumIds;
  final String? avatarUrl;
  final int fansCount;
}
