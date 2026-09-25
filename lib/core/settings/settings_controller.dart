import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_enums.dart';
import '../di/providers.dart';
import '../storage/local_store.dart';

/// User-controlled app preferences, persisted locally so they survive restarts
/// and remain available offline.
@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.languageCode = 'en',
    this.role = UserRole.victim,
    this.observeLargeText = false,
    this.highContrast = false,
    this.reduceMotion = false,
    this.offlineModeEnabled = false,
  });

  final ThemeMode themeMode;
  final String languageCode;
  final UserRole role;

  /// Accessibility (NFR): larger text, high contrast, reduce motion.
  final bool observeLargeText;
  final bool highContrast;
  final bool reduceMotion;

  /// "Airplane mode" for demos — forces repositories down the offline path.
  final bool offlineModeEnabled;

  Locale get locale => Locale(languageCode);

  AppSettings copyWith({
    ThemeMode? themeMode,
    String? languageCode,
    UserRole? role,
    bool? observeLargeText,
    bool? highContrast,
    bool? reduceMotion,
    bool? offlineModeEnabled,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      languageCode: languageCode ?? this.languageCode,
      role: role ?? this.role,
      observeLargeText: observeLargeText ?? this.observeLargeText,
      highContrast: highContrast ?? this.highContrast,
      reduceMotion: reduceMotion ?? this.reduceMotion,
      offlineModeEnabled: offlineModeEnabled ?? this.offlineModeEnabled,
    );
  }
}

class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    final LocalStore store = ref.watch(localStoreProvider);
    return AppSettings(
      themeMode: _themeModeFromKey(store.getString(LocalStore.keyThemeMode)),
      languageCode: store.getString(LocalStore.keyLanguage) ?? 'en',
      role: _roleFromKey(store.getString(LocalStore.keyRole)),
      observeLargeText: store.getBool(LocalStore.keyLargeText),
      highContrast: store.getBool(LocalStore.keyHighContrast),
      reduceMotion: store.getBool(LocalStore.keyReduceMotion),
      offlineModeEnabled: store.getBool(LocalStore.keyOfflinePreference),
    );
  }

  LocalStore get _store => ref.read(localStoreProvider);

  Future<void> setThemeMode(ThemeMode mode) async {
    await _store.setString(LocalStore.keyThemeMode, mode.name);
    state = state.copyWith(themeMode: mode);
  }

  Future<void> setLanguage(String languageCode) async {
    await _store.setString(LocalStore.keyLanguage, languageCode);
    state = state.copyWith(languageCode: languageCode);
  }

  Future<void> setRole(UserRole role) async {
    await _store.setString(LocalStore.keyRole, role.name);
    state = state.copyWith(role: role);
  }

  Future<void> setLargeText(bool value) async {
    await _store.setBool(LocalStore.keyLargeText, value);
    state = state.copyWith(observeLargeText: value);
  }

  Future<void> setHighContrast(bool value) async {
    await _store.setBool(LocalStore.keyHighContrast, value);
    state = state.copyWith(highContrast: value);
  }

  Future<void> setReduceMotion(bool value) async {
    await _store.setBool(LocalStore.keyReduceMotion, value);
    state = state.copyWith(reduceMotion: value);
  }

  Future<void> setOfflineMode(bool value) async {
    await _store.setBool(LocalStore.keyOfflinePreference, value);
    state = state.copyWith(offlineModeEnabled: value);
  }

  static ThemeMode _themeModeFromKey(String? key) => switch (key) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  static UserRole _roleFromKey(String? key) {
    for (final UserRole role in UserRole.values) {
      if (role.name == key) return role;
    }
    return UserRole.victim;
  }
}

final NotifierProvider<SettingsController, AppSettings> appSettingsProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

final Provider<ThemeMode> themeModeProvider =
    Provider<ThemeMode>((Ref ref) => ref.watch(appSettingsProvider).themeMode);

final Provider<Locale> localeProvider =
    Provider<Locale>((Ref ref) => ref.watch(appSettingsProvider).locale);

final Provider<UserRole> activeRoleProvider =
    Provider<UserRole>((Ref ref) => ref.watch(appSettingsProvider).role);

final Provider<bool> reduceMotionProvider =
    Provider<bool>((Ref ref) => ref.watch(appSettingsProvider).reduceMotion);

final Provider<bool> highContrastProvider =
    Provider<bool>((Ref ref) => ref.watch(appSettingsProvider).highContrast);
