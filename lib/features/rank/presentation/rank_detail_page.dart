import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/kugou_client.dart';
import '../../../core/utils/formatters.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/widgets/detail_hero.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/page_container.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../shared/widgets/song_tile.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../player/application/player_controller.dart';
import '../../song/domain/song.dart';
import '../application/rank_providers.dart';
import '../domain/rank_item.dart';

/// 榜单详情页（路由 `/rank/:id`）。
///
/// 榜单元信息复用列表接口（[rankItemProvider]），曲目单独请求
/// `/rank/audio`（[rankSongsProvider]），两块各自三态渲染。
class RankDetailPage extends ConsumerWidget {
  const RankDetailPage({super.key, required this.rankId});

  final String rankId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<RankItem?> rankAsync = ref.watch(rankItemProvider(rankId));
    final AsyncValue<List<Song>> songsAsync = ref.watch(rankSongsProvider(rankId));

    return PageContainer(
      child: rankAsync.when(
        loading: () => const _DetailLoading(label: '正在加载榜单信息…'),
        error: (Object error, StackTrace stack) => EmptyState(
          title: '榜单加载失败',
          description: _describeError(error),
          icon: Icons.cloud_off_rounded,
          actionLabel: '重新加载',
          onActionTap: () {
            ref.invalidate(rankListProvider);
            ref.invalidate(rankSongsProvider(rankId));
          },
        ),
        data: (RankItem? rank) {
          if (rank == null) {
            return EmptyState(
              title: '榜单不存在或已下线',
              description: '没有找到 ID 为 $rankId 的榜单。',
              icon: Icons.leaderboard_outlined,
              actionLabel: '返回排行榜',
              onActionTap: () => context.go(AppRoutes.rank),
            );
          }

          final List<Song> songs = songsAsync.value ?? const <Song>[];
          final List<String> metaParts = <String>[
            if (rank.updateNote.isNotEmpty) rank.updateNote,
            if (rank.playCount > 0) '${Formatters.playCount(rank.playCount)}次播放',
            if (songs.isNotEmpty) '${songs.length} 首',
          ];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              DetailHero(
                seed: rank.title,
                title: rank.title,
                typeLabel: '排行榜',
                icon: Icons.leaderboard_rounded,
                meta: metaParts.isEmpty ? null : metaParts.join(' · '),
                description: rank.intro.isNotEmpty ? rank.intro : rank.subtitle,
                onPrimaryTap: songs.isEmpty
                    ? null
                    : () => ref
                        .read(playerControllerProvider.notifier)
                        .playQueue(songs),
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionHeader(
                title: '榜单曲目',
                subtitle: songsAsync.when(
                  loading: () => '曲目加载中…',
                  error: (Object error, StackTrace stack) => '曲目加载失败',
                  data: (List<Song> list) => '共 ${list.length} 首',
                ),
              ),
              songsAsync.when(
                loading: () => const _DetailLoading(label: '正在加载榜单曲目…'),
                error: (Object error, StackTrace stack) => EmptyState(
                  title: '曲目加载失败',
                  description: _describeError(error),
                  icon: Icons.music_off_rounded,
                  actionLabel: '重试',
                  onActionTap: () => ref.invalidate(rankSongsProvider(rankId)),
                  compact: true,
                ),
                data: (List<Song> list) {
                  if (list.isEmpty) {
                    return EmptyState(
                      title: '该榜单暂无曲目',
                      description: '接口返回的曲目列表为空，请稍后重试。',
                      icon: Icons.music_off_rounded,
                      actionLabel: '重新加载',
                      onActionTap: () =>
                          ref.invalidate(rankSongsProvider(rankId)),
                      compact: true,
                    );
                  }
                  return Column(
                    children: list
                        .asMap()
                        .entries
                        .map(
                          (MapEntry<int, Song> entry) => SongTile(
                            song: entry.value,
                            index: entry.key,
                            onTap: () => ref
                                .read(playerControllerProvider.notifier)
                                .playQueue(list, startIndex: entry.key),
                            onPlayTap: () => ref
                                .read(playerControllerProvider.notifier)
                                .playQueue(list, startIndex: entry.key),
                          ),
                        )
                        .toList(growable: false),
                  );
                },
              ),
              const SizedBox(height: AppSpacing.huge),
            ],
          );
        },
      ),
    );
  }
}

class _DetailLoading extends StatelessWidget {
  const _DetailLoading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              label,
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
