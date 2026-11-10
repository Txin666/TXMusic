import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/formatters.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/page_container.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../shared/widgets/song_tile.dart';
import '../../../theme/app_spacing.dart';
import '../../player/application/player_controller.dart';
import '../../song/domain/song.dart';
import '../application/library_providers.dart';
import '../../../theme/app_palette.dart';

enum _LibraryTab { favorite, recent }

/// 我的音乐（路由 `/library`）：收藏 / 最近播放。
///
/// 数据全部来自 [libraryProvider]（`LibraryRepository` 落盘 JSON），
/// 不再引用任何假数据；收藏 / 取消收藏、清空记录都会立即持久化。
class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  _LibraryTab _tab = _LibraryTab.favorite;

  @override
  Widget build(BuildContext context) {
    final LibraryState library = ref.watch(libraryProvider);
    final LibraryController libraryController =
        ref.read(libraryProvider.notifier);
    final List<Song> favorites = library.favorites;
    final List<Song> recents = library.recent;
    final bool isFavoriteTab = _tab == _LibraryTab.favorite;
    final List<Song> current = isFavoriteTab ? favorites : recents;
    final ThemeData theme = Theme.of(context);

    return PageContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('我的音乐', style: theme.textTheme.headlineMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '收藏与最近播放，均保存在本机（.local 目录），无需登录',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: context.palette.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
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
              if (!isFavoriteTab && recents.isNotEmpty)
                TextButton.icon(
                  onPressed: () async {
                    await libraryController.clearRecent();
                    if (!context.mounted) {
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('已清空最近播放记录'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  icon: const Icon(Icons.delete_sweep_rounded, size: 16),
                  label: const Text('清空记录'),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          if (library.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
            )
          else if (current.isEmpty)
            EmptyState(
              title: isFavoriteTab ? '还没有收藏歌曲' : '还没有播放记录',
              description: isFavoriteTab
                  ? '在任意歌曲上点右侧爱心即可收藏，收藏会立即存到本机'
                  : '去发现页听听看，播放过的歌曲会自动记录在这里',
              icon: isFavoriteTab
                  ? Icons.favorite_border_rounded
                  : Icons.history_toggle_off_rounded,
              actionLabel: '去发现页',
              onActionTap: () => context.go(AppRoutes.discover),
            )
          else ...<Widget>[
            SectionHeader(
              title: isFavoriteTab ? '收藏歌曲' : '最近播放',
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
                    trailing: isFavoriteTab
                        ? IconButton(
                            tooltip: '取消收藏',
                            onPressed: () =>
                                libraryController.toggleFavorite(entry.value),
                            icon: const Icon(Icons.favorite_rounded, size: 18),
                            color: context.palette.emphasized,
                          )
                        : Text(
                            Formatters.duration(entry.value.duration),
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: context.palette.textDisabled),
                          ),
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
