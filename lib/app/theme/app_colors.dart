import 'package:flutter/material.dart';

/// Brand tokens lock-stepped with `docs/DESIGN-SYSTEM.md`.
///
/// Colour psychology (from the brand sheet):
///  Blue  = Trust, Safety, Stability
///  Green = Hope, Health, Growth
///  Orange= Action, Urgency, Energy
///  Navy  = Professionalism, Authority
///  White = Clarity, Simplicity
abstract final class AppColors {
  // Brand
  static const Color primary = Color(0xFF1B6FF1);
  static const Color primaryDark = Color(0xFF0E4FB8);
  static const Color success = Color(0xFF1DB97A);
  static const Color warning = Color(0xFFF5A623);
  static const Color danger = Color(0xFFF03D3D);
  static const Color critical = Color(0xFFB01414);
  static const Color purple = Color(0xFF7C4DFF);

  // Navy scale (splash, sidebar, hero)
  static const Color navyDeep = Color(0xFF0B2239);
  static const Color navy = Color(0xFF0E2A47);
  static const Color navySoft = Color(0xFF13355A);

  // Light surfaces
  static const Color lightBackground = Color(0xFFF4F6FA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceAlt = Color(0xFFEDF1F7);
  static const Color lightBorder = Color(0xFFE3E8F0);
  static const Color lightTextPrimary = Color(0xFF0E2A47);
  static const Color lightTextSecondary = Color(0xFF6B7A90);

  // Dark surfaces
  static const Color darkBackground = Color(0xFF0A1A2B);
  static const Color darkSurface = Color(0xFF102538);
  static const Color darkSurfaceAlt = Color(0xFF16324A);
  static const Color darkBorder = Color(0xFF23445F);
  static const Color darkTextPrimary = Color(0xFFF2F6FA);
  static const Color darkTextSecondary = Color(0xFF9DB0C4);

  // Pre-multiplied alpha tokens — avoids deprecated Color.withOpacity().
  static const Color primarySoft = Color(0x1A1B6FF1);
  static const Color successSoft = Color(0x1A1DB97A);
  static const Color warningSoft = Color(0x1AF5A623);
  static const Color dangerSoft = Color(0x1AF03D3D);
  static const Color criticalSoft = Color(0x1AB01414);
  static const Color purpleSoft = Color(0x1A7C4DFF);
  static const Color navySoftAlpha = Color(0x1A0E2A47);
  static const Color whiteSoft = Color(0x1FFFFFFF);
  static const Color whiteMuted = Color(0x66FFFFFF);
  static const Color shadow = Color(0x14000000);
  static const Color shadowStrong = Color(0x24000000);

  /// Gradient used for the splash screen and the web hero (blue → teal).
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[Color(0xFF1B6FF1), Color(0xFF13B0C6)],
  );

  static const LinearGradient navyGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[AppColors.navy, AppColors.navyDeep],
  );

  /// Severity → colour mapping locked in the design system §2.
  static Color forUrgency(String urgencyKey) {
    switch (urgencyKey) {
      case 'critical':
        return critical;
      case 'high':
        return danger;
      case 'medium':
        return warning;
      case 'low':
      default:
        return success;
    }
  }
}

/// Resolved palette for the active brightness.
@immutable
class AppPalette {
  const AppPalette({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.isDark,
  });

  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final bool isDark;

  static const AppPalette light = AppPalette(
    background: AppColors.lightBackground,
    surface: AppColors.lightSurface,
    surfaceAlt: AppColors.lightSurfaceAlt,
    border: AppColors.lightBorder,
    textPrimary: AppColors.lightTextPrimary,
    textSecondary: AppColors.lightTextSecondary,
    isDark: false,
  );

  static const AppPalette dark = AppPalette(
    background: AppColors.darkBackground,
    surface: AppColors.darkSurface,
    surfaceAlt: AppColors.darkSurfaceAlt,
    border: AppColors.darkBorder,
    textPrimary: AppColors.darkTextPrimary,
    textSecondary: AppColors.darkTextSecondary,
    isDark: true,
  );

  AppPalette copyWith({
    Color? background,
    Color? surface,
    Color? surfaceAlt,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    bool? isDark,
  }) {
    return AppPalette(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      isDark: isDark ?? this.isDark,
    );
  }

  /// The single accessor every widget uses — no `MediaQuery` needed.
  static AppPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  /// Container colour for tinted icon tiles.
  Color tint(Color base) => isDark ? base.withAlpha(0x33) : base.withAlpha(0x1A);
}
