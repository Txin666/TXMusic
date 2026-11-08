import 'package:flutter/material.dart';

import 'app_colors.dart';
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

    final Color bg = isDark ? AppColors.background : AppColors.lightBackground;
    final Color surface = isDark ? AppColors.surface : AppColors.lightSurface;
    final Color surfaceAlt = isDark ? AppColors.surfaceAlt : AppColors.lightSurfaceAlt;
    final Color divider = isDark ? AppColors.divider : AppColors.lightDivider;
    final Color textPrimary = isDark ? AppColors.textPrimary : AppColors.lightTextPrimary;
    final Color textSecondary = isDark ? AppColors.textSecondary : AppColors.lightTextSecondary;

    final ColorScheme scheme = ColorScheme.fromSeed(
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
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.card),
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
        inactiveTrackColor: isDark ? AppColors.surfaceHigh : const Color(0xFFD9DAE3),
        thumbColor: AppColors.primary,
        overlayColor: AppColors.primary.withValues(alpha: 0.16),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6, disabledThumbRadius: 4),
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
        thumbColor: WidgetStateProperty.resolveWith<Color>((Set<WidgetState> states) {
          if (states.contains(WidgetState.selected)) {
            return const Color(0xFF04120C);
          }
          return isDark ? AppColors.textSecondary : Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith<Color>((Set<WidgetState> states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primary;
          }
          return isDark ? AppColors.surfaceHigh : const Color(0xFFD9DAE3);
        }),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceAlt,
        selectedColor: AppColors.primary.withValues(alpha: 0.18),
        side: BorderSide(color: divider),
        labelStyle: textTheme.bodyMedium,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(AppRadius.pill))),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? AppColors.surfaceAlt : AppColors.lightSurfaceAlt,
        hintStyle: textTheme.bodyMedium?.copyWith(color: textSecondary),
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
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
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? AppColors.surfaceHigh : AppColors.lightTextPrimary,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.cover),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceHigh : AppColors.lightTextPrimary,
          borderRadius: AppRadius.cover,
        ),
        textStyle: textTheme.bodySmall?.copyWith(color: Colors.white),
        waitDuration: const Duration(milliseconds: 400),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.all(6),
        radius: const Radius.circular(3),
        thumbColor: WidgetStateProperty.all(
          isDark ? AppColors.textDisabled.withValues(alpha: 0.35) : Colors.black26,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.primary),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? AppColors.surfaceAlt : Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.panel),
      ),
    );
  }
}
