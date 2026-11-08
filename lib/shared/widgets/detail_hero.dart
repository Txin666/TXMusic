import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import 'cover_placeholder.dart';

/// 详情页顶部通用区块：封面 + 类型 + 标题 + 元信息 + 操作按钮。
/// 歌单 / 专辑 / 歌手 / 榜单详情共用，保证骨架期视觉一致。
class DetailHero extends StatelessWidget {
  const DetailHero({
    super.key,
    required this.seed,
    required this.title,
    required this.typeLabel,
    this.meta,
    this.description,
    this.icon = Icons.queue_music_rounded,
    this.primaryLabel = '播放全部',
    this.onPrimaryTap,
    this.secondaryLabel,
    this.onSecondaryTap,
  });

  final String seed;
  final String title;
  final String typeLabel;
  final String? meta;
  final String? description;
  final IconData icon;
  final String primaryLabel;
  final VoidCallback? onPrimaryTap;
  final String? secondaryLabel;
  final VoidCallback? onSecondaryTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        CoverPlaceholder(seed: seed, size: 196, radius: AppRadius.md, icon: icon),
        const SizedBox(width: AppSpacing.xl),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: Text(
                  typeLabel,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.displaySmall,
              ),
              if (meta != null) ...<Widget>[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  meta!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ],
              if (description != null && description!.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  description!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: <Widget>[
                  FilledButton.icon(
                    onPressed: onPrimaryTap,
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: Text(primaryLabel),
                  ),
                  if (secondaryLabel != null) ...<Widget>[
                    const SizedBox(width: AppSpacing.md),
                    OutlinedButton(
                      onPressed: onSecondaryTap,
                      child: Text(secondaryLabel!),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
