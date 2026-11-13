import 'package:flutter/material.dart';

import 'app_colors.dart';

/// 语义色扩展（ThemeExtension）：随主题（深色 / 浅色）自动切换。
///
/// 背景、表面、分割线、文字层级等"随明暗变化"的颜色一律走这里，
/// 组件通过 `context.palette` 取值，禁止再直接引用 [AppColors] 的深色常量。
/// 品牌色（primary / secondary / accent / danger）两种主题共用，仍从 [AppColors] 取。
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.surfaceHigh,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.textDisabled,
    required this.emphasized,
    required this.hoverOverlay,
    required this.scrim,
  });

  /// 页面底色。
  final Color background;

  /// 卡片 / 面板表面。
  final Color surface;

  /// 次级表面（输入框、chip、次级卡片）。
  final Color surfaceAlt;

  /// 高分表面（悬浮层、进度条底、头像底）。
  final Color surfaceHigh;

  /// 分割线 / 描边。
  final Color divider;

  /// 主文字。
  final Color textPrimary;

  /// 次要文字。
  final Color textSecondary;

  /// 禁用文字 / 弱提示。
  final Color textDisabled;

  /// 作为「文字 / 图标前景」使用的强调色（品牌绿的深浅修正版）。
  ///
  /// 深色主题直接用品牌绿 [AppColors.primary]（观感不变）；
  /// 浅色主题改用更深的绿，保证白底上文字对比度 ≥ 4.5:1。
  /// 注意：填充类用途（按钮底色、进度条、封面渐变等）仍用 [AppColors.primary]。
  final Color emphasized;

  /// hover / 选中态的遮罩色。
  final Color hoverOverlay;

  /// 阴影 / 遮罩底色。
  final Color scrim;

  /// 深色主题（与历史深色观感保持一致）。
  static const AppPalette dark = AppPalette(
    background: AppColors.background,
    surface: AppColors.surface,
    surfaceAlt: AppColors.surfaceAlt,
    surfaceHigh: AppColors.surfaceHigh,
    divider: AppColors.divider,
    textPrimary: AppColors.textPrimary,
    textSecondary: AppColors.textSecondary,
    textDisabled: AppColors.textDisabled,
    emphasized: AppColors.primary,
    hoverOverlay: Color(0x14FFFFFF),
    scrim: Color(0xB3000000),
  );

  /// 浅色主题：浅底 + 白卡片 + 深色文字，保证对比度。
  static const AppPalette light = AppPalette(
    background: AppColors.lightBackground,
    surface: AppColors.lightSurface,
    surfaceAlt: AppColors.lightSurfaceAlt,
    surfaceHigh: Color(0xFFE2E4EE),
    divider: AppColors.lightDivider,
    textPrimary: AppColors.lightTextPrimary,
    textSecondary: AppColors.lightTextSecondary,
    textDisabled: AppColors.lightTextDisabled,
    emphasized: AppColors.lightEmphasized,
    hoverOverlay: Color(0x14000000),
    scrim: Color(0x33000000),
  );

  @override
  AppPalette copyWith({
    Color? background,
    Color? surface,
    Color? surfaceAlt,
    Color? surfaceHigh,
    Color? divider,
    Color? textPrimary,
    Color? textSecondary,
    Color? textDisabled,
    Color? emphasized,
    Color? hoverOverlay,
    Color? scrim,
  }) {
    return AppPalette(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      surfaceHigh: surfaceHigh ?? this.surfaceHigh,
      divider: divider ?? this.divider,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textDisabled: textDisabled ?? this.textDisabled,
      emphasized: emphasized ?? this.emphasized,
      hoverOverlay: hoverOverlay ?? this.hoverOverlay,
      scrim: scrim ?? this.scrim,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) {
      return this;
    }
    return AppPalette(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      surfaceHigh: Color.lerp(surfaceHigh, other.surfaceHigh, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
      emphasized: Color.lerp(emphasized, other.emphasized, t)!,
      hoverOverlay: Color.lerp(hoverOverlay, other.hoverOverlay, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
    );
  }
}

/// 组件里读语义色的快捷入口：`context.palette.surface`。
extension AppPaletteContext on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.dark;
}
