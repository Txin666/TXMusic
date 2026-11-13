import 'package:flutter/material.dart';

import '../../core/responsive/app_breakpoints.dart';
import '../../theme/app_spacing.dart';

/// 页面内容容器：统一最大宽度与内边距，避免宽屏下内容贴边拉得过长。
class PageContainer extends StatelessWidget {
  const PageContainer({
    super.key,
    required this.child,
    this.padding,
    this.scrollable = true,
    this.maxWidth = AppSpacing.maxContentWidth,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final bool scrollable;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width;
    final EdgeInsetsGeometry effectivePadding =
        padding ??
        (AppBreakpoints.fromWidth(width) == AppWindowSize.compact
            ? AppSpacing.pageCompact
            : AppSpacing.page);

    final Widget content = Padding(
      padding: effectivePadding,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    );

    if (!scrollable) {
      return content;
    }

    return Scrollbar(child: SingleChildScrollView(child: content));
  }
}
