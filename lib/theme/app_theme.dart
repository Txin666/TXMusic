import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_palette.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// 主题装配：Material 3 + 深色为主的音乐播放器风格。
/// 见开发文档 §3.2 theme/app_theme.dart。
class AppTheme {
  const AppTheme._();

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData light() => _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;

    final AppPalette palette = isDark ? AppPalette.dark : AppPalette.light;

    final Color bg = palette.background;
    final Color surface = palette.surface;
    final Color surfaceAlt = palette.surfaceAlt;
    final Color surfaceHigh = palette.surfaceHigh;
    final Color divider = palette.divider;
    final Color textPrimary = palette.textPrimary;
    final Color textSecondary = palette.textSecondary;

    final ColorScheme scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: brightness,
        ).copyWith(
          primary: AppColors.primary,
          secondary: AppColors.secondary,
          tertiary: AppColors.accent,
          surface: surface,
          error: AppColors.danger,
          onSurface: textPrimary,
          onPrimary: isDark ? const Color(0xFF04120C) : Colors.white,
          surfaceContainerHighest: surfaceAlt,
        );

    final TextTheme textTheme = AppTypography.textTheme(
      primaryText: textPrimary,
      secondaryText: textSecondary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      extensions: <ThemeExtension<dynamic>>[palette],
      fontFamily: AppTypography.fontFamily,
      fontFamilyFallback: AppTypography.fontFallback,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      dividerTheme: DividerThemeData(color: divider, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: textSecondary, size: 20),
      cardTheme: CardThemeData(
        color: surface,
        // 浅色主题靠一层很淡的投影把白卡片从浅灰页面里拎起来。
        elevation: isDark ? 0 : 1.5,
        shadowColor: Colors.black.withValues(alpha: 0.10),
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.card),
      ),
      // 文字按钮默认取 primary 绿，在浅色背景上对比不足，浅色主题改用深绿强调色。
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: isDark ? AppColors.primary : palette.emphasized,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
        iconTheme: IconThemeData(color: textPrimary),
      ),
      listTileTheme: ListTileThemeData(
        dense: true,
        iconColor: textSecondary,
        textColor: textPrimary,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.cover),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 3,
        activeTrackColor: AppColors.primary,
        inactiveTrackColor: isDark ? surfaceHigh : const Color(0xFFD9DAE3),
        thumbColor: AppColors.primary,
        overlayColor: AppColors.primary.withValues(alpha: 0.16),
        thumbShape: const RoundSliderThumbShape(
          enabledThumbRadius: 6,
          disabledThumbRadius: 4,
        ),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        trackShape: const RoundedRectSliderTrackShape(),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: textPrimary,
        unselectedLabelColor: textSecondary,
        indicatorColor: AppColors.primary,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        labelStyle: textTheme.titleSmall,
        unselectedLabelStyle: textTheme.bodyMedium,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color>((
          Set<WidgetState> states,
        ) {
          if (states.contains(WidgetState.selected)) {
            return const Color(0xFF04120C);
          }
          return isDark ? textSecondary : Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith<Color>((
          Set<WidgetState> states,
        ) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primary;
          }
          return isDark ? surfaceHigh : const Color(0xFFD9DAE3);
        }),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceAlt,
        selectedColor: AppColors.primary.withValues(alpha: 0.18),
        side: BorderSide(color: divider),
        labelStyle: textTheme.bodyMedium,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xxs,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.pill)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceAlt,
        hintStyle: textTheme.bodyMedium?.copyWith(color: textSecondary),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(AppRadius.pill)),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(AppRadius.pill)),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(AppRadius.pill)),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
        ),
      ),
      // 提示条统一走 shared/widgets/app_snack_bar.dart 自绘样式；
      // 这里只保留兜底：万一有遗漏的直接 showSnackBar 调用，也不会是黑白默认块。
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? surfaceHigh : Colors.white,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: textPrimary),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cover,
          side: BorderSide(color: palette.divider),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? surfaceHigh : textPrimary,
          borderRadius: AppRadius.cover,
        ),
        textStyle: textTheme.bodySmall?.copyWith(color: Colors.white),
        waitDuration: const Duration(milliseconds: 400),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.all(6),
        radius: const Radius.circular(3),
        thumbColor: WidgetStateProperty.all(
          isDark
              ? palette.textDisabled.withValues(alpha: 0.35)
              : Colors.black26,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? surfaceAlt : Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.panel),
      ),
    );
  }
}
