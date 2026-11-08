import 'package:flutter/widgets.dart';

/// 窗口宽度断点：窄屏 / 标准 / 宽屏三档（见开发文档 §3.2 core/responsive）。
enum AppWindowSize { compact, standard, wide }

class AppBreakpoints {
  const AppBreakpoints._();

  /// 小于该宽度视为窄屏（侧边栏转图标模式、卡片列数减少）。
  static const double compactMax = 1000;

  /// 大于该宽度视为宽屏。
  static const double wideMin = 1600;

  static AppWindowSize of(BuildContext context) =>
      fromWidth(MediaQuery.sizeOf(context).width);

  static AppWindowSize fromWidth(double width) {
    if (width < compactMax) {
      return AppWindowSize.compact;
    }
    if (width < wideMin) {
      return AppWindowSize.standard;
    }
    return AppWindowSize.wide;
  }

  /// 窄屏下侧边栏默认收起为图标模式。
  static bool navCollapsedByDefault(double width) => width < 1180;

  /// 歌单/专辑卡片每行列数。
  static int gridColumns(double width) {
    switch (fromWidth(width)) {
      case AppWindowSize.compact:
        return 3;
      case AppWindowSize.standard:
        return 4;
      case AppWindowSize.wide:
        return 6;
    }
  }
}
