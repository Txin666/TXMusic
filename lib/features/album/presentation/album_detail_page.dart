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
import '../application/album_providers.dart';
import '../domain/album.dart';

/// 专辑详情页（路由 `/album/:id`）。
///
/// 元信息走 `/album/detail`（[albumDetailProvider]），曲目走 `/album/songs`
/// （[albumSongsProvider]），两块独立三态渲染；歌手跳转使用接口返回的真实
/// `artistId`，不再回退到假数据按名称匹配。
class AlbumDetailPage extends ConsumerWidget {
  const AlbumDetailPage({super.key, required this.albumId});

  final String albumId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Album?> albumAsync = ref.watch(albumDetailProvider(albumId));
    final AsyncValue<List<Song>> songsAsync = ref.watch(albumSongsProvider(albumId));

    return PageContainer(
      child: albumAsync.when(
        loading: () => const _DetailLoading(label: '正在加载专辑信息…'),
        error: (Object error, StackTrace stack) => EmptyState(
          title: '专辑加载失败',
          description: _describeError(error),
          icon: Icons.cloud_off_rounded,
          actionLabel: '重新加载',
          onActionTap: () {
            ref.invalidate(albumDetailProvider(albumId));
            ref.invalidate(albumSongsProvider(albumId));
          },
        ),
        data: (Album? album) {
          if (album == null) {
            return EmptyState(
              title: '专辑不存在或已下架',
              description: '没有找到 ID 为 $albumId 的专辑。',
              icon: Icons.album_outlined,
              actionLabel: '返回发现页',
              onActionTap: () => context.go(AppRoutes.discover),
            );
          }

          final List<Song> songs = songsAsync.value ?? const <Song>[];
          final List<String> metaParts = <String>[
            if (album.artist.isNotEmpty) album.artist,
            if (album.releaseDate.isNotEmpty) '发行于 ${album.releaseDate}',
            if (songs.isNotEmpty)
              '${songs.length} 首'
            else if (album.songCount > 0)
              '${album.songCount} 首',
            if (album.playCount > 0)
              '${Formatters.playCount(album.playCount)}次播放',
          ];
          final bool canOpenArtist = album.artistId.isNotEmpty;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              DetailHero(
                seed: album.title,
                title: album.title,
                typeLabel: '专辑',
                icon: Icons.album_rounded,
                meta: metaParts.isEmpty ? null : metaParts.join(' · '),
                description: album.intro,
                onPrimaryTap: songs.isEmpty
                    ? null
                    : () => ref
                        .read(playerControllerProvider.notifier)
                        .playQueue(songs),
                secondaryLabel: canOpenArtist ? '查看歌手' : null,
                onSecondaryTap: canOpenArtist
                    ? () => context.push(AppRoutes.artistDetail(album.artistId))
                    : null,
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionHeader(
                title: '专辑曲目',
                subtitle: songsAsync.when(
                  loading: () => '曲目加载中…',
                  error: (Object error, StackTrace stack) => '曲目加载失败',
                  data: (List<Song> list) => '共 ${list.length} 首',
                ),
              ),
              songsAsync.when(
                loading: () => const _DetailLoading(label: '正在加载专辑曲目…'),
                error: (Object error, StackTrace stack) => EmptyState(
                  title: '曲目加载失败',
                  description: _describeError(error),
                  icon: Icons.music_off_rounded,
                  actionLabel: '重试',
                  onActionTap: () => ref.invalidate(albumSongsProvider(albumId)),
                  compact: true,
                ),
                data: (List<Song> list) {
                  if (list.isEmpty) {
                    return EmptyState(
                      title: '该专辑暂无曲目',
                      description: '接口返回的曲目列表为空，可能专辑已下架或需要登录。',
                      icon: Icons.music_off_rounded,
                      actionLabel: '重新加载',
                      onActionTap: () =>
                          ref.invalidate(albumSongsProvider(albumId)),
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
