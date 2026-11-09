import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/kugou_providers.dart';
import '../../song/domain/song.dart';
import '../domain/rank_item.dart';

/// 榜单列表（`/rank/list`）。
final rankListProvider = FutureProvider<List<RankItem>>(
  (Ref ref) => ref.watch(kugouRankApiProvider).list(),
);

/// 单个榜单元信息：直接复用列表结果，避免详情页再打一次列表接口。
final rankItemProvider = FutureProvider.family<RankItem?, String>((
  Ref ref,
  String id,
) async {
  final List<RankItem> ranks = await ref.watch(rankListProvider.future);
  for (final RankItem item in ranks) {
    if (item.id == id) {
      return item;
    }
  }
  return null;
});

/// 榜单曲目（`/rank/audio`）。
final rankSongsProvider = FutureProvider.family<List<Song>, String>(
  (Ref ref, String rankId) => ref.watch(kugouRankApiProvider).songs(rankId),
);
