import 'package:flutter/material.dart';

/// 颜色 token（见开发文档 §3.2 theme/app_colors.dart）。
/// 所有界面禁止硬编码色值，一律引用本文件。
class AppColors {
  const AppColors._();

  // ---- 品牌色 ----
  static const Color primary = Color(0xFF31C48D);
  static const Color primaryDim = Color(0xFF1F8F66);
  static const Color secondary = Color(0xFF7C6BFF);
  static const Color accent = Color(0xFFFFB020);

  // ---- 深色底（默认）----
  static const Color background = Color(0xFF0B0B0F);
  static const Color surface = Color(0xFF14141A);
  static const Color surfaceAlt = Color(0xFF1C1C25);
  static const Color surfaceHigh = Color(0xFF26262F);
  static const Color divider = Color(0xFF2A2A34);

  // ---- 深色文字 ----
  static const Color textPrimary = Color(0xFFF3F3F6);
  static const Color textSecondary = Color(0xFFA0A0AE);
  static const Color textDisabled = Color(0xFF6B6B78);

  // ---- 浅色主题 ----
  // 页面底色略深于白卡片，保证「卡片浮起」的层次；文字层级比深色主题更重，
  // 因为浅底上同样的灰度可读性会显著下降（全部按 WCAG ≥ 4.5:1 取值）。
  static const Color lightBackground = Color(0xFFF2F3F9);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceAlt = Color(0xFFEBEDF4);
  static const Color lightDivider = Color(0xFFD9DCE6);
  static const Color lightTextPrimary = Color(0xFF17171C);
  static const Color lightTextSecondary = Color(0xFF55555F);
  static const Color lightTextDisabled = Color(0xFF6E6E7C);
  /// 浅色主题的强调文字色（深绿，白底对比 5.3:1）。
  static const Color lightEmphasized = Color(0xFF0E7A55);

  // ---- 语义色 ----
  static const Color danger = Color(0xFFE5484D);
  static const Color success = Color(0xFF31C48D);
  static const Color vip = accent;

  // ---- 别名（语义化命名，供组件层引用）----
  static const Color border = divider;
  static const Color textTertiary = textDisabled;

  /// 无封面时按种子字符串生成稳定的渐变（骨架期不依赖网络图片）。
  static List<Color> coverGradient(String seed) {
    const List<List<Color>> palette = <List<Color>>[
      <Color>[Color(0xFF2B5876), Color(0xFF4E4376)],
      <Color>[Color(0xFF31C48D), Color(0xFF1F8F66)],
      <Color>[Color(0xFF7C6BFF), Color(0xFF3B2E8F)],
      <Color>[Color(0xFFFF8A5B), Color(0xFFC0392B)],
      <Color>[Color(0xFF00B4DB), Color(0xFF0083B0)],
      <Color>[Color(0xFFDA22FF), Color(0xFF9733EE)],
    ];
    final int sum = seed.codeUnits.fold<int>(0, (int a, int c) => a + c);
    return palette[sum % palette.length];
  }
}
