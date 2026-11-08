import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/formatters.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/widgets/cover_placeholder.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/song_tile.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../lyric/application/lyric_providers.dart';
import '../../lyric/data/fake_lyric_data.dart';
import '../../lyric/domain/lyric_line.dart';
import '../../player/application/player_controller.dart';
import '../../player/domain/playback_state.dart';
import '../../song/domain/song.dart';

/// 播放详情页（路由 `/player`，脱离 Shell 全屏展示）。
///
/// 骨架期：左侧大封面 + 右侧歌词滚动区 + 底部传输控制；音频为假进度，
/// TODO(audio): 接入 media_kit 后由引擎事件驱动 position / duration。
class PlayerPage extends ConsumerWidget {
  const PlayerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PlaybackSnapshot playback = ref.watch(playerControllerProvider);
    final PlayerController controller =
        ref.read(playerControllerProvider.notifier);
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
    final List<LyricLine> lyrics = ref.watch(lyricLinesProvider(song.id));
    final int currentLine = FakeLyricData.indexAt(lyrics, playback.position);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xFF12161A), AppColors.background],
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
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      Expanded(
                        flex: 4,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            CoverPlaceholder(
                              seed: song.album,
                              size: 320,
                              radius: AppRadius.lg,
                              icon: Icons.album_rounded,
                            ),
                            const SizedBox(height: AppSpacing.xl),
                            Text(
                              song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.headlineMedium,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              '${song.artist} · ${song.album}',
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 5,
                        child: Padding(
                          padding:
                              const EdgeInsets.only(left: AppSpacing.xxl),
                          child: _LyricPane(
                            lyrics: lyrics,
                            currentLine: currentLine,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _TransportBar(playback: playback, controller: controller),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LyricPane extends StatelessWidget {
  const _LyricPane({required this.lyrics, required this.currentLine});

  final List<LyricLine> lyrics;
  final int currentLine;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    if (lyrics.isEmpty) {
      return Center(
        child: Text(
          '暂无歌词',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: AppColors.textSecondary),
        ),
      );
    }

    final int start = (currentLine - 4).clamp(0, lyrics.length - 1);
    final int end = (currentLine + 5).clamp(0, lyrics.length);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (int i = start; i < end; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: (i == currentLine
                      ? theme.textTheme.headlineSmall
                      : theme.textTheme.titleMedium)
                  ?.copyWith(
                color: i == currentLine
                    ? AppColors.primary
                    : AppColors.textSecondary,
                fontWeight:
                    i == currentLine ? FontWeight.w700 : FontWeight.w400,
              ) ?? const TextStyle(),
              child: Text(lyrics[i].text),
            ),
          ),
      ],
    );
  }
}

class _TransportBar extends StatelessWidget {
  const _TransportBar({required this.playback, required this.controller});

  final PlaybackSnapshot playback;
  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
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
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.textTertiary),
              ),
              const Spacer(),
              Text(
                Formatters.duration(playback.duration),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.textTertiary),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            IconButton(
              tooltip: playback.repeatMode.label,
              onPressed: controller.cycleRepeatMode,
              icon: Icon(
                playback.repeatMode == RepeatMode.one
                    ? Icons.repeat_one_rounded
                    : Icons.repeat_rounded,
                color: playback.repeatMode == RepeatMode.none
                    ? AppColors.textSecondary
                    : AppColors.primary,
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

  void _showQueue(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceAlt,
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
                          controller.playQueue(playback.queue,
                              startIndex: index);
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
