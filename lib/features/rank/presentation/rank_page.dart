import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../routing/app_routes.dart';
import '../../../shared/widgets/cover_placeholder.dart';
import '../../../shared/widgets/page_container.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../player/application/player_controller.dart';
import '../../song/data/fake_song_data.dart';
import '../../song/domain/song.dart';
import '../application/rank_providers.dart';
import '../domain/rank_item.dart';

/// 排行榜列表页。
class RankPage extends ConsumerWidget {
  const RankPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<RankItem> ranks = ref.watch(rankListProvider);

    return PageContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('排行榜', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '官方榜单定时更新（骨架期展示示例榜单与示例曲目）',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xl),
          SectionHeader(title: '全部榜单', subtitle: '共 ${ranks.length} 个榜单'),
          ...ranks.map((RankItem rank) => _RankCard(rank: rank)),
          const SizedBox(height: AppSpacing.huge),
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
    final List<Song> songs = FakeSongs.byIds(rank.songIds);

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
            child: CoverPlaceholder(
              seed: rank.id,
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
                    InkWell(
                      onTap: () => context.push(AppRoutes.rankDetail(rank.id)),
                      child: Text(
                        rank.title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _Chip(text: rank.updateNote),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  rank.subtitle,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.sm),
                ...songs.take(3).toList(growable: false).asMap().entries.map(
                      (MapEntry<int, Song> entry) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: InkWell(
                          onTap: () => ref
                              .read(playerControllerProvider.notifier)
                              .playSong(entry.value, queue: songs),
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
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                              Text(
                                entry.value.artist,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Column(
            children: <Widget>[
              FilledButton.tonalIcon(
                onPressed: () => ref
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
