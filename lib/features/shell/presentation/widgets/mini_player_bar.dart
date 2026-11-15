import 'dart:math';

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/kugou_client.dart';
import '../../../../routing/app_routes.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/widgets/cover_image.dart';
import '../../../../shared/widgets/app_snack_bar.dart';
import '../../../../shared/widgets/cover_placeholder.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_spacing.dart';
import '../../../discover/application/discover_providers.dart';
import '../../../library/application/library_providers.dart';
import '../../../player/application/player_controller.dart';
import '../../../player/domain/playback_state.dart';
import '../../../song/domain/song.dart';
import '../../../../theme/app_palette.dart';

/// 底部播放控制条：与播放状态双向绑定，点击信息区进入播放详情页。
class MiniPlayerBar extends ConsumerWidget {
  const MiniPlayerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PlaybackSnapshot playback = ref.watch(playerControllerProvider);
    final PlayerController controller = ref.read(
      playerControllerProvider.notifier,
    );
    final Song? song = playback.currentSong;

    // 切歌时写入真实「最近播放」（`.local/recent.json`），失败曲目不计入。
    ref.listen<PlaybackSnapshot>(playerControllerProvider, (
      PlaybackSnapshot? previous,
      PlaybackSnapshot next,
    ) {
      final Song? current = next.currentSong;
      if (current == null || next.errorMessage != null) {
        return;
      }
      if (current.hash == previous?.currentSong?.hash) {
        return;
      }
      ref.read(libraryProvider.notifier).recordPlayed(current);
    });

    return Container(
      height: AppSpacing.nowPlayingBarHeight,
      decoration: BoxDecoration(
        color: context.palette.surface,
        border: Border(top: BorderSide(color: context.palette.divider)),
        // 浅色主题下白底播放条会和浅灰页面糊成一片，靠一道向上的投影分层。
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: song == null
          ? _buildIdle(context, ref)
          : _buildActive(context, ref, playback, controller),
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
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: context.palette.textSecondary),
              ),
            ],
          ),
        ),
        const _ShuffleButton(),
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
            padding: const EdgeInsets.only(
              left: AppSpacing.lg,
              right: AppSpacing.lg,
            ),
            child: Row(
              children: <Widget>[
                InkWell(
                  onTap: () => context.push(AppRoutes.player),
                  borderRadius: BorderRadius.circular(10),
                  child: Row(
                    children: <Widget>[
                      CoverImage(
                        seed: song.album,
                        url: song.coverUrl,
                        size: 52,
                        radius: 10,
                      ),
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
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: playback.errorMessage != null
                                        ? AppColors.danger
                                        : context.palette.textSecondary,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Builder(
                  builder: (BuildContext buttonContext) {
                    // 收藏态读统一入口：登录时以服务器「我喜欢」为准。
                    final bool liked = ref.watch(isFavoriteProvider)(song.hash);
                    return IconButton(
                      tooltip: liked ? '取消收藏' : '收藏',
                      onPressed: () async {
                        String message = liked ? '已取消收藏' : '已加入我喜欢的音乐';
                        try {
                          await ref
                              .read(libraryProvider.notifier)
                              .toggleFavorite(song);
                        } on KugouApiException catch (error) {
                          message = '收藏失败：${error.message}';
                        } on Object catch (error) {
                          message = '收藏失败：$error';
                        }
                        if (!buttonContext.mounted) {
                          return;
                        }
                        showAppSnackBar(buttonContext, message);
                      },
                      icon: Icon(
                        liked
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        size: 18,
                      ),
                      color: liked
                          ? context.palette.emphasized
                          : context.palette.textSecondary,
                    );
                  },
                ),
                const Spacer(),
                IconButton(
                  tooltip: '上一首',
                  onPressed: controller.skipPrevious,
                  icon: const Icon(Icons.skip_previous_rounded, size: 24),
                  color: context.palette.textPrimary,
                ),
                const SizedBox(width: AppSpacing.xxs),
                _PlayButton(playback: playback, controller: controller),
                const SizedBox(width: AppSpacing.xxs),
                IconButton(
                  tooltip: '下一首',
                  onPressed: controller.skipNext,
                  icon: const Icon(Icons.skip_next_rounded, size: 24),
                  color: context.palette.textPrimary,
                ),
                const SizedBox(width: AppSpacing.sm),
                IconButton(
                  tooltip: playback.repeatMode.label,
                  onPressed: controller.cycleRepeatMode,
                  icon: Icon(_repeatIcon(playback.repeatMode), size: 18),
                  color: playback.repeatMode == RepeatMode.none
                      ? context.palette.textSecondary
                      : context.palette.emphasized,
                ),
                const Spacer(),
                Text(
                  Formatters.duration(playback.position),
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: context.palette.textSecondary),
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
                  color: context.palette.textSecondary,
                ),
                SizedBox(
                  width: 84,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 4,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 8,
                      ),
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
                  color: context.palette.textSecondary,
                ),
                IconButton(
                  tooltip: '播放详情',
                  onPressed: () => context.push(AppRoutes.player),
                  icon: const Icon(Icons.open_in_full_rounded, size: 18),
                  color: context.palette.textSecondary,
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
      backgroundColor: context.palette.surfaceAlt,
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
                          color: active
                              ? context.palette.emphasized
                              : context.palette.textSecondary,
                          fontWeight: active
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      title: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: active
                              ? context.palette.emphasized
                              : context.palette.textPrimary,
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
                  playback.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  size: 24,
                  color: const Color(0xFF04120C),
                ),
        ),
      ),
    );
  }
}

/// 空闲态「随便听听」：取真实每日推荐（`/everyday/recommend`）随机起播，
/// 拉取失败或为空时提示用户，绝不回退到假数据。
class _ShuffleButton extends ConsumerStatefulWidget {
  const _ShuffleButton();

  @override
  ConsumerState<_ShuffleButton> createState() => _ShuffleButtonState();
}

class _ShuffleButtonState extends ConsumerState<_ShuffleButton> {
  bool _busy = false;

  Future<void> _shuffle() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      final DiscoverFeed feed = await ref.read(discoverFeedProvider.future);
      final List<Song> pool = List<Song>.of(feed.dailySongs);
      if (pool.isEmpty) {
        _toast('暂时拿不到每日推荐，请确认本地接口服务是否运行');
        return;
      }
      pool.shuffle(Random());
      await ref.read(playerControllerProvider.notifier).playQueue(pool);
    } on Object catch (error) {
      _toast(
        error is KugouApiException
            ? '获取每日推荐失败：${error.message}'
            : '获取每日推荐失败：$error',
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _toast(String message) {
    if (!mounted) {
      return;
    }
    showAppSnackBar(context, message);
  }

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: _busy ? null : _shuffle,
      icon: _busy
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.shuffle_rounded, size: 16),
      label: Text(_busy ? '准备中' : '随便听听'),
    );
  }
}
