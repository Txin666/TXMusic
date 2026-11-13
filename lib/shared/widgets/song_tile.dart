import 'package:flutter/material.dart';

import '../../features/song/domain/song.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../theme/app_palette.dart';
import 'cover_image.dart';

/// 通用歌曲行：榜单 / 歌单 / 专辑 / 搜索结果 / 我的音乐共用。
/// 仅负责展示与回调，不直接依赖播放 Provider（保持共享层无业务状态）。
class SongTile extends StatelessWidget {
  const SongTile({
    super.key,
    required this.song,
    this.index,
    this.onTap,
    this.onPlayTap,
    this.trailing,
    this.showCover = true,
    this.showAlbum = true,
    this.highlight = false,
    this.dense = false,
  });

  final Song song;
  final int? index;
  final VoidCallback? onTap;
  final VoidCallback? onPlayTap;
  final Widget? trailing;
  final bool showCover;
  final bool showAlbum;
  final bool highlight;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String subtitle = showAlbum
        ? '${song.artist} · ${song.album}'
        : song.artist;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: dense ? AppSpacing.xs : AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            color: highlight ? context.palette.surfaceHigh : Colors.transparent,
          ),
          child: Row(
            children: <Widget>[
              if (index != null)
                SizedBox(
                  width: 28,
                  child: Text(
                    '${index! + 1}'.padLeft(2, '0'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: index! < 3
                          ? context.palette.emphasized
                          : context.palette.textDisabled,
                      fontWeight: index! < 3
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
              if (showCover) ...<Widget>[
                CoverImage(
                  seed: song.album,
                  url: song.coverUrl,
                  size: dense ? 36 : 44,
                  radius: 8,
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: highlight
                                  ? context.palette.emphasized
                                  : context.palette.textPrimary,
                            ),
                          ),
                        ),
                        if (song.isVip) ...<Widget>[
                          const SizedBox(width: 6),
                          const _VipBadge(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: context.palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (trailing != null)
                trailing!
              else
                Text(
                  Formatters.duration(song.duration),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: context.palette.textDisabled,
                  ),
                ),
              if (onPlayTap != null)
                IconButton(
                  tooltip: '播放',
                  onPressed: onPlayTap,
                  icon: const Icon(Icons.play_circle_outline_rounded, size: 22),
                  color: context.palette.textSecondary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VipBadge extends StatelessWidget {
  const _VipBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.vip.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: AppColors.vip.withValues(alpha: 0.6),
          width: 0.8,
        ),
      ),
      child: const Text(
        'VIP',
        style: TextStyle(
          fontSize: 9,
          color: AppColors.vip,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
