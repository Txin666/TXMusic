import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/formatters.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/widgets/artist_avatar.dart';
import '../../../shared/widgets/media_card.dart';
import '../../../shared/widgets/page_container.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../shared/widgets/song_tile.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../album/application/album_providers.dart';
import '../../album/domain/album.dart';
import '../../player/application/player_controller.dart';
import '../../song/data/fake_song_data.dart';
import '../../song/domain/song.dart';
import '../application/artist_providers.dart';
import '../domain/artist.dart';

/// 歌手详情页（路由 `/artist/:id`）：简介 + 热门歌曲 + 专辑。
class ArtistDetailPage extends ConsumerWidget {
  const ArtistDetailPage({super.key, required this.artistId});

  final String artistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Artist artist = ref.watch(artistDetailProvider(artistId));
    final List<Song> songs = FakeSongs.byIds(artist.songIds);
    final List<Album> albums = ref.watch(albumListProvider).where(
          (Album album) => artist.albumIds.contains(album.id),
        ).toList(growable: false);
    final ThemeData theme = Theme.of(context);

    return PageContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              ArtistAvatar(name: artist.name, size: 128),
              const SizedBox(width: AppSpacing.xl),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '歌手',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(artist.name, style: theme.textTheme.displaySmall),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '粉丝 ${Formatters.playCount(artist.fansCount)} · '
                      '${songs.length} 首单曲 · ${albums.length} 张专辑',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      artist.bio,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton.icon(
                      onPressed: songs.isEmpty
                          ? null
                          : () => ref
                              .read(playerControllerProvider.notifier)
                              .playQueue(songs),
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('播放热门歌曲'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxl),
          SectionHeader(title: '热门歌曲', subtitle: '骨架期示例曲目'),
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
          const SizedBox(height: AppSpacing.xl),
          SectionHeader(title: '专辑', subtitle: '共 ${albums.length} 张'),
          if (albums.isEmpty)
            Text(
              '暂无专辑数据',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: AppColors.textSecondary),
            )
          else
            Wrap(
              spacing: AppSpacing.lg,
              runSpacing: AppSpacing.lg,
              children: albums
                  .map(
                    (Album album) => MediaCard(
                      title: album.title,
                      seed: album.title,
                      subtitle: album.releaseDate,
                      icon: Icons.album_rounded,
                      onTap: () =>
                          context.go(AppRoutes.albumDetail(album.id)),
                    ),
                  )
                  .toList(growable: false),
            ),
        ],
      ),
    );
  }
}
