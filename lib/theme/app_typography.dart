import 'package:flutter/material.dart';

/// 字体与文字层级 token（见开发文档 §3.2 theme/app_typography.dart）。
/// Windows 中文优先使用 Microsoft YaHei UI，缺失时回退 Segoe UI / Roboto。
class AppTypography {
  const AppTypography._();

  static const String fontFamily = 'Microsoft YaHei UI';
  static const List<String> fontFallback = <String>[
    'Segoe UI',
    'Roboto',
    'Noto Sans SC',
    'sans-serif',
  ];

  static TextTheme textTheme({
    required Color primaryText,
    required Color secondaryText,
  }) {
    TextStyle style({
      required double size,
      FontWeight weight = FontWeight.w400,
      Color? color,
      double? height,
      double spacing = 0.1,
    }) {
      return TextStyle(
        fontFamily: fontFamily,
        fontFamilyFallback: fontFallback,
        fontSize: size,
        fontWeight: weight,
        color: color ?? primaryText,
        height: height ?? 1.35,
        letterSpacing: spacing,
      );
    }

    return TextTheme(
      displaySmall: style(size: 32, weight: FontWeight.w700, height: 1.2),
      headlineMedium: style(size: 24, weight: FontWeight.w700, height: 1.25),
      headlineSmall: style(size: 20, weight: FontWeight.w600),
      titleLarge: style(size: 18, weight: FontWeight.w600),
      titleMedium: style(size: 15, weight: FontWeight.w600),
      titleSmall: style(size: 13, weight: FontWeight.w600),
      bodyLarge: style(size: 15),
      bodyMedium: style(size: 13),
      bodySmall: style(size: 12, color: secondaryText),
      labelLarge: style(size: 13, weight: FontWeight.w600),
      labelMedium: style(size: 12, color: secondaryText),
      labelSmall: style(size: 11, color: secondaryText),
    );
  }
}
