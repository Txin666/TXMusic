import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/kugou_client.dart';
import '../../../core/network/kugou_providers.dart';
import '../../../core/utils/formatters.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/widgets/cover_image.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/playback_error_banner.dart';
import '../../../shared/widgets/song_tile.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../library/application/liked_songs_providers.dart';
import '../../library/data/kugou_collect_api.dart';
import '../../lyric/application/lyric_providers.dart';
import '../../lyric/domain/lyric_index.dart';
import '../../lyric/domain/lyric_line.dart';
import '../../player/application/player_controller.dart';
import '../../player/domain/playback_state.dart';
import '../../song/domain/song.dart';
import '../../../theme/app_palette.dart';

/// 播放详情页（路由 `/player`，脱离 Shell 全屏展示）。
///
/// 歌词来自真实接口（[lyricLinesProvider]，family key 用 [lyricKeyOf]），
/// 高亮行由播放位置 + [LyricIndex.indexAt] 二分定位；曲目加载 / 解析 /
/// 播放失败时在顶部展示 [PlaybackErrorBanner] 并提供重试。
class PlayerPage extends ConsumerWidget {
  const PlayerPage({super.key});

  /// 歌词区宽度上限：超过就不再变宽，多出来的空间均匀留在整块内容两侧，
  /// 避免歌词一路拉满、把封面视觉上「挤」在最左边。
  static const double _lyricsMaxWidth = 920;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PlaybackSnapshot playback = ref.watch(playerControllerProvider);
    final PlayerController controller = ref.read(
      playerControllerProvider.notifier,
    );
    final ThemeData theme = Theme.of(context);

    if (!playback.hasSong) {
      return Scaffold(
        body: EmptyState(
          title: '当前没有播放中的歌曲',
          description: '从发现页、歌单或搜索结果中选择一首开始播放',
          icon: Icons.play_circle_outline_rounded,
          actionLabel: '去发现页',
          onActionTap: () => context.go(AppRoutes.discover),
        ),
      );
    }

    final Song song = playback.currentSong!;
    final AsyncValue<List<LyricLine>> lyricsAsync = ref.watch(
      lyricLinesProvider(lyricKeyOf(song)),
    );

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              context.palette.surfaceAlt,
              context.palette.background,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: AppSpacing.page,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    IconButton(
                      tooltip: '收起播放页',
                      onPressed: () {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go(AppRoutes.discover);
                        }
                      },
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      '正在播放',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: context.palette.textSecondary,
                      ),
                    ),
                  ],
                ),
                if (playback.errorMessage != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  PlaybackErrorBanner(
                    message: playback.errorMessage!,
                    onRetry: _retry(controller, playback),
                  ),
                ],
                Expanded(
                  child: LayoutBuilder(
                    builder:
                        (BuildContext context, BoxConstraints constraints) {
                          // 宽度区间：窄窗口按可用宽度排版，宽窗口封顶后整体居中，
                          // 不再让封面和歌词被越拉越远。
                          final double maxAvailableWidth =
                              constraints.maxWidth > AppSpacing.maxContentWidth
                              ? AppSpacing.maxContentWidth
                              : constraints.maxWidth;
                          // 封面随可用高度自适应，但锁在区间内，不会太大也不会太小。
                          final double coverSize =
                              (constraints.maxHeight * 0.46).clamp(
                                180.0,
                                340.0,
                              );
                          // 歌词区单独封顶：宽屏下不让它一路顶到内容框右边，
                          // 否则整块重心偏右，封面就被看成了「被挤到左边」。
                          final double remainingWidth =
                              maxAvailableWidth - coverSize - AppSpacing.xxl;
                          final double lyricsWidth =
                              remainingWidth > _lyricsMaxWidth
                              ? _lyricsMaxWidth
                              : remainingWidth;
                          return Center(
                            child: SizedBox(
                              // 整块内容宽度 = 封面列 + 间距 + 歌词列，
                              // 窗口再宽也只在外侧留余量，左右对称。
                              width: coverSize + AppSpacing.xxl + lyricsWidth,
                              child: Row(
                                // 交叉轴拉伸：歌词列表要占满整行高度，不能按内容收缩。
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: <Widget>[
                                  // 左列宽度等于封面宽度：窗口变宽只加右侧余量，
                                  // 两栏间距恒定，不会跟着窗口一路变宽。
                                  SizedBox(
                                    width: coverSize,
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: <Widget>[
                                        CoverImage(
                                          seed: song.album,
                                          url: song.coverUrl,
                                          size: coverSize,
                                          radius: AppRadius.lg,
                                          icon: Icons.album_rounded,
                                        ),
                                        const SizedBox(height: AppSpacing.xl),
                                        Text(
                                          song.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style: theme.textTheme.headlineMedium,
                                        ),
                                        const SizedBox(height: AppSpacing.xs),
                                        Text(
                                          '${song.artist} · ${song.album}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                                color: context
                                                    .palette
                                                    .textSecondary,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.xxl),
                                  SizedBox(
                                    width: lyricsWidth,
                                    child: _LyricPane(
                                      lyricsAsync: lyricsAsync,
                                      position: playback.position,
                                      onSeek: controller.seek,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                  ),
                ),
                // 进度条 / 控制按钮同样限宽居中，宽屏下不会横跨整页。
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AppSpacing.maxContentWidth,
                    ),
                    child: _TransportBar(
                      playback: playback,
                      controller: controller,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  VoidCallback? _retry(PlayerController controller, PlaybackSnapshot playback) {
    if (!playback.hasSong) {
      return null;
    }
    final Song song = playback.currentSong!;
    return () {
      if (playback.queue.isEmpty) {
        controller.playSong(song);
        return;
      }
      controller.playQueue(
        playback.queue,
        startIndex: playback.queueIndex < 0 ? 0 : playback.queueIndex,
      );
    };
  }
}

/// 歌词区：真实歌词三态（加载中 / 失败 / 有数据）各自独立渲染。
///
/// 有歌词时是完整可滚动的歌词列表：
/// - 默认跟随播放进度，当前行始终停在视口正中；
/// - 鼠标滚轮 / 拖动一旦发生就暂停跟随，避免和用户抢滚动位置；
/// - 暂停后 3 秒内没有点击任何歌词行跳转，就自动回到当前播放行继续跟随
///   （不额外弹提示，避免挡住歌词）；
/// - 暂停期间双击任意歌词行会 seek 到该行时间点并立刻恢复跟随
///   （单击不跳转，留给浏览，避免误触跳走一大段）。
class _LyricPane extends StatefulWidget {
  const _LyricPane({
    required this.lyricsAsync,
    required this.position,
    required this.onSeek,
  });

  final AsyncValue<List<LyricLine>> lyricsAsync;
  final Duration position;
  final ValueChanged<Duration> onSeek;

  @override
  State<_LyricPane> createState() => _LyricPaneState();
}

class _LyricPaneState extends State<_LyricPane> {
  /// 每行固定高度：固定 itemExtent 才能用滚动偏移精确算出「第几行居中」。
  static const double _lineExtent = 56;

  /// 播放位置跳变超过这个阈值（拖动进度条 / 重播）就恢复自动跟随。
  static const Duration _seekThreshold = Duration(seconds: 2);

  /// 手动浏览后多久没双击歌词跳转，就自动回到当前播放行。
  static const Duration _autoResumeDelay = Duration(seconds: 3);

  final ScrollController _scroll = ScrollController();

  /// true = 跟随播放进度；滚轮 / 拖动后置 false，交给用户自己浏览。
  bool _autoFollow = true;

  /// 上一次自动跟随到的行号，避免每次位置刷新都重复滚动。
  int _followedLine = -1;

  /// 当前高亮行，暂停跟随期间也要能随时取到（自动恢复时用）。
  int _currentLine = 0;

  /// 闲置自动恢复计时器：暂停跟随起算，到点没双击歌词就回到当前播放。
  Timer? _resumeTimer;

  @override
  void initState() {
    super.initState();
    _currentLine = _currentLineOf(widget.lyricsAsync);
  }

  int _currentLineOf(AsyncValue<List<LyricLine>> lyricsAsync) {
    final List<LyricLine>? lyrics = lyricsAsync.asData?.value;
    if (lyrics == null || lyrics.isEmpty) {
      return 0;
    }
    return LyricIndex.indexAt(lyrics, widget.position);
  }

  @override
  void didUpdateWidget(covariant _LyricPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 换歌（歌词来源变了）：位置、跟随状态、滚动位置全部归零重来。
    if (!identical(oldWidget.lyricsAsync, widget.lyricsAsync)) {
      _cancelResumeTimer();
      _followedLine = -1;
      _autoFollow = true;
      if (_scroll.hasClients) {
        _scroll.jumpTo(0);
      }
      return;
    }
    // 位置被外部大幅改动（拖动进度条、重播）时恢复跟随，否则会一直卡在手动态。
    final int delta = (widget.position - oldWidget.position).inMilliseconds
        .abs();
    if (delta > _seekThreshold.inMilliseconds) {
      _cancelResumeTimer();
      _autoFollow = true;
    }
  }

  @override
  void dispose() {
    _cancelResumeTimer();
    _scroll.dispose();
    super.dispose();
  }

  void _cancelResumeTimer() {
    _resumeTimer?.cancel();
    _resumeTimer = null;
  }

  /// 让第 [line] 行停在视口正中。
  void _scrollToLine(int line, {required bool animate}) {
    if (!_scroll.hasClients) {
      return;
    }
    final double target = (line * _lineExtent).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    if ((_scroll.offset - target).abs() < 1) {
      return;
    }
    if (animate) {
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    } else {
      _scroll.jumpTo(target);
    }
  }

  /// 用户一动（滚轮 / 拖动 / 惯性），立刻交还滚动控制权，
  /// 并重新计时：到点仍未双击歌词跳转就自动回到当前播放。
  void _pauseFollow() {
    _cancelResumeTimer();
    _resumeTimer = Timer(_autoResumeDelay, () {
      _resumeTimer = null;
      if (!mounted || _autoFollow) {
        return;
      }
      _resumeFollow(_currentLine);
    });
    if (_autoFollow) {
      setState(() => _autoFollow = false);
    }
  }

  void _resumeFollow(int currentLine) {
    _cancelResumeTimer();
    if (!mounted) {
      return;
    }
    setState(() {
      _autoFollow = true;
      _followedLine = currentLine;
      _currentLine = currentLine;
    });
    _scrollToLine(currentLine, animate: true);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return widget.lyricsAsync.when(
      loading: () => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              '正在加载歌词…',
              style: theme.textTheme.bodySmall?.copyWith(
                color: context.palette.textSecondary,
              ),
            ),
          ],
        ),
      ),
      error: (Object error, StackTrace stack) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.lyrics_outlined,
              size: 28,
              color: context.palette.textDisabled,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '歌词加载失败',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: context.palette.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '$error',
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: context.palette.textDisabled,
              ),
            ),
          ],
        ),
      ),
      data: (List<LyricLine> lyrics) {
        if (lyrics.isEmpty) {
          return Center(
            child: Text(
              '暂无歌词',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: context.palette.textSecondary,
              ),
            ),
          );
        }

        final int currentLine = LyricIndex.indexAt(lyrics, widget.position);
        _currentLine = currentLine;
        if (currentLine != _followedLine) {
          _followedLine = currentLine;
          if (_autoFollow) {
            // build 期间不能直接滚，排到帧末再对齐当前行。
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _autoFollow) {
                _scrollToLine(currentLine, animate: true);
              }
            });
          }
        }

        return ShaderMask(
          // 上下边缘淡出，滚动时不会有硬切边。
          shaderCallback: (Rect bounds) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Color(0x00000000),
              Color(0xFF000000),
              Color(0xFF000000),
              Color(0x00000000),
            ],
            stops: <double>[0, 0.1, 0.9, 1],
          ).createShader(bounds),
          blendMode: BlendMode.dstIn,
          child: _buildLineList(theme, lyrics, currentLine),
        );
      },
    );
  }

  Widget _buildLineList(
    ThemeData theme,
    List<LyricLine> lyrics,
    int currentLine,
  ) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // 上下各留半屏空白，首末行也能停在视口正中。
        final double verticalPad = ((constraints.maxHeight - _lineExtent) / 2)
            .clamp(0.0, double.infinity);
        return Listener(
          onPointerSignal: (PointerSignalEvent event) {
            // 桌面上滚轮走 PointerSignal，不一定产生 UserScrollNotification。
            if (event is PointerScrollEvent && event.scrollDelta.dy != 0) {
              _pauseFollow();
            }
          },
          child: NotificationListener<ScrollNotification>(
            onNotification: (ScrollNotification notification) {
              // 拖动皮肤 / 滚动条 / 惯性滚动都算用户操作。
              if (notification is UserScrollNotification ||
                  (notification is ScrollStartNotification &&
                      notification.dragDetails != null)) {
                _pauseFollow();
              }
              return false;
            },
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context)
                  .copyWith(scrollbars: false),
              child: ListView.builder(
                controller: _scroll,
                itemExtent: _lineExtent,
                padding: EdgeInsets.symmetric(vertical: verticalPad),
                itemCount: lyrics.length,
                itemBuilder: (BuildContext context, int index) {
                  final LyricLine line = lyrics[index];
                  return _LyricLineTile(
                    text: line.text,
                    time: line.time,
                    isCurrent: index == currentLine,
                    onDoubleTap: () {
                      widget.onSeek(line.time);
                      _resumeFollow(index);
                    },
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 单行歌词：整体居中，hover 高亮并在文本后补上该行时间戳，
/// 双击跳到该行时间点（单击留给浏览，避免误触跳走）。
class _LyricLineTile extends StatefulWidget {
  const _LyricLineTile({
    required this.text,
    required this.time,
    required this.isCurrent,
    required this.onDoubleTap,
  });

  final String text;

  /// 该行对应的时间点，hover 时显示在歌词后面，方便判断会跳到哪一段。
  final Duration time;
  final bool isCurrent;
  final VoidCallback onDoubleTap;

  @override
  State<_LyricLineTile> createState() => _LyricLineTileState();
}

class _LyricLineTileState extends State<_LyricLineTile> {
  /// 时间胶囊的固定槽位宽度：够放 `1:23:45` 这类长时间戳。
  static const double _timeSlotWidth = 64;

  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppPalette palette = context.palette;
    final Color color = widget.isCurrent
        ? palette.emphasized
        : (_hovered ? palette.textPrimary : palette.textSecondary);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (PointerEnterEvent event) => setState(() => _hovered = true),
      onExit: (PointerExitEvent event) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // 双击才跳转：单击太容易在滚轮浏览时误触，跳过一整段。
        onDoubleTap: widget.onDoubleTap,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hovered ? palette.hoverOverlay : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Row(
            children: <Widget>[
              // 左右各留一个等宽槽位：歌词视觉居中，时间固定在行尾。
              const SizedBox(width: _timeSlotWidth),
              Expanded(
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style:
                      (widget.isCurrent
                              ? theme.textTheme.headlineSmall
                              : theme.textTheme.titleMedium)
                          ?.copyWith(
                            color: color,
                            fontWeight: widget.isCurrent
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ) ??
                      const TextStyle(),
                  child: Text(widget.text, textAlign: TextAlign.center),
                ),
              ),
              SizedBox(
                width: _timeSlotWidth,
                // 时间右对齐贴行尾，hover 才出现；强调色胶囊保证足够醒目。
                child: _hovered
                    ? Align(
                        alignment: Alignment.centerRight,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: palette.emphasized.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: AppSpacing.xxs,
                            ),
                            child: Text(
                              Formatters.duration(widget.time),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: palette.emphasized,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TransportBar extends ConsumerWidget {
  const _TransportBar({required this.playback, required this.controller});

  final PlaybackSnapshot playback;
  final PlayerController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final Song? currentSong = playback.currentSong;
    final AsyncValue<LikedSongsSnapshot> likedState = ref.watch(
      likedSongsProvider,
    );
    final bool liked =
        currentSong != null &&
        (likedState.asData?.value.has(currentSong.hash) ?? false);
    final bool loggedIn = ref.watch(kugouSessionProvider).isLoggedIn;
    final bool canCollect = currentSong != null && loggedIn;
    final double maxSeconds = playback.duration.inSeconds
        .clamp(1, 24 * 3600)
        .toDouble();
    final double value = playback.position.inSeconds
        .clamp(0, playback.duration.inSeconds)
        .toDouble();

    return Column(
      children: <Widget>[
        Slider(
          value: value,
          max: maxSeconds,
          onChanged: (double seconds) =>
              controller.seek(Duration(seconds: seconds.round())),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Row(
            children: <Widget>[
              Text(
                Formatters.duration(playback.position),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: context.palette.textDisabled,
                ),
              ),
              const Spacer(),
              Text(
                Formatters.duration(playback.duration),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: context.palette.textDisabled,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            IconButton(
              tooltip: !loggedIn ? '登录后可同步收藏' : (liked ? '取消收藏' : '收藏到「我喜欢」'),
              onPressed: canCollect
                  ? () => _toggleLiked(context, ref, currentSong)
                  : null,
              icon: Icon(
                liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              ),
              color: liked
                  ? context.palette.emphasized
                  : context.palette.textSecondary,
            ),
            const SizedBox(width: AppSpacing.lg),
            IconButton(
              tooltip: playback.repeatMode.label,
              onPressed: controller.cycleRepeatMode,
              icon: Icon(
                playback.repeatMode == RepeatMode.one
                    ? Icons.repeat_one_rounded
                    : Icons.repeat_rounded,
                color: playback.repeatMode == RepeatMode.none
                    ? context.palette.textSecondary
                    : context.palette.emphasized,
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            IconButton(
              tooltip: '上一首',
              iconSize: 30,
              onPressed: controller.skipPrevious,
              icon: const Icon(Icons.skip_previous_rounded),
            ),
            const SizedBox(width: AppSpacing.sm),
            Container(
              width: 60,
              height: 60,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                tooltip: playback.isPlaying ? '暂停' : '播放',
                iconSize: 32,
                color: const Color(0xFF04120C),
                onPressed: controller.togglePlayPause,
                icon: Icon(
                  playback.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton(
              tooltip: '下一首',
              iconSize: 30,
              onPressed: controller.skipNext,
              icon: const Icon(Icons.skip_next_rounded),
            ),
            const SizedBox(width: AppSpacing.lg),
            Row(
              children: <Widget>[
                IconButton(
                  tooltip: playback.muted ? '取消静音' : '静音',
                  onPressed: controller.toggleMute,
                  icon: Icon(
                    playback.muted
                        ? Icons.volume_off_rounded
                        : Icons.volume_up_rounded,
                  ),
                ),
                SizedBox(
                  width: 96,
                  child: Slider(
                    value: playback.muted ? 0 : playback.volume,
                    onChanged: controller.setVolume,
                  ),
                ),
              ],
            ),
            const SizedBox(width: AppSpacing.lg),
            IconButton(
              tooltip: '播放队列（${playback.queue.length} 首）',
              onPressed: () => _showQueue(context),
              icon: const Icon(Icons.queue_music_rounded),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
    );
  }

  /// 收藏 / 取消收藏：写服务器后本地镜像同步，「我的音乐」页随之刷新。
  Future<void> _toggleLiked(
    BuildContext context,
    WidgetRef ref,
    Song song,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      final bool liked = await ref
          .read(likedSongsProvider.notifier)
          .toggle(song);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(liked ? '已收藏到「我喜欢」' : '已从「我喜欢」移除'),
            duration: const Duration(seconds: 2),
          ),
        );
    } on KugouApiException catch (error) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('收藏失败：${error.message}')));
    } on Object catch (error) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('收藏失败：$error')));
    }
  }

  void _showQueue(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.palette.surfaceAlt,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: SizedBox(
            height: 420,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.sm,
                  ),
                  child: Text(
                    '播放队列 · ${playback.queue.length} 首',
                    style: Theme.of(sheetContext).textTheme.titleMedium,
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: playback.queue.length,
                    itemBuilder: (BuildContext context, int index) {
                      final Song item = playback.queue[index];
                      return SongTile(
                        song: item,
                        index: index,
                        dense: true,
                        highlight: index == playback.queueIndex,
                        onTap: () {
                          controller.playQueue(
                            playback.queue,
                            startIndex: index,
                          );
                          Navigator.of(sheetContext).pop();
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
