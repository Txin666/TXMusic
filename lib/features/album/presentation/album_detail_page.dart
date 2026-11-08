import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/formatters.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/widgets/detail_hero.dart';
import '../../../shared/widgets/page_container.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../shared/widgets/song_tile.dart';
import '../../../theme/app_spacing.dart';
import '../../artist/data/fake_artist_data.dart';
import '../../artist/domain/artist.dart';
import '../../player/application/player_controller.dart';
import '../../song/data/fake_song_data.dart';
import '../../song/domain/song.dart';
import '../application/album_providers.dart';
import '../domain/album.dart';

/// 专辑详情页（路由 `/album/:id`）。
class AlbumDetailPage extends ConsumerWidget {
  const AlbumDetailPage({super.key, required this.albumId});

  final String albumId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Album album = ref.watch(albumDetailProvider(albumId));
    final List<Song> songs = FakeSongs.byIds(album.songIds);
    final Artist artist = FakeArtists.byName(album.artist);

    return PageContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          DetailHero(
            seed: album.title,
            title: album.title,
            typeLabel: '专辑',
            icon: Icons.album_rounded,
            meta: '${album.artist} · ${album.releaseDate} · '
                '${album.songCount} 首 · 播放 ${Formatters.playCount(album.playCount)}',
            onPrimaryTap: songs.isEmpty
                ? null
                : () => ref
                    .read(playerControllerProvider.notifier)
                    .playQueue(songs),
            secondaryLabel: '查看歌手',
            onSecondaryTap: () =>
                context.go(AppRoutes.artistDetail(artist.id)),
          ),
          const SizedBox(height: AppSpacing.xl),
          SectionHeader(title: '专辑曲目', subtitle: '共 ${songs.length} 首'),
          ...songs.asMap().entries.map(
                (MapEntry<int, Song> entry) => SongTile(
                  song: entry.value,
                  index: entry.key,
                  showAlbum: false,
                  onTap: () => ref
                      .read(playerControllerProvider.notifier)
                      .playQueue(songs, startIndex: entry.key),
                  onPlayTap: () => ref
                      .read(playerControllerProvider.notifier)
                      .playQueue(songs, startIndex: entry.key),
                ),
              ),
        ],
      ),
    );
  }
}
