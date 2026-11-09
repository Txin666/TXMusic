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
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../album/domain/album.dart';
import '../../artist/domain/artist.dart';
import '../../player/application/player_controller.dart';
import '../../playlist/domain/playlist.dart';
import '../../song/domain/song.dart';
import '../application/search_controller.dart';

/// 错误文案统一取 [KugouApiException.message]，避免把堆栈抛给用户。
String _describeError(Object error) =>
    error is KugouApiException ? error.message : '请求失败，请检查本地接口服务';

/// 搜索页（路由 `/search`，可选 `?q=关键词` 从顶部搜索框带入）。
///
/// 结果与热搜均来自真实接口（`/search/complex`、`/search/hot/detail`），
/// 搜索历史由 `SearchHistoryRepository` 落盘，全页不引用任何假数据。
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key, this.initialQuery});

  final String? initialQuery;

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery ?? '');
    final String query = (widget.initialQuery ?? '').trim();
    if (query.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(searchPageControllerProvider.notifier).search(query);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String value) {
    ref.read(searchPageControllerProvider.notifier).search(value);
    final String key = value.trim();
    if (key.isNotEmpty) {
      // 把关键词同步到地址栏，方便前进/后退与分享（文档 §9.4 路由参数化）。
      context.go('${AppRoutes.search}?q=${Uri.encodeQueryComponent(key)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final SearchState state = ref.watch(searchPageControllerProvider);
    final SearchPageController controller =
        ref.read(searchPageControllerProvider.notifier);
    final ThemeData theme = Theme.of(context);

    return PageContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('搜索', style: theme.textTheme.headlineMedium),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _controller,
            textInputAction: TextInputAction.search,
            onSubmitted: _submit,
            onChanged: controller.updateKeyword,
            decoration: InputDecoration(
              hintText: '搜索歌曲 / 歌手 / 歌单',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: IconButton(
                tooltip: '搜索',
                icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                onPressed: () => _submit(_controller.text),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          if (state.keyword.isEmpty)
            _IdleView(
              history: state.history,
              onPick: (String keyword) {
                _controller.text = keyword;
                _submit(keyword);
              },
              onClearHistory: controller.clearHistory,
            )
          else if (state.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
            )
          else if (state.errorMessage != null)
            EmptyState(
              title: '搜索失败',
              description: state.errorMessage!,
              icon: Icons.cloud_off_rounded,
              actionLabel: '重试',
              onActionTap: () => controller.search(state.keyword),
            )
          else if (state.isEmptyResult)
            EmptyState(
              title: '没有找到「${state.keyword}」相关内容',
              description: '换个关键词试试，或确认本地 KuGouMusicApi 服务是否在运行',
              icon: Icons.search_off_rounded,
              actionLabel: '清空搜索',
              onActionTap: () {
                _controller.clear();
                controller.clear();
                context.go(AppRoutes.search);
              },
            )
          else ...<Widget>[
            if (state.notice != null && state.notice!.isNotEmpty) ...<Widget>[
              _DegradeNotice(text: state.notice!),
              const SizedBox(height: AppSpacing.md),
            ],
            if (state.songs.isNotEmpty) ...<Widget>[
              SectionHeader(
                title: '单曲',
                subtitle: '${state.songs.length} 条结果',
              ),
              ...state.songs.asMap().entries.map(
                    (MapEntry<int, Song> entry) => SongTile(
                      song: entry.value,
                      onTap: () => ref
                          .read(playerControllerProvider.notifier)
                          .playQueue(state.songs, startIndex: entry.key),
                      onPlayTap: () => ref
                          .read(playerControllerProvider.notifier)
                          .playQueue(state.songs, startIndex: entry.key),
                    ),
                  ),
              const SizedBox(height: AppSpacing.xl),
            ],
            if (state.playlists.isNotEmpty) ...<Widget>[
              SectionHeader(
                title: '歌单',
                subtitle: '${state.playlists.length} 条结果',
              ),
              Wrap(
                spacing: AppSpacing.lg,
                runSpacing: AppSpacing.lg,
                children: state.playlists
                    .map(
                      (Playlist playlist) => MediaCard(
                        title: playlist.title,
                        seed: playlist.title,
                        subtitle: '${playlist.songCount} 首 · '
                            '${Formatters.playCount(playlist.playCount)}',
                        onTap: () => context
                            .go(AppRoutes.playlistDetail(playlist.id)),
                      ),
                    )
                    .toList(growable: false),
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
            if (state.artists.isNotEmpty) ...<Widget>[
              SectionHeader(
                title: '歌手',
                subtitle: '${state.artists.length} 条结果',
              ),
              Wrap(
                spacing: AppSpacing.lg,
                runSpacing: AppSpacing.lg,
                children: state.artists
                    .map(
                      (Artist artist) => _ArtistResultTile(
                        artist: artist,
                        onTap: () =>
                            context.go(AppRoutes.artistDetail(artist.id)),
                      ),
                    )
                    .toList(growable: false),
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
            if (state.albums.isNotEmpty) ...<Widget>[
              SectionHeader(
                title: '专辑',
                subtitle: '${state.albums.length} 条结果',
              ),
              Wrap(
                spacing: AppSpacing.lg,
                runSpacing: AppSpacing.lg,
                children: state.albums
                    .map(
                      (Album album) => MediaCard(
                        title: album.title,
                        seed: album.title,
                        subtitle: album.artist.isEmpty
                            ? '${album.trackCount} 首'
                            : '${album.artist} · ${album.trackCount} 首',
                        icon: Icons.album_rounded,
                        onTap: () => context.go(AppRoutes.albumDetail(album.id)),
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _IdleView extends ConsumerWidget {
  const _IdleView({
    required this.history,
    required this.onPick,
    required this.onClearHistory,
  });

  final List<String> history;
  final ValueChanged<String> onPick;
  final VoidCallback onClearHistory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(
          title: '搜索历史',
          subtitle: history.isEmpty ? '暂无历史记录' : '点击可快速检索',
          actionLabel: history.isEmpty ? null : '清空',
          onActionTap: onClearHistory,
        ),
        if (history.isNotEmpty)
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: history
                .map(
                  (String item) => ActionChip(
                    label: Text(item),
                    avatar: const Icon(Icons.history_rounded, size: 14),
                    onPressed: () => onPick(item),
                  ),
                )
                .toList(growable: false),
          ),
        const SizedBox(height: AppSpacing.xxl),
        const SectionHeader(title: '热搜榜', subtitle: '来自酷狗实时热搜'),
        ref.watch(hotKeywordsProvider).when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
              ),
              error: (Object error, StackTrace stackTrace) => Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        '热搜加载失败：${_describeError(error)}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                    ),
                    TextButton(
                      onPressed: () => ref.invalidate(hotKeywordsProvider),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
              data: (List<String> keywords) {
                if (keywords.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                    child: Text(
                      '暂时没有热搜数据，直接输入关键词搜索吧',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: keywords.asMap().entries.map(
                    (MapEntry<int, String> entry) => ListTile(
                      onTap: () => onPick(entry.value),
                      contentPadding: EdgeInsets.zero,
                      leading: SizedBox(
                        width: 24,
                        child: Text(
                          '${entry.key + 1}'.padLeft(2, '0'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: entry.key < 3
                                ? AppColors.primary
                                : AppColors.textTertiary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      title:
                          Text(entry.value, style: theme.textTheme.bodyMedium),
                      trailing: const Icon(Icons.north_east_rounded, size: 15),
                    ),
                  ).toList(growable: false),
                );
              },
            ),
      ],
    );
  }
}

class _DegradeNotice extends StatelessWidget {
  const _DegradeNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.info_outline_rounded,
              size: 16, color: AppColors.textTertiary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArtistResultTile extends StatelessWidget {
  const _ArtistResultTile({required this.artist, required this.onTap});

  final Artist artist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: SizedBox(
        width: 168,
        child: Column(
          children: <Widget>[
            ArtistAvatar(name: artist.name, size: 120),
            const SizedBox(height: AppSpacing.sm),
            Text(
              artist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            Text(
              // 聚合搜索返回的歌手字段未必带粉丝数，缺失时不展示 0。
              artist.fansCount > 0
                  ? '粉丝 ${Formatters.playCount(artist.fansCount)}'
                  : '歌手',
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
