import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/desktop/desktop_host.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_spacing.dart';

/// 无边框窗口的自绘标题栏。
///
/// - 空白区域可拖动窗口（[DesktopHost.startDragging]），双击切换最大化；
/// - 右侧提供最小化 / 最大化还原 / 关闭三个按钮，关闭按钮走「收进托盘」；
/// - 颜色全部取自 `context.palette`，深色与浅色主题同时适配。
class WindowTitleBar extends StatelessWidget {
  const WindowTitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // 无边框窗口没有系统拖拽区，按住空白处交给原生处理。
      onPanStart: (_) => unawaited(DesktopHost.instance.startDragging()),
      onDoubleTap: () => unawaited(DesktopHost.instance.toggleMaximize()),
      child: MouseRegion(
        cursor: SystemMouseCursors.basic,
        child: Container(
          height: AppSpacing.titleBarHeight,
          decoration: BoxDecoration(
            // 用 surface 而非 background：浅色主题下页面底色比纯白深一档，
            // 标题栏取白色才能和内容区拉开层次，否则整条顶部会糊成一片。
            color: palette.surface,
            border: Border(bottom: BorderSide(color: palette.divider)),
          ),
          child: Row(
            children: <Widget>[
              const SizedBox(width: AppSpacing.md),
              const _BrandMark(),
              const Spacer(),
              _CaptionButton(
                tooltip: '最小化',
                icon: Icons.remove,
                onPressed: DesktopHost.instance.minimize,
              ),
              const _MaximizeButton(),
              _CaptionButton(
                tooltip: '关闭',
                icon: Icons.close,
                hoverColor: AppColors.danger,
                onPressed: DesktopHost.instance.hideToTray,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Icon(Icons.graphic_eq, size: 16, color: AppColors.primary),
        const SizedBox(width: AppSpacing.sm),
        Text(
          'TX Music',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
            color: palette.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// 最大化 / 还原按钮：图标随窗口最大化状态切换。
class _MaximizeButton extends StatelessWidget {
  const _MaximizeButton();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: DesktopHost.instance.isMaximized,
      builder: (BuildContext context, bool maximized, _) {
        return _CaptionButton(
          tooltip: maximized ? '还原' : '最大化',
          icon: maximized ? Icons.filter_none : Icons.crop_square,
          onPressed: DesktopHost.instance.toggleMaximize,
        );
      },
    );
  }
}

/// 单个窗口按钮：带 hover 底色过渡，浅色主题下自动取浅色 hover 遮罩。
class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.hoverColor,
  });

  final String tooltip;
  final IconData icon;
  final Future<void> Function() onPressed;

  /// 自定义 hover / 前景色（关闭按钮使用危险色）。
  final Color? hoverColor;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final Color accent = widget.hoverColor ?? palette.hoverOverlay;

    return Semantics(
      button: true,
      label: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: () => unawaited(widget.onPressed()),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: AppSpacing.windowButtonWidth,
            height: AppSpacing.titleBarHeight,
            color: _hovered ? accent : Colors.transparent,
            child: Icon(
              widget.icon,
              size: 15,
              color: _hovered
                  ? (widget.hoverColor != null ? Colors.white : palette.textPrimary)
                  : palette.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
