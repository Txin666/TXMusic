import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/fake_rank_data.dart';
import '../domain/rank_item.dart';

/// 排行榜列表 / 榜单详情（骨架期假数据）。
final rankListProvider = Provider<List<RankItem>>(
  (Ref ref) => FakeRanks.all,
);

final rankDetailProvider = Provider.family<RankItem, String>(
  (Ref ref, String id) => FakeRanks.byId(id),
);
