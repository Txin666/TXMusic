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
import '../../album/domain/album.dart';
import '../../artist/domain/artist.dart';
import '../../player/application/player_controller.dart';
import '../../playlist/domain/playlist.dart';
import '../../song/domain/song.dart';
import '../application/discover_providers.dart';
import '../domain/discover_banner.dart';
import 'widgets/discover_banner_carousel.dart';

/// 发现 / 推荐首页。
/// 数据全部来自 `discover_providers.dart`（骨架期为假数据），
/// 接入接口时只需把 Provider 换成 FutureProvider 并在此处加 AsyncValue.when。
class DiscoverPage extends ConsumerWidget {
  const DiscoverPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<DiscoverBanner> banners = ref.watch(discoverBannersProvider);
    final List<Playlist> playlists = ref.watch(recommendedPlaylistsProvider);
    final List<Album> albums = ref.watch(recommendedAlbumsProvider);
    final List<Artist> artists = ref.watch(recommendedArtistsProvider);
    final List<Song> newSongs = ref.watch(newSongsProvider);

    return PageContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildGreeting(context, ref, newSongs),
          const SizedBox(height: AppSpacing.lg),
          DiscoverBannerCarousel(
            banners: banners,
            onTapBanner: (DiscoverBanner banner) {
              final String? route = banner.targetRoute;
              if (route != null) {
                context.push(route);
              }
            },
          ),
          const SizedBox(height: AppSpacing.xl),
          SectionHeader(
            title: '推荐歌单',
            subtitle: '根据你的收听偏好生成（骨架期示例数据）',
            actionLabel: '排行榜',
            onActionTap: () => context.go(AppRoutes.rank),
          ),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.lg,
            children: playlists.map((Playlist playlist) {
              return MediaCard(
                title: playlist.title,
                seed: playlist.id,
                subtitle: '${Formatters.playCount(playlist.playCount)}次播放 · ${playlist.creator}',
                badge: playlist.tags.isEmpty ? null : playlist.tags.first,
                onTap: () => context.push(AppRoutes.playlistDetail(playlist.id)),
              );
            }).toList(growable: false),
          ),
          const SizedBox(height: AppSpacing.xl),
          SectionHeader(
            title: '新歌速递',
            subtitle: '每日更新的新发行作品',
            actionLabel: '播放全部',
            onActionTap: () => ref
                .read(playerControllerProvider.notifier)
                .playQueue(newSongs),
          ),
          ...newSongs.asMap().entries.map((MapEntry<int, Song> entry) {
            return SongTile(
              song: entry.value,
              onTap: () => ref
                  .read(playerControllerProvider.notifier)
                  .playSong(entry.value, queue: newSongs),
              onPlayTap: () => ref
                  .read(playerControllerProvider.notifier)
                  .playSong(entry.value, queue: newSongs),
            );
          }),
          const SizedBox(height: AppSpacing.xl),
          SectionHeader(
            title: '热门歌手',
            subtitle: '点击进入歌手详情',
            actionLabel: '更多',
            onActionTap: () => context.go(AppRoutes.rank),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: artists.map((Artist artist) {
                return Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.lg),
                  child: ArtistAvatar(
                    name: artist.name,
                    subtitle: '${Formatters.playCount(artist.fansCount)} 粉丝',
                    onTap: () => context.push(AppRoutes.artistDetail(artist.id)),
                  ),
                );
              }).toList(growable: false),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          SectionHeader(
            title: '推荐专辑',
            subtitle: '完整专辑，按发行时间排序',
            actionLabel: '更多',
            onActionTap: () => context.go(AppRoutes.rank),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: albums.map((Album album) {
                return Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.lg),
                  child: MediaCard(
                    title: album.title,
                    seed: album.id,
                    icon: Icons.album_rounded,
                    subtitle: '${album.artist} · ${album.releaseDate}',
                    onTap: () => context.push(AppRoutes.albumDetail(album.id)),
                  ),
                );
              }).toList(growable: false),
            ),
          ),
          const SizedBox(height: AppSpacing.huge),
        ],
      ),
    );
  }

  Widget _buildGreeting(BuildContext context, WidgetRef ref, List<Song> newSongs) {
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
                '${Formatters.date(now)} · 今日推荐已更新，随便听点什么吧',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        FilledButton.icon(
          onPressed: () => ref
              .read(playerControllerProvider.notifier)
              .playQueue(newSongs),
          icon: const Icon(Icons.play_arrow_rounded, size: 18),
          label: const Text('播放每日推荐'),
        ),
      ],
    );
  }
}
