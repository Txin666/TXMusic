import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:txmusic/theme/app_colors.dart';
import 'package:txmusic/theme/app_palette.dart';
import 'package:txmusic/theme/app_theme.dart';

/// 相对亮度（WCAG 2.1）。
double _luminance(Color color) {
  double channel(double normalized) {
    return normalized <= 0.03928
        ? normalized / 12.92
        : math.pow((normalized + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

/// 对比度（1 ~ 21）。
double _contrast(Color a, Color b) {
  final double la = _luminance(a);
  final double lb = _luminance(b);
  final double lighter = la > lb ? la : lb;
  final double darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('主题语义色 AppPalette', () {
    test('深色与浅色主题都注入了 AppPalette 扩展', () {
      final AppPalette? dark = AppTheme.dark().extension<AppPalette>();
      final AppPalette? light = AppTheme.light().extension<AppPalette>();

      expect(dark, isNotNull);
      expect(light, isNotNull);
      expect(dark!.background, AppColors.background);
      expect(light!.background, AppColors.lightBackground);
      expect(light.surface, AppColors.lightSurface);
      expect(light.textPrimary, AppColors.lightTextPrimary);
    });

    test('两套主题的背景与文字层级确实不同', () {
      final AppPalette dark = AppTheme.dark().extension<AppPalette>()!;
      final AppPalette light = AppTheme.light().extension<AppPalette>()!;

      expect(dark.background, isNot(light.background));
      expect(dark.textPrimary, isNot(light.textPrimary));
    });

    test('浅色主题正文与背景对比度不低于 4.5（可读性）', () {
      final AppPalette light = AppTheme.light().extension<AppPalette>()!;

      expect(_contrast(light.textPrimary, light.background), greaterThan(4.5));
      expect(_contrast(light.textPrimary, light.surface), greaterThan(4.5));
      expect(_contrast(light.textSecondary, light.surface), greaterThan(4.5));
    });

    test('深色主题正文与背景对比度不低于 4.5（保持历史观感）', () {
      final AppPalette dark = AppTheme.dark().extension<AppPalette>()!;

      expect(_contrast(dark.textPrimary, dark.background), greaterThan(4.5));
      expect(_contrast(dark.textSecondary, dark.surface), greaterThan(4.5));
    });

    test('copyWith 与 lerp 不丢字段', () {
      const AppPalette palette = AppPalette.light;
      final AppPalette changed =
          palette.copyWith(textPrimary: const Color(0xFF000000));
      expect(changed.textPrimary, const Color(0xFF000000));
      expect(changed.background, palette.background);

      final AppPalette mid = palette.lerp(AppPalette.dark, 0.5);
      expect(mid.background, isNot(palette.background));
      expect(palette.lerp(null, 0.5).background, palette.background);
    });
  });
}
