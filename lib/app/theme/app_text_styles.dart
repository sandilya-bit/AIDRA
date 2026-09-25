import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Typography scale — geometric sans, bold headers, regular body
/// (design system §3). Sizes use `sp`-like fixed values and inherit the
/// platform text scale factor, so system accessibility settings apply.
abstract final class AppText {
  static const String? fontFamily = null; // platform default (Inter/Poppins can be dropped in here)

  static const TextStyle display = TextStyle(
    fontSize: 32,
    height: 1.15,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
  );

  static const TextStyle headline = TextStyle(
    fontSize: 24,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
  );

  static const TextStyle title = TextStyle(
    fontSize: 18,
    height: 1.25,
    fontWeight: FontWeight.w700,
  );

  static const TextStyle subtitle = TextStyle(
    fontSize: 15,
    height: 1.3,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle body = TextStyle(
    fontSize: 14,
    height: 1.45,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle bodyStrong = TextStyle(
    fontSize: 14,
    height: 1.4,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12,
    height: 1.35,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle label = TextStyle(
    fontSize: 11,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.6,
  );

  static const TextStyle stat = TextStyle(
    fontSize: 26,
    height: 1.1,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.4,
  );

  /// Material theme wiring. Kept to the long-stable named slots so the app
  /// compiles across Flutter 3.x releases.
  static TextTheme materialTextTheme(AppPalette palette) {
    return TextTheme(
      displayLarge: display.copyWith(color: palette.textPrimary),
      displayMedium: display.copyWith(color: palette.textPrimary),
      headlineMedium: headline.copyWith(color: palette.textPrimary),
      headlineSmall: headline.copyWith(fontSize: 20, color: palette.textPrimary),
      titleLarge: title.copyWith(color: palette.textPrimary),
      titleMedium: subtitle.copyWith(color: palette.textPrimary),
      bodyLarge: body.copyWith(fontSize: 15, color: palette.textPrimary),
      bodyMedium: body.copyWith(color: palette.textPrimary),
      bodySmall: caption.copyWith(color: palette.textSecondary),
      labelLarge: bodyStrong.copyWith(color: palette.textPrimary),
      labelMedium: caption.copyWith(color: palette.textSecondary),
      labelSmall: label.copyWith(color: palette.textSecondary),
    );
  }

  /// Convenience for the navy surfaces (splash, hero, deep headers).
  static TextTheme onNavyTextTheme() {
    return TextTheme(
      displayLarge: display.copyWith(color: Colors.white),
      headlineMedium: headline.copyWith(color: Colors.white),
      headlineSmall: headline.copyWith(fontSize: 20, color: Colors.white),
      titleLarge: title.copyWith(color: Colors.white),
      titleMedium: subtitle.copyWith(color: Colors.white),
      bodyLarge: body.copyWith(fontSize: 15, color: AppColors.whiteMuted),
      bodyMedium: body.copyWith(color: AppColors.whiteMuted),
      bodySmall: caption.copyWith(color: AppColors.whiteMuted),
      labelLarge: bodyStrong.copyWith(color: Colors.white),
      labelMedium: caption.copyWith(color: AppColors.whiteMuted),
      labelSmall: label.copyWith(color: AppColors.whiteMuted),
    );
  }
}
