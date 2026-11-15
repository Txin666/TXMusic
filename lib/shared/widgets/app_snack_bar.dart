import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_spacing.dart';

/// 提示条语义类型：决定左侧图标与强调色。
enum AppSnackKind {
  /// 中性信息（默认）：例如「已清空最近播放记录」。
  info,

  /// 操作成功：例如登录成功、已收藏。
  success,

  /// 需要注意但不致命：例如功能待接入、缺少字段。
  warning,

  /// 失败：例如收藏失败、网络异常。
  error,
}

/// 全应用统一提示条入口。
///
/// 业务代码禁止再直接写 `ScaffoldMessenger.of(context).showSnackBar(SnackBar(...))`，
/// 一律走这里：底色、圆角、描边、阴影、宽度、图标语义与停留时长在此统一收口，
/// 深色 / 浅色主题各自取语义色，不再逐处手写。
void showAppSnackBar(
  BuildContext context,
  String message, {
  AppSnackKind kind = AppSnackKind.info,
  Duration? duration,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  showAppSnackBarWith(
    ScaffoldMessenger.of(context),
    message,
    kind: kind,
    duration: duration,
    actionLabel: actionLabel,
    onAction: onAction,
  );
}

/// 与 [showAppSnackBar] 同款样式，但直接接收 [ScaffoldMessengerState]。
///
/// 用于拿不到页面 context 的场景（如托盘收起的提示走 `DesktopHost.messengerKey`）。
void showAppSnackBarWith(
  ScaffoldMessengerState messenger,
  String message, {
  AppSnackKind kind = AppSnackKind.info,
  Duration? duration,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  if (message.trim().isEmpty) {
    return;
  }
  messenger
    // 连点时只保留最新一条，避免排队堆叠挡住播放条。
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: duration ?? kind.defaultDuration,
        behavior: SnackBarBehavior.floating,
        // 底色、描边、阴影全部由 content 自绘，SnackBar 本体只负责定位。
        backgroundColor: Colors.transparent,
        elevation: 0,
        padding: EdgeInsets.zero,
        // 底部让出迷你播放条（nowPlayingBarHeight）的高度，提示不压歌名。
        margin: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.nowPlayingBarHeight + AppSpacing.md,
        ),
        content: _AppSnackBody(
          message: message,
          kind: kind,
          actionLabel: actionLabel,
          onAction: onAction,
          onClose: messenger.hideCurrentSnackBar,
        ),
      ),
    );
}

extension AppSnackKindStyle on AppSnackKind {
  /// 强调色：成功用品牌绿，警告用琥珀，失败用危险红，信息用弱化文字色。
  Color accentOf(AppPalette palette) {
    switch (this) {
      case AppSnackKind.success:
        return AppColors.success;
      case AppSnackKind.warning:
        return AppColors.accent;
      case AppSnackKind.error:
        return AppColors.danger;
      case AppSnackKind.info:
        return palette.emphasized;
    }
  }

  IconData get icon {
    switch (this) {
      case AppSnackKind.success:
        return Icons.check_rounded;
      case AppSnackKind.warning:
        return Icons.error_outline_rounded;
      case AppSnackKind.error:
        return Icons.priority_high_rounded;
      case AppSnackKind.info:
        return Icons.info_outline_rounded;
    }
  }

  /// 停留时长：失败信息给更长时间读完，其余按一眼扫过即可。
  Duration get defaultDuration {
    switch (this) {
      case AppSnackKind.error:
        return const Duration(seconds: 4);
      case AppSnackKind.warning:
        return const Duration(seconds: 3);
      case AppSnackKind.info:
      case AppSnackKind.success:
        return const Duration(milliseconds: 2200);
    }
  }
}

/// 提示条视觉本体：左侧色点图标 + 文案，右侧可选操作与关闭。
class _AppSnackBody extends StatelessWidget {
  const _AppSnackBody({
    required this.message,
    required this.kind,
    required this.onClose,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final AppSnackKind kind;
  final VoidCallback onClose;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color accent = kind.accentOf(palette);

    return Center(
      child: ConstrainedBox(
        // 桌面窗口很宽，提示条不跟着拉满，限宽后靠底居中更像系统 Toast。
        constraints: const BoxConstraints(maxWidth: 420),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isDark ? palette.surfaceHigh : palette.surface,
            borderRadius: AppRadius.cover,
            border: Border.all(color: palette.divider),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: palette.scrim,
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.xs,
              AppSpacing.sm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(kind.icon, size: 15, color: accent),
                ),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    message,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(
                      color: palette.textPrimary,
                      height: 1.35,
                    ),
                  ),
                ),
                if (actionLabel != null && onAction != null) ...<Widget>[
                  const SizedBox(width: AppSpacing.sm),
                  TextButton(
                    onPressed: () {
                      onClose();
                      onAction!();
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: palette.emphasized,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                      ),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(actionLabel!),
                  ),
                ],
                IconButton(
                  tooltip: '关闭提示',
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded, size: 15),
                  color: palette.textDisabled,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  splashRadius: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
