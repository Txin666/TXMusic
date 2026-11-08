import '../domain/rank_item.dart';

/// 骨架期假数据：排行榜。
///
/// TODO(api): 接入 `/rank/list`、`/rank/audio` 后替换为 RankRepository。
class FakeRanks {
  const FakeRanks._();

  static const List<RankItem> all = <RankItem>[
    RankItem(
      id: 'r001',
      title: 'TX 飙升榜',
      subtitle: '最近 24 小时播放增速最快',
      updateNote: '每天 09:00 更新',
      songIds: <String>['s011', 's001', 's007', 's004', 's009'],
    ),
    RankItem(
      id: 'r002',
      title: 'TX 热歌榜',
      subtitle: '全站播放量综合排行',
      updateNote: '每周一 12:00 更新',
      songIds: <String>['s002', 's006', 's003', 's010', 's012'],
    ),
    RankItem(
      id: 'r003',
      title: '新歌速递榜',
      subtitle: '新发行作品热度排行',
      updateNote: '每天 18:00 更新',
      songIds: <String>['s012', 's008', 's005', 's001'],
    ),
    RankItem(
      id: 'r004',
      title: '独立音乐榜',
      subtitle: '独立音乐人作品每周推荐',
      updateNote: '每周五 10:00 更新',
      songIds: <String>['s004', 's008', 's011', 's006'],
    ),
    RankItem(
      id: 'r005',
      title: '深夜收听榜',
      subtitle: '00:00-05:00 时段收听排行',
      updateNote: '每天 06:00 更新',
      songIds: <String>['s009', 's007', 's003', 's005'],
    ),
  ];

  static RankItem byId(String id) => all.firstWhere(
        (RankItem rank) => rank.id == id,
        orElse: () => all.first,
      );
}
