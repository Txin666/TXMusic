import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/detail_hero.dart';
import '../../../shared/widgets/page_container.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../shared/widgets/song_tile.dart';
import '../../../theme/app_spacing.dart';
import '../../player/application/player_controller.dart';
import '../../song/data/fake_song_data.dart';
import '../../song/domain/song.dart';
import '../application/rank_providers.dart';
import '../domain/rank_item.dart';

/// 榜单详情页（路由 `/rank/:id`）。
class RankDetailPage extends ConsumerWidget {
  const RankDetailPage({super.key, required this.rankId});

  final String rankId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final RankItem rank = ref.watch(rankDetailProvider(rankId));
    final List<Song> songs = FakeSongs.byIds(rank.songIds);

    return PageContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          DetailHero(
            seed: rank.title,
            title: rank.title,
            typeLabel: '排行榜',
            icon: Icons.leaderboard_rounded,
            meta: <String>[
              rank.subtitle,
              rank.updateNote,
              '${songs.length} 首',
            ].where((String item) => item.isNotEmpty).join(' · '),
            onPrimaryTap: songs.isEmpty
                ? null
                : () => ref
                    .read(playerControllerProvider.notifier)
                    .playQueue(songs),
          ),
          const SizedBox(height: AppSpacing.xl),
          SectionHeader(title: '榜单曲目', subtitle: '骨架期示例排名'),
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
        ],
      ),
    );
  }
}
