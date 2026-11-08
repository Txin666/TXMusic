import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/formatters.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/page_container.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../shared/widgets/song_tile.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../player/application/player_controller.dart';
import '../../song/domain/song.dart';
import '../application/library_providers.dart';
import '../data/fake_library_data.dart';

enum _LibraryTab { favorite, recent }

/// 我的音乐（路由 `/library`）：收藏 / 最近播放。
///
/// TODO(storage): 收藏与历史应来自本地 Hive（文档 §8），当前为假数据。
class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  _LibraryTab _tab = _LibraryTab.favorite;

  @override
  Widget build(BuildContext context) {
    final List<Song> favorites = ref.watch(favoriteSongsProvider);
    final List<Song> recents = ref.watch(recentSongsProvider);
    final List<Song> current = _tab == _LibraryTab.favorite ? favorites : recents;
    final ThemeData theme = Theme.of(context);

    return PageContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('我的音乐', style: theme.textTheme.headlineMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '收藏与最近播放（骨架期示例数据，接入本地数据库后为真实记录）',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          SegmentedButton<_LibraryTab>(
            showSelectedIcon: false,
            segments: <ButtonSegment<_LibraryTab>>[
              ButtonSegment<_LibraryTab>(
                value: _LibraryTab.favorite,
                icon: const Icon(Icons.favorite_rounded, size: 16),
                label: Text('我喜欢的音乐 ${favorites.length}'),
              ),
              ButtonSegment<_LibraryTab>(
                value: _LibraryTab.recent,
                icon: const Icon(Icons.history_rounded, size: 16),
                label: Text('最近播放 ${recents.length}'),
              ),
            ],
            selected: <_LibraryTab>{_tab},
            onSelectionChanged: (Set<_LibraryTab> selection) =>
                setState(() => _tab = selection.first),
          ),
          const SizedBox(height: AppSpacing.xl),
          if (current.isEmpty)
            EmptyState(
              title: _tab == _LibraryTab.favorite ? '还没有收藏歌曲' : '还没有播放记录',
              description: '去发现页听听看，收藏后会出现在这里',
              icon: _tab == _LibraryTab.favorite
                  ? Icons.favorite_border_rounded
                  : Icons.history_toggle_off_rounded,
              actionLabel: '去发现页',
              onActionTap: () => context.go(AppRoutes.discover),
            )
          else ...<Widget>[
            SectionHeader(
              title: _tab == _LibraryTab.favorite ? '收藏歌曲' : '最近播放',
              subtitle: '共 ${current.length} 首',
              actionLabel: '全部播放',
              onActionTap: () => ref
                  .read(playerControllerProvider.notifier)
                  .playQueue(current),
            ),
            ...current.asMap().entries.map(
                  (MapEntry<int, Song> entry) => SongTile(
                    song: entry.value,
                    index: entry.key,
                    trailing: _tab == _LibraryTab.recent
                        ? Text(
                            Formatters.relative(
                              FakeLibraryData.recentTimeAt(entry.key),
                            ),
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: AppColors.textTertiary),
                          )
                        : null,
                    onTap: () => ref
                        .read(playerControllerProvider.notifier)
                        .playQueue(current, startIndex: entry.key),
                    onPlayTap: () => ref
                        .read(playerControllerProvider.notifier)
                        .playQueue(current, startIndex: entry.key),
                  ),
                ),
          ],
        ],
      ),
    );
  }
}
