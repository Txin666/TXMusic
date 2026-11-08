import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import 'cover_placeholder.dart';

/// 通用媒体卡片（歌单 / 专辑 / 榜单）：
/// 骨架期封面为本地渐变，接入接口后把 [CoverPlaceholder] 换成网络图即可。
class MediaCard extends StatefulWidget {
  const MediaCard({
    super.key,
    required this.title,
    required this.seed,
    this.subtitle,
    this.badge,
    this.width = 168,
    this.icon = Icons.queue_music_rounded,
    this.onTap,
    this.showPlayButton = true,
  });

  final String title;
  final String seed;
  final String? subtitle;
  final String? badge;
  final double width;
  final IconData icon;
  final VoidCallback? onTap;
  final bool showPlayButton;

  @override
  State<MediaCard> createState() => _MediaCardState();
}

class _MediaCardState extends State<MediaCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: SizedBox(
          width: widget.width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Stack(
                children: <Widget>[
                  CoverPlaceholder(
                    seed: widget.seed,
                    size: widget.width,
                    radius: AppRadius.sm,
                    icon: widget.icon,
                  ),
                  Positioned(
                    right: AppSpacing.sm,
                    bottom: AppSpacing.sm,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 150),
                      opacity: _hovered && widget.showPlayButton ? 1 : 0,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          size: 22,
                          color: Color(0xFF04120C),
                        ),
                      ),
                    ),
                  ),
                  if (widget.badge != null)
                    Positioned(
                      left: AppSpacing.sm,
                      top: AppSpacing.sm,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                        ),
                        child: Text(
                          widget.badge!,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                widget.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (widget.subtitle != null) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  widget.subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
