import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_text_styles.dart';

/// Material 3 themes built only from long-stable ThemeData fields
/// (colour scheme, scaffold background, divider, text theme). Component
/// styling lives in `core/widgets/app_widgets.dart` so the app stays
/// resilient across Flutter's theme-object renames.
abstract final class AppTheme {
  /// High-contrast mode darkens borders and body text without changing the
  /// brand palette — the accessible variant of the same design system.
  static ThemeData light({bool highContrast = false}) {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.primary,
      secondary: AppColors.success,
      tertiary: AppColors.purple,
      error: AppColors.danger,
      surface: AppColors.lightSurface,
    );

    final AppPalette palette = highContrast
        ? AppPalette.light.copyWith(
            border: const Color(0xFF9AA9BC),
            textSecondary: const Color(0xFF44536A),
          )
        : AppPalette.light;

    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.background,
      dividerColor: palette.border,
      textTheme: AppText.materialTextTheme(palette),
      splashFactory: InkRipple.splashFactory,
      visualDensity: VisualDensity.standard,
    );
  }

  static ThemeData dark({bool highContrast = false}) {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
    ).copyWith(
      primary: AppColors.primary,
      secondary: AppColors.success,
      tertiary: AppColors.purple,
      error: AppColors.danger,
      surface: AppColors.darkSurface,
    );

    final AppPalette palette = highContrast
        ? AppPalette.dark.copyWith(
            border: const Color(0xFF5C7C99),
            textSecondary: const Color(0xFFD3E0EC),
          )
        : AppPalette.dark;

    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.background,
      dividerColor: palette.border,
      textTheme: AppText.materialTextTheme(palette),
      splashFactory: InkRipple.splashFactory,
      visualDensity: VisualDensity.standard,
    );
  }
}

/// Spacing + radius scale (design system §3: 14–16 px cards, pill buttons).
abstract final class AppSizes {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 28;

  /// Accessibility: minimum interactive target (WCAG 2.1 AA / NFR).
  static const double minTapTarget = 48;

  static const double radiusSm = 10;
  static const double radiusMd = 14;
  static const double radiusLg = 18;
  static const double radiusPill = 999;

  static const EdgeInsets screenPadding = EdgeInsets.fromLTRB(lg, md, lg, xxl);
}

/// Elevation/opacity presets expressed as pre-built decorations.
abstract final class AppDecorations {
  static BoxDecoration card(AppPalette palette, {double radius = AppSizes.radiusMd}) {
    return BoxDecoration(
      color: palette.surface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: palette.border),
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: palette.isDark ? AppColors.shadowStrong : AppColors.shadow,
          blurRadius: 14,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }

  static BoxDecoration flat(AppPalette palette, {double radius = AppSizes.radiusMd}) {
    return BoxDecoration(
      color: palette.surface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: palette.border),
    );
  }

  static BoxDecoration tile(Color tint, {double radius = AppSizes.radiusMd}) {
    return BoxDecoration(
      color: tint,
      borderRadius: BorderRadius.circular(radius),
    );
  }
}
