import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

/// 播放失败提示条：音源解析失败 / 播放出错时在播放条与全屏播放页统一展示。
///
/// 只做展示与重试回调，不依赖任何播放 Provider，保持 shared 层无业务状态。
class PlaybackErrorBanner extends StatelessWidget {
  const PlaybackErrorBanner({
    super.key,
    required this.message,
    this.onRetry,
    this.compact = false,
  });

  final String message;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: compact ? AppSpacing.xs : AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.error_outline_rounded,
            size: 16,
            color: AppColors.danger,
          ),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              message,
              maxLines: compact ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.danger),
            ),
          ),
          if (onRetry != null) ...<Widget>[
            const SizedBox(width: AppSpacing.sm),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.danger,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                ),
                minimumSize: const Size(0, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('重试'),
            ),
          ],
        ],
      ),
    );
  }
}
