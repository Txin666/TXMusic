import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/kugou_providers.dart';
import '../../../core/network/kugou_session.dart';
import '../../../core/utils/formatters.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/media_card.dart';
import '../../../shared/widgets/page_container.dart';
import '../../../shared/widgets/playback_error_banner.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../shared/widgets/song_tile.dart';
import '../../../theme/app_palette.dart';
import '../../../theme/app_spacing.dart';
import '../../album/domain/album.dart';
import '../../player/application/player_controller.dart';
import '../../playlist/domain/playlist.dart';
import '../../song/domain/song.dart';
import '../application/library_providers.dart';
import '../application/user_library_providers.dart';
import '../domain/my_music_library.dart';

/// 「我的音乐」分区：前四栏走酷狗账号接口，最后一栏仍是本机存储。
enum _LibraryTab { liked, created, collected, albums, recent }

/// 我的音乐（路由 `/library`）。
///
/// 数据来源分两类：
/// - **账号维度**（我的喜欢 / 我创建的歌单 / 我收藏的歌单 / 我收藏的专辑）来自
///   [myMusicLibraryProvider]，即真实酷狗接口，登录态变化会自动重取；
/// - **本机维度**（最近播放）来自 [libraryProvider]，落盘在 `.local` 目录，
///   不依赖登录。
///
/// 云歌单在概念版登录态下会被上游拒绝（`30227`），此时只有对应分区展示
/// 降级提示条，其余分区与「最近播放」不受影响；「我的喜欢」会自动回落到
/// 本机收藏并明确标注来源，避免用户看到莫名其妙的空白。
class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  _LibraryTab _tab = _LibraryTab.liked;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final LibraryState library = ref.watch(libraryProvider);
    final KugouSession session = ref.watch(kugouSessionProvider);
    final AsyncValue<MyMusicLibrary> apiAsync = ref.watch(
      myMusicLibraryProvider,
    );
    final MyMusicLibrary my = apiAsync.asData?.value ?? MyMusicLibrary.empty;

    return PageContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('我的音乐', style: theme.textTheme.headlineMedium),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      session.isLoggedIn
                          ? '歌单 / 专辑读取酷狗账号数据，最近播放保存在本机'
                          : '未登录：当前仅展示本机数据，登录后自动同步账号歌单与专辑',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: context.palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '刷新账号数据',
                onPressed: apiAsync.isLoading ? null : _refresh,
                icon: apiAsync.isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, size: 20),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<_LibraryTab>(
              showSelectedIcon: false,
              segments: <ButtonSegment<_LibraryTab>>[
                ButtonSegment<_LibraryTab>(
                  value: _LibraryTab.liked,
                  icon: const Icon(Icons.favorite_rounded, size: 16),
                  label: Text(
                    _label(
                      '我的喜欢',
                      my.likedSongs.isNotEmpty
                          ? my.likedSongs.length
                          : library.favorites.length,
                    ),
                  ),
                ),
                ButtonSegment<_LibraryTab>(
                  value: _LibraryTab.created,
                  icon: const Icon(Icons.queue_music_rounded, size: 16),
                  label: Text(
                    _label('我创建的歌单', my.createdPlaylists.length),
                  ),
                ),
                ButtonSegment<_LibraryTab>(
                  value: _LibraryTab.collected,
                  icon: const Icon(Icons.bookmark_rounded, size: 16),
                  label: Text(
                    _label('我收藏的歌单', my.collectedPlaylists.length),
                  ),
                ),
                ButtonSegment<_LibraryTab>(
                  value: _LibraryTab.albums,
                  icon: const Icon(Icons.album_rounded, size: 16),
                  label: Text(_label('我收藏的专辑', my.albums.length)),
                ),
                ButtonSegment<_LibraryTab>(
                  value: _LibraryTab.recent,
                  icon: const Icon(Icons.history_rounded, size: 16),
                  label: Text(_label('最近播放', library.recent.length)),
                ),
              ],
              selected: <_LibraryTab>{_tab},
              onSelectionChanged: (Set<_LibraryTab> selection) =>
                  setState(() => _tab = selection.first),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          switch (_tab) {
            _LibraryTab.liked => _buildLiked(library, my, session),
            _LibraryTab.created => _buildPlaylistSection(
              title: '我创建的歌单',
              items: my.createdPlaylists,
              error: my.playlistsError,
              emptyTitle: '还没有创建歌单',
              emptyDescription: '在酷狗客户端创建的歌单会出现在这里',
            ),
            _LibraryTab.collected => _buildPlaylistSection(
              title: '我收藏的歌单',
              items: my.collectedPlaylists,
              error: my.playlistsError,
              emptyTitle: '还没有收藏歌单',
              emptyDescription: '收藏别人的歌单后，这里会自动同步',
            ),
            _LibraryTab.albums => _buildAlbumSection(my),
            _LibraryTab.recent => _buildRecent(library),
          },
        ],
      ),
    );
  }

  void _refresh() {
    ref.invalidate(myMusicLibraryProvider);
    ref.read(libraryProvider.notifier).refresh();
  }

  /// 分区标题右侧的数字：为 0 时不显示，避免加载期间出现一堆 0。
  static String _label(String title, int count) =>
      count > 0 ? '$title $count' : title;

  // ---------------------------------------------------------------- 我的喜欢

  Widget _buildLiked(
    LibraryState library,
    MyMusicLibrary my,
    KugouSession session,
  ) {
    final bool apiAvailable = my.likedSongs.isNotEmpty;
    // 接口没有数据（失败 / 未登录 / 账号无「我喜欢」歌单）时，回落到本机收藏，
    // 并在标题上明确标注来源，不做静默混排。
    final bool useLocal = !apiAvailable;
    final List<Song> songs = useLocal ? library.favorites : my.likedSongs;
    // 真错误（接口报错）才显示红色 banner；"账号没有「我喜欢」歌单"是正常
    // 空态，只用中性提示说明来源，不能把空态渲染成故障。
    final String? errorBanner = my.likedError;
    final String? fallbackNote = useLocal && errorBanner == null
        ? (session.isLoggedIn
              ? '账号暂无「我喜欢」歌单，先展示本机收藏'
              : '未登录，展示本机收藏')
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (errorBanner != null) ...<Widget>[
          PlaybackErrorBanner(
            message: errorBanner,
            onRetry: session.isLoggedIn ? _refresh : null,
          ),
          const SizedBox(height: AppSpacing.md),
        ] else if (fallbackNote != null) ...<Widget>[
          Text(
            fallbackNote,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.palette.textDisabled,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (library.isLoading && useLocal)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
          )
        else if (songs.isEmpty)
          EmptyState(
            title: '还没有喜欢的歌曲',
            description: '在任意歌曲上点右侧爱心即可收藏；登录后可同步酷狗账号的「我喜欢」',
            icon: Icons.favorite_border_rounded,
            actionLabel: '去发现页',
            onActionTap: () => context.go(AppRoutes.discover),
          )
        else ...<Widget>[
          SectionHeader(
            title: useLocal ? '本机收藏' : '我的喜欢',
            subtitle: '共 ${songs.length} 首${useLocal ? '（本机）' : ''}',
            actionLabel: '全部播放',
            onActionTap: () =>
                ref.read(playerControllerProvider.notifier).playQueue(songs),
          ),
          ...songs.asMap().entries.map(
            (MapEntry<int, Song> entry) => SongTile(
              song: entry.value,
              index: entry.key,
              trailing: useLocal
                  ? IconButton(
                      tooltip: '取消收藏',
                      onPressed: () => ref
                          .read(libraryProvider.notifier)
                          .toggleFavorite(entry.value),
                      icon: const Icon(Icons.favorite_rounded, size: 18),
                      color: context.palette.emphasized,
                    )
                  : Text(
                      Formatters.duration(entry.value.duration),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.palette.textDisabled,
                      ),
                    ),
              onTap: () => ref
                  .read(playerControllerProvider.notifier)
                  .playQueue(songs, startIndex: entry.key),
              onPlayTap: () => ref
                  .read(playerControllerProvider.notifier)
                  .playQueue(songs, startIndex: entry.key),
            ),
          ),
        ],
      ],
    );
  }

  // ------------------------------------------------------------- 歌单 / 专辑

  Widget _buildPlaylistSection({
    required String title,
    required List<Playlist> items,
    required String? error,
    required String emptyTitle,
    required String emptyDescription,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (error != null) ...<Widget>[
          PlaybackErrorBanner(message: error, onRetry: _refresh),
          const SizedBox(height: AppSpacing.md),
        ],
        if (items.isEmpty)
          EmptyState(
            title: emptyTitle,
            description: error == null ? emptyDescription : '接口恢复后会自动同步到这里',
            icon: Icons.queue_music_rounded,
            actionLabel: '去歌单广场',
            onActionTap: () => context.go(AppRoutes.discover),
          )
        else ...<Widget>[
          SectionHeader(title: title, subtitle: '共 ${items.length} 个'),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.lg,
            children: items.map(_playlistCard).toList(growable: false),
          ),
        ],
      ],
    );
  }

  Widget _playlistCard(Playlist playlist) {
    return MediaCard(
      title: playlist.title,
      seed: playlist.title,
      coverUrl: playlist.coverUrl,
      subtitle: playlist.songCount > 0
          ? '${playlist.songCount} 首'
          : (playlist.creator.isNotEmpty ? playlist.creator : null),
      badge: playlist.creator.isNotEmpty && playlist.songCount > 0
          ? playlist.creator
          : null,
      onTap: () {
        if (!playlist.hasCollectionId) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('该歌单缺少 collection id，暂无法打开详情'),
              duration: Duration(seconds: 2),
            ),
          );
          return;
        }
        context.push(AppRoutes.playlistDetail(playlist.id));
      },
    );
  }

  Widget _buildAlbumSection(MyMusicLibrary my) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (my.albumsError != null) ...<Widget>[
          PlaybackErrorBanner(message: my.albumsError!, onRetry: _refresh),
          const SizedBox(height: AppSpacing.md),
        ],
        if (my.albums.isEmpty)
          EmptyState(
            title: '还没有收藏专辑',
            description: my.albumsError == null
                ? '在酷狗购买或收藏的数字专辑会出现在这里'
                : '接口恢复后会自动同步到这里',
            icon: Icons.album_outlined,
          )
        else ...<Widget>[
          SectionHeader(title: '我收藏的专辑', subtitle: '共 ${my.albums.length} 张'),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.lg,
            children: my.albums.map(_albumCard).toList(growable: false),
          ),
        ],
      ],
    );
  }

  Widget _albumCard(Album album) {
    return MediaCard(
      title: album.title,
      seed: album.title,
      coverUrl: album.coverUrl,
      subtitle: album.artist.isNotEmpty ? album.artist : null,
      icon: Icons.album_rounded,
      onTap: () => context.push(AppRoutes.albumDetail(album.id)),
    );
  }

  // ------------------------------------------------------------- 最近播放

  Widget _buildRecent(LibraryState library) {
    final ThemeData theme = Theme.of(context);
    final List<Song> recents = library.recent;
    if (library.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
      );
    }
    if (recents.isEmpty) {
      return EmptyState(
        title: '还没有播放记录',
        description: '去发现页听听看，播放过的歌曲会自动记录在本机',
        icon: Icons.history_toggle_off_rounded,
        actionLabel: '去发现页',
        onActionTap: () => context.go(AppRoutes.discover),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(
          title: '最近播放',
          subtitle: '共 ${recents.length} 首 · 仅存本机',
          actionLabel: '清空记录',
          onActionTap: () async {
            await ref.read(libraryProvider.notifier).clearRecent();
            if (!mounted) {
              return;
            }
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('已清空最近播放记录'),
                duration: Duration(seconds: 2),
              ),
            );
          },
        ),
        ...recents.asMap().entries.map(
          (MapEntry<int, Song> entry) => SongTile(
            song: entry.value,
            index: entry.key,
            trailing: Text(
              Formatters.duration(entry.value.duration),
              style: theme.textTheme.bodySmall?.copyWith(
                color: context.palette.textDisabled,
              ),
            ),
            onTap: () => ref
                .read(playerControllerProvider.notifier)
                .playQueue(recents, startIndex: entry.key),
            onPlayTap: () => ref
                .read(playerControllerProvider.notifier)
                .playQueue(recents, startIndex: entry.key),
          ),
        ),
      ],
    );
  }
}
