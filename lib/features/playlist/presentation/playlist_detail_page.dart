import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/detail_hero.dart';
import '../../../shared/widgets/page_container.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../shared/widgets/song_tile.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../player/application/player_controller.dart';
import '../../song/data/fake_song_data.dart';
import '../../song/domain/song.dart';
import '../application/playlist_providers.dart';
import '../domain/playlist.dart';

/// 歌单详情页（路由 `/playlist/:id`，位于主框架 Shell 内）。
///
/// TODO(api): 目前从 `playlistDetailProvider` 取假数据，接入 `/plist/detail` 后
/// 改为 `AsyncValue` 三态渲染（loading / error / data）。
class PlaylistDetailPage extends ConsumerWidget {
  const PlaylistDetailPage({super.key, required this.playlistId});

  final String playlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Playlist playlist = ref.watch(playlistDetailProvider(playlistId));
    final List<Song> songs = FakeSongs.byIds(playlist.songIds);
    final ThemeData theme = Theme.of(context);

    return PageContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          DetailHero(
            seed: playlist.title,
            title: playlist.title,
            typeLabel: '歌单',
            icon: Icons.queue_music_rounded,
            meta: '创建者 ${playlist.creator} · '
                '${playlist.songCount} 首 · 播放 ${Formatters.playCount(playlist.playCount)}',
            description: playlist.description,
            onPrimaryTap: songs.isEmpty
                ? null
                : () => ref
                    .read(playerControllerProvider.notifier)
                    .playQueue(songs),
            secondaryLabel: '收藏歌单',
            onSecondaryTap: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('收藏能力待接入本地持久化（见文档 §8）')),
            ),
          ),
          if (playlist.tags.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: playlist.tags
                  .map((String tag) => Chip(label: Text('# $tag')))
                  .toList(growable: false),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          SectionHeader(
            title: '歌曲列表',
            subtitle: '共 ${songs.length} 首',
          ),
          ...songs.asMap().entries.map(
                (MapEntry<int, Song> entry) => SongTile(
                  song: entry.value,
                  index: entry.key,
                  onTap: () => ref
                      .read(playerControllerProvider.notifier)
                      .playQueue(songs, startIndex: entry.key),
                  onPlayTap: () => ref
                      .read(playerControllerProvider.notifier)
                      .playQueue(songs, startIndex: entry.key),
                ),
              ),
          if (songs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Text(
                '该歌单暂无歌曲（骨架期假数据为空）',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}
