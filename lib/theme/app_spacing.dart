import 'package:flutter/widgets.dart';

/// 间距 token（8pt 栅格）。界面禁止写裸数字间距，统一引用本文件。
class AppSpacing {
  const AppSpacing._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double huge = 48;

  /// 页面统一内边距。
  static const EdgeInsets page = EdgeInsets.symmetric(
    horizontal: 32,
    vertical: 24,
  );
  static const EdgeInsets pageCompact = EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 16,
  );
  static const EdgeInsets card = EdgeInsets.all(12);

  // ---- 骨架尺寸 ----
  static const double sideNavWidth = 224;
  static const double sideNavCollapsedWidth = 76;
  static const double topBarHeight = 64;

  /// 自绘标题栏高度（无边框窗口的拖拽区域）。
  static const double titleBarHeight = 36;

  /// 标题栏窗口按钮（最小化 / 最大化 / 关闭）宽度。
  static const double windowButtonWidth = 46;
  static const double nowPlayingBarHeight = 84;
  static const double maxContentWidth = 1400;
}

/// 圆角 token。
class AppRadius {
  const AppRadius._();

  static const double xs = 6;
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double pill = 999;

  static const BorderRadius card = BorderRadius.all(Radius.circular(md));
  static const BorderRadius cover = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius panel = BorderRadius.all(Radius.circular(lg));
}
