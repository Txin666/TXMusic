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
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../player/application/player_controller.dart';
import '../../song/domain/song.dart';
import '../application/rank_providers.dart';
import '../domain/rank_item.dart';

/// 排行榜列表页：数据来自 `/rank/list`，三态渲染。
class RankPage extends ConsumerWidget {
  const RankPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<List<RankItem>> ranksAsync = ref.watch(rankListProvider);

    return PageContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('排行榜', style: theme.textTheme.headlineMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '官方榜单定时更新，曲目与播放量均来自酷狗榜单接口',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xl),
          ranksAsync.when(
            loading: () => const _RankLoading(),
            error: (Object error, StackTrace stack) => EmptyState(
              title: '榜单加载失败',
              description: _describeError(error),
              icon: Icons.cloud_off_rounded,
              actionLabel: '重新加载',
              onActionTap: () => ref.invalidate(rankListProvider),
            ),
            data: (List<RankItem> ranks) {
              if (ranks.isEmpty) {
                return EmptyState(
                  title: '暂无榜单数据',
                  description: '接口未返回榜单列表，请稍后重试。',
                  icon: Icons.leaderboard_outlined,
                  actionLabel: '重新加载',
                  onActionTap: () => ref.invalidate(rankListProvider),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SectionHeader(
                    title: '全部榜单',
                    subtitle: '共 ${ranks.length} 个榜单',
                  ),
                  ...ranks.map((RankItem rank) => _RankCard(rank: rank)),
                  const SizedBox(height: AppSpacing.huge),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RankCard extends ConsumerWidget {
  const _RankCard({required this.rank});

  final RankItem rank;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<List<Song>> songsAsync = ref.watch(rankSongsProvider(rank.id));
    final List<Song> songs = songsAsync.value ?? const <Song>[];
    final String meta = <String>[
      if (rank.playCount > 0) '${Formatters.playCount(rank.playCount)}次播放',
      if (rank.updateNote.isNotEmpty) rank.updateNote,
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InkWell(
            onTap: () => context.push(AppRoutes.rankDetail(rank.id)),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: CoverImage(
              seed: rank.title,
              url: rank.coverUrl,
              size: 108,
              radius: AppRadius.sm,
              icon: Icons.leaderboard_rounded,
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: InkWell(
                        onTap: () => context.push(AppRoutes.rankDetail(rank.id)),
                        child: Text(
                          rank.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                    ),
                    if (rank.updateNote.isNotEmpty) ...<Widget>[
                      const SizedBox(width: AppSpacing.sm),
                      _Chip(text: rank.updateNote),
                    ],
                  ],
                ),
                if (meta.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                songsAsync.when(
                  loading: () => Text(
                    '曲目加载中…',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.textTertiary),
                  ),
                  error: (Object error, StackTrace stack) => Text(
                    '曲目加载失败：${_describeError(error)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.danger),
                  ),
                  data: (List<Song> list) {
                    if (list.isEmpty) {
                      return Text(
                        '该榜单暂无曲目',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppColors.textTertiary),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: list
                          .take(3)
                          .toList(growable: false)
                          .asMap()
                          .entries
                          .map(
                            (MapEntry<int, Song> entry) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: InkWell(
                                onTap: () => ref
                                    .read(playerControllerProvider.notifier)
                                    .playQueue(list, startIndex: entry.key),
                                child: Row(
                                  children: <Widget>[
                                    SizedBox(
                                      width: 22,
                                      child: Text(
                                        '${entry.key + 1}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: entry.key == 0
                                              ? AppColors.primary
                                              : AppColors.textTertiary,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        entry.value.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodyMedium,
                                      ),
                                    ),
                                    const SizedBox(width: AppSpacing.sm),
                                    Text(
                                      entry.value.artist,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                          .toList(growable: false),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Column(
            children: <Widget>[
              FilledButton.tonalIcon(
                onPressed: songs.isEmpty
                    ? null
                    : () => ref
                        .read(playerControllerProvider.notifier)
                        .playQueue(songs),
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('播放'),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton(
                onPressed: () => context.push(AppRoutes.rankDetail(rank.id)),
                child: const Text('查看全部'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
      ),
    );
  }
}

class _RankLoading extends StatelessWidget {
  const _RankLoading();

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
              '正在加载榜单…',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

String _describeError(Object error) =>
    error is KugouApiException ? error.message : '网络请求失败：$error';
