import 'package:flutter/material.dart';

import 'app_strings.dart';

/// Localizations facade over [AppStrings].
///
/// ```dart
/// Text(context.tr('dash.reportEmergency'))
/// ```
class AppLocalizations {
  const AppLocalizations(this.locale);

  final Locale locale;

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        const AppLocalizations(Locale(AppStrings.fallbackLanguage));
  }

  String t(String key) => AppStrings.lookup(locale.languageCode, key);

  /// Human readable name of the active language, for the settings screen.
  String get languageName {
    const Map<String, String> names = <String, String>{
      'en': 'English',
      'hi': 'हिन्दी (Hindi)',
      'te': 'తెలుగు (Telugu)',
      'ta': 'தமிழ் (Tamil)',
      'es': 'Español (Spanish)',
    };
    return names[locale.languageCode] ?? 'English';
  }

  /// RTL-ready (NFR i18n): Arabic/Urdu can be added without structural change.
  TextDirection get textDirection =>
      const <String>{'ar', 'ur', 'he', 'fa'}.contains(locale.languageCode)
          ? TextDirection.rtl
          : TextDirection.ltr;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      AppStrings.supports(locale.languageCode) ||
      locale.languageCode == AppStrings.fallbackLanguage;

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

/// Ergonomic access: `context.tr('nav.home')`.
extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);

  String tr(String key) => AppLocalizations.of(this).t(key);
}
