import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/kugou_client.dart';
import '../../../core/utils/formatters.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/widgets/artist_avatar.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/media_card.dart';
import '../../../shared/widgets/page_container.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../shared/widgets/song_tile.dart';
import '../../../theme/app_spacing.dart';
import '../../album/domain/album.dart';
import '../../player/application/player_controller.dart';
import '../../song/domain/song.dart';
import '../application/artist_providers.dart';
import '../domain/artist.dart';
import '../../../theme/app_palette.dart';

/// 歌手详情页（路由 `/artist/:id`）：简介 + 热门歌曲 + 专辑。
///
/// 三块数据各自独立来源、独立三态：
/// - 元信息走 `/artist/detail`（[artistDetailProvider]）；
/// - 热门歌曲走 `/artist/audios`（[artistSongsProvider]）；
/// - 专辑走 `/artist/albums`（[artistAlbumsProvider]）。
/// 任一区域失败只降级该区域，不牵连其它已加载内容。
class ArtistDetailPage extends ConsumerWidget {
  const ArtistDetailPage({super.key, required this.artistId});

  final String artistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Artist?> artistAsync =
        ref.watch(artistDetailProvider(artistId));
    final AsyncValue<List<Song>> songsAsync =
        ref.watch(artistSongsProvider(artistId));
    final AsyncValue<List<Album>> albumsAsync =
        ref.watch(artistAlbumsProvider(artistId));
    final ThemeData theme = Theme.of(context);

    return PageContainer(
      child: artistAsync.when(
        loading: () => const _ArtistLoading(label: '正在加载歌手信息…'),
        error: (Object error, StackTrace stack) => EmptyState(
          title: '歌手信息加载失败',
          description: _describeError(error),
          icon: Icons.cloud_off_rounded,
          actionLabel: '重新加载',
          onActionTap: () => _refreshAll(ref),
        ),
        data: (Artist? artist) {
          if (artist == null) {
            return EmptyState(
              title: '歌手不存在或已下架',
              description: '没有找到 ID 为 $artistId 的歌手。',
              icon: Icons.person_off_outlined,
              actionLabel: '返回发现页',
              onActionTap: () => context.go(AppRoutes.discover),
            );
          }

          final List<Song> songs = songsAsync.value ?? const <Song>[];
          final List<Album> albums = albumsAsync.value ?? const <Album>[];
          final List<String> metaParts = <String>[
            if (artist.fansCount > 0)
              '粉丝 ${Formatters.playCount(artist.fansCount)}',
            if (songs.isNotEmpty)
              '${songs.length} 首单曲'
            else if (artist.songCount > 0)
              '${artist.songCount} 首单曲',
            if (albums.isNotEmpty)
              '${albums.length} 张专辑'
            else if (artist.albumCount > 0)
              '${artist.albumCount} 张专辑',
          ];

          return Column(
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
                              ?.copyWith(color: context.palette.textSecondary),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(artist.name, style: theme.textTheme.displaySmall),
                        if (metaParts.isNotEmpty) ...<Widget>[
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            metaParts.join(' · '),
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: context.palette.textSecondary),
                          ),
                        ],
                        if (artist.bio.isNotEmpty) ...<Widget>[
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            artist.bio,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: context.palette.textSecondary),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.lg),
                        Row(
                          children: <Widget>[
                            FilledButton.icon(
                              onPressed: songs.isEmpty
                                  ? null
                                  : () => ref
                                      .read(playerControllerProvider.notifier)
                                      .playQueue(songs),
                              icon: const Icon(Icons.play_arrow_rounded,
                                  size: 18),
                              label: const Text('播放热门歌曲'),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            OutlinedButton.icon(
                              onPressed: songsAsync.isLoading
                                  ? null
                                  : () =>
                                      ref.invalidate(artistSongsProvider(artistId)),
                              icon: const Icon(Icons.refresh_rounded, size: 18),
                              label: const Text('刷新'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxl),
              SectionHeader(
                title: '热门歌曲',
                subtitle: songsAsync.when(
                  loading: () => '正在拉取歌手歌曲…',
                  error: (Object error, StackTrace stack) => '歌曲加载失败',
                  data: (List<Song> list) =>
                      list.isEmpty ? '暂无歌曲' : '共 ${list.length} 首',
                ),
              ),
              songsAsync.when(
                loading: () => const _ArtistLoading(label: '正在加载歌手歌曲…'),
                error: (Object error, StackTrace stack) => EmptyState(
                  title: '歌曲加载失败',
                  description: _describeError(error),
                  icon: Icons.music_off_rounded,
                  actionLabel: '重试',
                  onActionTap: () => ref.invalidate(artistSongsProvider(artistId)),
                  compact: true,
                ),
                data: (List<Song> list) {
                  if (list.isEmpty) {
                    return EmptyState(
                      title: '该歌手暂无歌曲',
                      description: '接口返回的歌曲列表为空，可能需要登录或歌手已下架。',
                      icon: Icons.music_off_rounded,
                      actionLabel: '重新加载',
                      onActionTap: () =>
                          ref.invalidate(artistSongsProvider(artistId)),
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
              const SizedBox(height: AppSpacing.xl),
              SectionHeader(
                title: '专辑',
                subtitle: albumsAsync.when(
                  loading: () => '正在拉取歌手专辑…',
                  error: (Object error, StackTrace stack) => '专辑加载失败',
                  data: (List<Album> list) =>
                      list.isEmpty ? '暂无专辑' : '共 ${list.length} 张',
                ),
              ),
              albumsAsync.when(
                loading: () => const _ArtistLoading(label: '正在加载歌手专辑…'),
                error: (Object error, StackTrace stack) => EmptyState(
                  title: '专辑加载失败',
                  description: _describeError(error),
                  icon: Icons.album_outlined,
                  actionLabel: '重试',
                  onActionTap: () => ref.invalidate(artistAlbumsProvider(artistId)),
                  compact: true,
                ),
                data: (List<Album> list) {
                  if (list.isEmpty) {
                    return EmptyState(
                      title: '该歌手暂无专辑',
                      description: '接口返回的专辑列表为空，可能需要登录或歌手已下架。',
                      icon: Icons.album_outlined,
                      actionLabel: '重新加载',
                      onActionTap: () =>
                          ref.invalidate(artistAlbumsProvider(artistId)),
                      compact: true,
                    );
                  }
                  return Wrap(
                    spacing: AppSpacing.lg,
                    runSpacing: AppSpacing.lg,
                    children: list
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

  void _refreshAll(WidgetRef ref) {
    ref.invalidate(artistDetailProvider(artistId));
    ref.invalidate(artistSongsProvider(artistId));
    ref.invalidate(artistAlbumsProvider(artistId));
  }
}

class _ArtistLoading extends StatelessWidget {
  const _ArtistLoading({required this.label});

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
                  ?.copyWith(color: context.palette.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

String _describeError(Object error) =>
    error is KugouApiException ? error.message : '网络请求失败：$error';
