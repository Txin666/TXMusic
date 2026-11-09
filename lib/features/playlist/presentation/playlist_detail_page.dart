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
import '../application/playlist_providers.dart';
import '../domain/playlist.dart';

/// 歌单详情页（路由 `/playlist/:id`）。
///
/// 元信息走 `/playlist/detail`（[playlistDetailProvider]），曲目走
/// `/playlist/track/all`（[playlistSongsProvider]），两块独立三态渲染。
class PlaylistDetailPage extends ConsumerWidget {
  const PlaylistDetailPage({super.key, required this.playlistId});

  final String playlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 实测详情与曲目接口只认 global_collection_id，其它形态 ID 会空数据或 502，
    // 这里提前降级为提示，避免整页报错。
    if (!playlistId.startsWith('collection_')) {
      return PageContainer(
        child: EmptyState(
          title: '该歌单暂不支持查看',
          description: '此歌单没有返回 global_collection_id（当前 ID：$playlistId），'
              '酷狗详情接口不支持用 specialid 查询。可换一个推荐歌单再试。',
          icon: Icons.queue_music_rounded,
          actionLabel: '返回发现页',
          onActionTap: () => context.go(AppRoutes.discover),
        ),
      );
    }

    final AsyncValue<Playlist?> playlistAsync =
        ref.watch(playlistDetailProvider(playlistId));
    final AsyncValue<List<Song>> songsAsync =
        ref.watch(playlistSongsProvider(playlistId));

    return PageContainer(
      child: playlistAsync.when(
        loading: () => const _DetailLoading(label: '正在加载歌单信息…'),
        error: (Object error, StackTrace stack) => EmptyState(
          title: '歌单加载失败',
          description: _describeError(error),
          icon: Icons.cloud_off_rounded,
          actionLabel: '重新加载',
          onActionTap: () {
            ref.invalidate(playlistDetailProvider(playlistId));
            ref.invalidate(playlistSongsProvider(playlistId));
          },
        ),
        data: (Playlist? playlist) {
          if (playlist == null) {
            return EmptyState(
              title: '歌单不存在或已被删除',
              description: '没有找到 ID 为 $playlistId 的歌单。',
              icon: Icons.queue_music_rounded,
              actionLabel: '返回发现页',
              onActionTap: () => context.go(AppRoutes.discover),
            );
          }

          final List<Song> songs = songsAsync.value ?? const <Song>[];
          final List<String> metaParts = <String>[
            if (playlist.creator.isNotEmpty) playlist.creator,
            if (playlist.playCount > 0)
              '${Formatters.playCount(playlist.playCount)}次播放',
            if (songs.isNotEmpty) '${songs.length} 首' else if (playlist.songCount > 0) '${playlist.songCount} 首',
            if (playlist.updateTime.isNotEmpty) '更新于 ${playlist.updateTime}',
          ];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              DetailHero(
                seed: playlist.title,
                title: playlist.title,
                typeLabel: '歌单',
                icon: Icons.queue_music_rounded,
                meta: metaParts.isEmpty ? null : metaParts.join(' · '),
                description: playlist.description,
                onPrimaryTap: songs.isEmpty
                    ? null
                    : () => ref
                        .read(playerControllerProvider.notifier)
                        .playQueue(songs),
                secondaryLabel: '电台/收藏',
                onSecondaryTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('收藏功能待接入本地库（后续任务）')),
                  );
                },
              ),
              if (playlist.tags.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: playlist.tags
                      .map((String tag) => _TagChip(text: tag))
                      .toList(growable: false),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              SectionHeader(
                title: '歌单曲目',
                subtitle: songsAsync.when(
                  loading: () => '曲目加载中…',
                  error: (Object error, StackTrace stack) => '曲目加载失败',
                  data: (List<Song> list) => '共 ${list.length} 首',
                ),
              ),
              songsAsync.when(
                loading: () => const _DetailLoading(label: '正在加载歌单曲目…'),
                error: (Object error, StackTrace stack) => EmptyState(
                  title: '曲目加载失败',
                  description: _describeError(error),
                  icon: Icons.music_off_rounded,
                  actionLabel: '重试',
                  onActionTap: () =>
                      ref.invalidate(playlistSongsProvider(playlistId)),
                  compact: true,
                ),
                data: (List<Song> list) {
                  if (list.isEmpty) {
                    return EmptyState(
                      title: '该歌单暂无曲目',
                      description: '接口返回的曲目列表为空，可能需要登录或歌单已下架。',
                      icon: Icons.music_off_rounded,
                      actionLabel: '重新加载',
                      onActionTap: () =>
                          ref.invalidate(playlistSongsProvider(playlistId)),
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

class _TagChip extends StatelessWidget {
  const _TagChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.divider),
      ),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: AppColors.textSecondary),
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
