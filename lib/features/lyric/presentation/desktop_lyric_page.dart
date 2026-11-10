import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/kugou_client.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/widgets/playback_error_banner.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../lyric/application/lyric_providers.dart';
import '../../lyric/domain/lyric_index.dart';
import '../../lyric/domain/lyric_line.dart';
import '../../player/application/player_controller.dart';
import '../../player/domain/playback_state.dart';
import '../../song/domain/song.dart';
import '../../../theme/app_palette.dart';

/// 桌面歌词独立窗口占位页（路由 `/desktop-lyric`）。
///
/// 歌词来自真实 `/search/lyric` + `/krc/get` 链路（[lyricLinesProvider]，
/// family key 为 [lyricKeyOf]，随歌曲切换自动换缓存），高亮行由
/// [LyricIndex.indexAt] 纯函数按播放进度二分定位。
/// 播放失败时在歌词区上方展示 [PlaybackErrorBanner]，可一键重试。
/// TODO(window): 接入 `window_manager` 后由 `window_manager.createWindow`
/// + 置顶 / 穿透配置承载真实悬浮窗（文档 §7）。
class DesktopLyricPage extends ConsumerWidget {
  const DesktopLyricPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PlaybackSnapshot playback = ref.watch(playerControllerProvider);
    final PlayerController controller =
        ref.read(playerControllerProvider.notifier);
    final Song? song = playback.currentSong;

    final AsyncValue<List<LyricLine>> lyricsAsync = song == null
        ? const AsyncData<List<LyricLine>>(<LyricLine>[])
        : ref.watch(lyricLinesProvider(lyricKeyOf(song)));
    final List<LyricLine> lyrics = lyricsAsync.value ?? const <LyricLine>[];
    final int currentLine = LyricIndex.indexAt(lyrics, playback.position);
    final ThemeData theme = Theme.of(context);

    final String lyricText;
    if (song == null) {
      lyricText = '未播放';
    } else if (lyricsAsync.isLoading) {
      lyricText = '歌词加载中…';
    } else if (lyricsAsync.hasError) {
      lyricText = '歌词加载失败';
    } else if (lyrics.isEmpty) {
      lyricText = '暂无歌词';
    } else if (currentLine >= 0 && currentLine < lyrics.length) {
      lyricText = lyrics[currentLine].text;
    } else {
      lyricText = '暂无歌词';
    }

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xxl,
                vertical: AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const Icon(
                        Icons.lyrics_rounded,
                        size: 18,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        '桌面歌词 · 独立窗口占位',
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: context.palette.textSecondary),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: '返回主界面',
                        onPressed: () => context.go(AppRoutes.discover),
                        icon: Icon(
                          Icons.close_rounded,
                          size: 18,
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
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Text(
                            lyricText,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.displaySmall?.copyWith(
                              color: lyricsAsync.hasError
                                  ? AppColors.danger
                                  : AppColors.primary,
                              fontWeight: FontWeight.w700,
                              fontSize: 34,
                            ),
                          ),
                          if (lyricsAsync.hasError) ...<Widget>[
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              _describeError(lyricsAsync.error!),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: context.palette.textSecondary),
                            ),
                          ],
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            song == null
                                ? '未播放'
                                : '${song.title} · ${song.artist}',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: context.palette.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      IconButton(
                        tooltip: '上一首',
                        onPressed: controller.skipPrevious,
                        icon: const Icon(Icons.skip_previous_rounded),
                      ),
                      IconButton(
                        tooltip: playback.isPlaying ? '暂停' : '播放',
                        onPressed: controller.togglePlayPause,
                        icon: Icon(
                          playback.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: AppColors.primary,
                        ),
                      ),
                      IconButton(
                        tooltip: '下一首',
                        onPressed: controller.skipNext,
                        icon: const Icon(Icons.skip_next_rounded),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
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

String _describeError(Object error) =>
    error is KugouApiException ? error.message : '歌词加载失败：$error';
