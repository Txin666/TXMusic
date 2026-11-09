import '../../../core/network/json_utils.dart';

/// 领域实体：排行榜。
class RankItem {
  const RankItem({
    required this.id,
    required this.title,
    this.subtitle = '',
    this.updateNote = '',
    this.intro = '',
    this.playCount = 0,
    this.coverUrl,
    this.songIds = const <String>[],
  });

  final String id;
  final String title;
  final String subtitle;
  final String updateNote;
  final String intro;
  final int playCount;
  final String? coverUrl;
  final List<String> songIds;

  static RankItem? fromJson(Map<String, dynamic> json) {
    final String id = JsonUtils.str(
      JsonUtils.pick(json, const <String>['rankid', 'rank_id', 'id']),
    );
    if (id.isEmpty) {
      return null;
    }
    return RankItem(
      id: id,
      title: JsonUtils.str(
        JsonUtils.pick(json, const <String>['rankname', 'rank_name', 'name']),
        fallback: '未命名榜单',
      ),
      subtitle: JsonUtils.str(
        JsonUtils.pick(json, const <String>['intro', 'jump_title', 'issue']),
      ),
      updateNote: JsonUtils.str(
        JsonUtils.pick(json, const <String>['update_frequency', 'issue']),
      ),
      intro: JsonUtils.str(JsonUtils.pick(json, const <String>['intro'])),
      playCount: JsonUtils.integer(
        JsonUtils.pick(json, const <String>['play_times', 'play_count']),
      ),
      coverUrl: JsonUtils.cover(
        JsonUtils.pick(json, const <String>[
          'imgurl',
          'album_img_9',
          'bannerurl',
          'img_9',
          'banner_9',
        ]),
        size: 480,
      ),
    );
  }
}
