import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../routing/app_routes.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../lyric/application/lyric_providers.dart';
import '../../lyric/data/fake_lyric_data.dart';
import '../../lyric/domain/lyric_line.dart';
import '../../player/application/player_controller.dart';
import '../../player/domain/playback_state.dart';

/// 桌面歌词独立窗口占位页（路由 `/desktop-lyric`）。
///
/// 骨架期以页面形式演示布局；TODO(window): 接入 `window_manager` 后由
/// `window_manager.createWindow` + 置顶 / 穿透配置承载真实悬浮窗（文档 §7）。
class DesktopLyricPage extends ConsumerWidget {
  const DesktopLyricPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PlaybackSnapshot playback = ref.watch(playerControllerProvider);
    final PlayerController controller =
        ref.read(playerControllerProvider.notifier);
    final List<LyricLine> lyrics = playback.hasSong
        ? ref.watch(lyricLinesProvider(playback.currentSong!.id))
        : const <LyricLine>[];
    final int currentLine = FakeLyricData.indexAt(lyrics, playback.position);
    final ThemeData theme = Theme.of(context);

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
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: '返回主界面',
                        onPressed: () => context.go(AppRoutes.discover),
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Text(
                            currentLine >= 0 && currentLine < lyrics.length
                                ? lyrics[currentLine].text
                                : '暂无歌词',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.displaySmall?.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                              fontSize: 34,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            playback.hasSong
                                ? '${playback.currentSong!.title} · '
                                    '${playback.currentSong!.artist}'
                                : '未播放',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: AppColors.textSecondary),
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
}
