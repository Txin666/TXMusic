import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/kugou_providers.dart';
import '../../playlist/domain/playlist.dart';
import '../../rank/domain/rank_item.dart';
import '../../song/domain/song.dart';

/// 发现页聚合数据：全部来自真实接口，无假数据兜底。
@immutable
class DiscoverFeed {
  const DiscoverFeed({
    this.dailySongs = const <Song>[],
    this.playlists = const <Playlist>[],
    this.ranks = const <RankItem>[],
  });

  /// 每日推荐（`/everyday/recommend`）。
  final List<Song> dailySongs;

  /// 推荐歌单（`/top/playlist`）。
  final List<Playlist> playlists;

  /// 热门榜单（`/rank/list` 前几个）。
  final List<RankItem> ranks;

  bool get isEmpty => dailySongs.isEmpty && playlists.isEmpty && ranks.isEmpty;
}

/// 发现页一次性并发拉取三个区块，任一区块失败不影响其它区块渲染。
final discoverFeedProvider = FutureProvider<DiscoverFeed>((Ref ref) async {
  Future<List<T>> safe<T>(Future<List<T>> Function() task, String label) async {
    try {
      return await task();
    } on Object catch (error) {
      debugPrint('$label拉取失败: $error');
      return <T>[];
    }
  }

  final List<Song> daily = await safe<Song>(
    () => ref.read(kugouDiscoverApiProvider).dailyRecommend(),
    '每日推荐',
  );
  final List<Playlist> playlists = await safe<Playlist>(
    () => ref.read(kugouPlaylistApiProvider).topPlaylists(pageSize: 12),
    '推荐歌单',
  );
  final List<RankItem> ranks = await safe<RankItem>(
    () => ref.read(kugouRankApiProvider).list(),
    '榜单列表',
  );

  return DiscoverFeed(
    dailySongs: daily,
    playlists: playlists,
    ranks: ranks.take(6).toList(growable: false),
  );
});
