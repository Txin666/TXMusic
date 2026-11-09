import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../routing/app_routes.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/widgets/cover_placeholder.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_spacing.dart';
import '../../../player/application/player_controller.dart';
import '../../../player/domain/playback_state.dart';
import '../../../song/data/fake_song_data.dart';
import '../../../song/domain/song.dart';

/// 底部播放控制条：与播放状态双向绑定，点击信息区进入播放详情页。
class MiniPlayerBar extends ConsumerWidget {
  const MiniPlayerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PlaybackSnapshot playback = ref.watch(playerControllerProvider);
    final PlayerController controller = ref.read(playerControllerProvider.notifier);
    final Song? song = playback.currentSong;

    return Container(
      height: AppSpacing.nowPlayingBarHeight,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: song == null ? _buildIdle(context, ref) : _buildActive(context, ref, playback, controller),
    );
  }

  Widget _buildIdle(BuildContext context, WidgetRef ref) {
    return Row(
      children: <Widget>[
        const SizedBox(width: AppSpacing.lg),
        const CoverPlaceholder(seed: 'idle', size: 52, radius: 10),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('暂无播放', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(
                '从发现页或榜单选择一首歌开始',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        TextButton(
          // 骨架期：直接播放推荐假数据队列；接入推荐接口后改为读取每日推荐 Provider。
          onPressed: () => ref
              .read(playerControllerProvider.notifier)
              .playQueue(FakeSongs.slice(0, 6)),
          child: const Text('随便听听'),
        ),
        const SizedBox(width: AppSpacing.lg),
      ],
    );
  }

  Widget _buildActive(
    BuildContext context,
    WidgetRef ref,
    PlaybackSnapshot playback,
    PlayerController controller,
  ) {
    final Song song = playback.currentSong!;

    return Column(
      children: <Widget>[
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
          ),
          child: SizedBox(
            height: 14,
            child: Slider(
              value: playback.position.inMilliseconds.toDouble(),
              max: playback.duration.inMilliseconds <= 0
                  ? 1
                  : playback.duration.inMilliseconds.toDouble(),
              onChanged: (double value) =>
                  controller.seek(Duration(milliseconds: value.round())),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: AppSpacing.lg, right: AppSpacing.lg),
            child: Row(
              children: <Widget>[
                InkWell(
                  onTap: () => context.push(AppRoutes.player),
                  borderRadius: BorderRadius.circular(10),
                  child: Row(
                    children: <Widget>[
                      CoverPlaceholder(seed: song.album, size: 52, radius: 10),
                      const SizedBox(width: AppSpacing.md),
                      SizedBox(
                        width: 190,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              // 播放失败时把原因顶到副标题位置，用户不用翻日志。
                              playback.errorMessage ??
                                  '${song.artist} · '
                                      '${Formatters.duration(playback.duration)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: playback.errorMessage != null
                                        ? AppColors.vip
                                        : AppColors.textSecondary,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                IconButton(
                  tooltip: '收藏（骨架期仅界面反馈）',
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('收藏功能将在接入本地存储后可用'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  icon: const Icon(Icons.favorite_border_rounded, size: 18),
                  color: AppColors.textTertiary,
                ),
                const Spacer(),
                IconButton(
                  tooltip: '上一首',
                  onPressed: controller.skipPrevious,
                  icon: const Icon(Icons.skip_previous_rounded, size: 24),
                  color: AppColors.textPrimary,
                ),
                const SizedBox(width: AppSpacing.xxs),
                _PlayButton(playback: playback, controller: controller),
                const SizedBox(width: AppSpacing.xxs),
                IconButton(
                  tooltip: '下一首',
                  onPressed: controller.skipNext,
                  icon: const Icon(Icons.skip_next_rounded, size: 24),
                  color: AppColors.textPrimary,
                ),
                const SizedBox(width: AppSpacing.sm),
                IconButton(
                  tooltip: playback.repeatMode.label,
                  onPressed: controller.cycleRepeatMode,
                  icon: Icon(_repeatIcon(playback.repeatMode), size: 18),
                  color: playback.repeatMode == RepeatMode.none
                      ? AppColors.textTertiary
                      : AppColors.primary,
                ),
                const Spacer(),
                Text(
                  Formatters.duration(playback.position),
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(width: AppSpacing.sm),
                IconButton(
                  tooltip: playback.muted ? '取消静音' : '静音',
                  onPressed: controller.toggleMute,
                  icon: Icon(
                    playback.muted || playback.volume <= 0
                        ? Icons.volume_off_rounded
                        : Icons.volume_up_rounded,
                    size: 18,
                  ),
                  color: AppColors.textSecondary,
                ),
                SizedBox(
                  width: 84,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
                    ),
                    child: Slider(
                      value: playback.muted ? 0 : playback.volume,
                      onChanged: controller.setVolume,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '播放队列（${playback.queue.length}）',
                  onPressed: () => _showQueue(context, playback, controller),
                  icon: const Icon(Icons.queue_music_rounded, size: 19),
                  color: AppColors.textSecondary,
                ),
                IconButton(
                  tooltip: '播放详情',
                  onPressed: () => context.push(AppRoutes.player),
                  icon: const Icon(Icons.open_in_full_rounded, size: 18),
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  IconData _repeatIcon(RepeatMode mode) {
    switch (mode) {
      case RepeatMode.none:
        return Icons.repeat_rounded;
      case RepeatMode.all:
        return Icons.repeat_rounded;
      case RepeatMode.one:
        return Icons.repeat_one_rounded;
    }
  }

  void _showQueue(
    BuildContext context,
    PlaybackSnapshot playback,
    PlayerController controller,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceAlt,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: Text(
                  '播放队列 · ${playback.queue.length} 首',
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: playback.queue.length,
                  itemBuilder: (BuildContext itemContext, int index) {
                    final Song item = playback.queue[index];
                    final bool active = index == playback.queueIndex;
                    return ListTile(
                      dense: true,
                      leading: Text(
                        '${index + 1}'.padLeft(2, '0'),
                        style: TextStyle(
                          color: active ? AppColors.primary : AppColors.textTertiary,
                          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                      title: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: active ? AppColors.primary : AppColors.textPrimary,
                        ),
                      ),
                      subtitle: Text('${item.artist} · ${item.album}'),
                      trailing: Text(Formatters.duration(item.duration)),
                      onTap: () {
                        controller.playSong(item, queue: playback.queue);
                        Navigator.of(sheetContext).pop();
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        );
      },
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.playback, required this.controller});

  final PlaybackSnapshot playback;
  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 42,
      child: Material(
        color: AppColors.primary,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: controller.togglePlayPause,
          child: playback.isLoading
              ? const Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF04120C),
                  ),
                )
              : Icon(
                  playback.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 24,
                  color: const Color(0xFF04120C),
                ),
        ),
      ),
    );
  }
}

/// 空闲态「随便听听」使用推荐假数据（FakeSongs.slice），无需额外 Provider。
