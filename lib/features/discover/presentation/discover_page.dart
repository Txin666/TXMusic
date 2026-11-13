import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/kugou_client.dart';
import '../../../core/utils/formatters.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/widgets/cover_image.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/page_container.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../shared/widgets/song_tile.dart';
import '../../../theme/app_spacing.dart';
import '../../player/application/player_controller.dart';
import '../../playlist/domain/playlist.dart';
import '../../rank/domain/rank_item.dart';
import '../../song/domain/song.dart';
import '../application/discover_providers.dart';
import '../domain/discover_banner.dart';
import '../../../theme/app_palette.dart';
import 'widgets/discover_banner_carousel.dart';

/// 发现 / 推荐首页。
///
/// 数据全部来自 [discoverFeedProvider]（`/everyday/recommend` + `/top/playlist`
/// + `/rank/list` 并发聚合），页面只做三态渲染：loading / error / data。
class DiscoverPage extends ConsumerWidget {
  const DiscoverPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<DiscoverFeed> feedAsync = ref.watch(discoverFeedProvider);

    return PageContainer(
      child: feedAsync.when(
        loading: () => const _DiscoverLoading(),
        error: (Object error, StackTrace stack) => _DiscoverError(
          message: _describeError(error),
          onRetry: () => ref.invalidate(discoverFeedProvider),
        ),
        data: (DiscoverFeed feed) => _DiscoverContent(feed: feed),
      ),
    );
  }
}

class _DiscoverContent extends ConsumerWidget {
  const _DiscoverContent({required this.feed});

  final DiscoverFeed feed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Song> dailySongs = feed.dailySongs;
    final List<Playlist> playlists = feed.playlists;
    final List<RankItem> ranks = feed.ranks;

    if (feed.isEmpty) {
      return _DiscoverError(
        message: '接口暂未返回任何推荐内容，可能处于未登录状态或服务端限流。',
        title: '暂无推荐内容',
        onRetry: () => ref.invalidate(discoverFeedProvider),
      );
    }

    final List<DiscoverBanner> banners = ranks
        .take(3)
        .map(
          (RankItem rank) => DiscoverBanner(
            id: rank.id,
            title: rank.title,
            subtitle: rank.subtitle.isNotEmpty
                ? rank.subtitle
                : (rank.intro.isNotEmpty ? rank.intro : '点击查看完整榜单'),
            tag: rank.updateNote.isNotEmpty ? rank.updateNote : '榜单',
            targetRoute: AppRoutes.rankDetail(rank.id),
          ),
        )
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildGreeting(context, ref, dailySongs),
        const SizedBox(height: AppSpacing.lg),
        if (banners.isNotEmpty)
          DiscoverBannerCarousel(
            banners: banners,
            onTapBanner: (DiscoverBanner banner) {
              final String? route = banner.targetRoute;
              if (route != null) {
                context.push(route);
              }
            },
          ),
        if (banners.isNotEmpty) const SizedBox(height: AppSpacing.xl),
        if (dailySongs.isNotEmpty) ...<Widget>[
          SectionHeader(
            title: '每日推荐',
            subtitle: '共 ${dailySongs.length} 首 · 每日更新',
            actionLabel: '播放全部',
            onActionTap: () => ref
                .read(playerControllerProvider.notifier)
                .playQueue(dailySongs),
          ),
          ...dailySongs
              .take(10)
              .map(
                (Song song) => SongTile(
                  song: song,
                  onTap: () => ref
                      .read(playerControllerProvider.notifier)
                      .playSong(song, queue: dailySongs),
                  onPlayTap: () => ref
                      .read(playerControllerProvider.notifier)
                      .playSong(song, queue: dailySongs),
                ),
              ),
          if (dailySongs.length > 10)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                '仅展示前 10 首，点击「播放全部」收听 ${dailySongs.length} 首',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: context.palette.textDisabled),
              ),
            ),
          const SizedBox(height: AppSpacing.xl),
        ],
        if (playlists.isNotEmpty) ...<Widget>[
          SectionHeader(
            title: '推荐歌单',
            subtitle: '共 ${playlists.length} 个歌单',
            actionLabel: '排行榜',
            onActionTap: () => context.go(AppRoutes.rank),
          ),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.lg,
            children: playlists
                .map((Playlist playlist) => _PlaylistCard(playlist: playlist))
                .toList(growable: false),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
        if (ranks.isNotEmpty) ...<Widget>[
          SectionHeader(
            title: '热门榜单',
            subtitle: '官方榜单实时更新',
            actionLabel: '全部榜单',
            onActionTap: () => context.go(AppRoutes.rank),
          ),
          ...ranks.map((RankItem rank) => _RankRow(rank: rank)),
        ],
        const SizedBox(height: AppSpacing.huge),
      ],
    );
  }

  Widget _buildGreeting(
    BuildContext context,
    WidgetRef ref,
    List<Song> dailySongs,
  ) {
    final DateTime now = DateTime.now();
    final String greeting = now.hour < 6
        ? '凌晨好'
        : now.hour < 12
        ? '早上好'
        : now.hour < 18
        ? '下午好'
        : '晚上好';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '$greeting，欢迎回到 TX Music',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                dailySongs.isEmpty
                    ? '${Formatters.date(now)} · 今日推荐正在更新'
                    : '${Formatters.date(now)} · 今日为你准备了 ${dailySongs.length} 首推荐',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: context.palette.textSecondary),
              ),
            ],
          ),
        ),
        FilledButton.icon(
          onPressed: dailySongs.isEmpty
              ? null
              : () => ref
                    .read(playerControllerProvider.notifier)
                    .playQueue(dailySongs),
          icon: const Icon(Icons.play_arrow_rounded, size: 18),
          label: const Text('播放每日推荐'),
        ),
      ],
    );
  }
}

/// 单个推荐歌单卡片：封面走真实网络图（[CoverImage] 自带失败兜底）。
class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({required this.playlist});

  final Playlist playlist;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String subtitle = playlist.creator.isEmpty
        ? '${Formatters.playCount(playlist.playCount)}次播放'
        : '${playlist.creator} · ${Formatters.playCount(playlist.playCount)}次播放';

    return InkWell(
      onTap: () => context.push(AppRoutes.playlistDetail(playlist.id)),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: SizedBox(
        width: 168,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            CoverImage(
              seed: playlist.title,
              url: playlist.coverUrl,
              size: 168,
              radius: AppRadius.sm,
              icon: Icons.queue_music_rounded,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              playlist.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: context.palette.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 榜单行：封面 + 名称 + 更新频率 + 跳转。
class _RankRow extends StatelessWidget {
  const _RankRow({required this.rank});

  final RankItem rank;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String meta = <String>[
      if (rank.updateNote.isNotEmpty) rank.updateNote,
      if (rank.playCount > 0) '${Formatters.playCount(rank.playCount)}次播放',
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: context.palette.divider),
      ),
      child: Row(
        children: <Widget>[
          CoverImage(
            seed: rank.title,
            url: rank.coverUrl,
            size: 64,
            radius: AppRadius.sm,
            icon: Icons.leaderboard_rounded,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  rank.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
                if (meta.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: context.palette.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          OutlinedButton(
            onPressed: () => context.push(AppRoutes.rankDetail(rank.id)),
            child: const Text('查看'),
          ),
        ],
      ),
    );
  }
}

class _DiscoverLoading extends StatelessWidget {
  const _DiscoverLoading();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.huge),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              '正在加载推荐内容…',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: context.palette.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiscoverError extends StatelessWidget {
  const _DiscoverError({
    required this.message,
    required this.onRetry,
    this.title = '推荐内容加载失败',
  });

  final String message;
  final VoidCallback onRetry;
  final String title;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      title: title,
      description: message,
      icon: Icons.cloud_off_rounded,
      actionLabel: '重新加载',
      onActionTap: onRetry,
    );
  }
}

String _describeError(Object error) =>
    error is KugouApiException ? error.message : '网络请求失败：$error';
