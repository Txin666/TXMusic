/// 领域实体：排行榜。
class RankItem {
  const RankItem({
    required this.id,
    required this.title,
    this.subtitle = '',
    this.updateNote = '',
    this.songIds = const <String>[],
    this.coverUrl,
  });

  final String id;
  final String title;
  final String subtitle;
  final String updateNote;
  final List<String> songIds;
  final String? coverUrl;
}
