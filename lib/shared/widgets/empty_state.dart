import 'package:flutter/material.dart';

import '../../theme/app_spacing.dart';
import '../../theme/app_palette.dart';

/// 空态 / 占位提示（骨架期大量使用，避免出现纯白屏）。
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.description,
    this.icon = Icons.inbox_rounded,
    this.actionLabel,
    this.onActionTap,
    this.compact = false,
  });

  final String title;
  final String? description;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onActionTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: compact ? AppSpacing.xl : AppSpacing.xxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: context.palette.surfaceAlt,
                shape: BoxShape.circle,
                border: Border.all(color: context.palette.divider),
              ),
              child: Icon(icon, size: 28, color: context.palette.textDisabled),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall,
            ),
            if (description != null) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              Text(
                description!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: context.palette.textSecondary),
              ),
            ],
            if (actionLabel != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              FilledButton.tonal(
                onPressed: onActionTap,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
