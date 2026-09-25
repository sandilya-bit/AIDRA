import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Synchronous local persistence (SharedPreferences).
///
/// Initialised once in `main()` and injected through `localStoreProvider`,
/// which keeps every other layer free of plugin singletons and makes
/// repositories trivially testable.
class LocalStore {
  LocalStore(this._prefs);

  final SharedPreferences _prefs;

  static const String keyThemeMode = 'settings.theme_mode';
  static const String keyLanguage = 'settings.language';
  static const String keyRole = 'settings.role';
  static const String keyOnboarded = 'settings.onboarded';
  static const String keyLargeText = 'a11y.large_text';
  static const String keyHighContrast = 'a11y.high_contrast';
  static const String keyReduceMotion = 'a11y.reduce_motion';
  static const String keyOfflinePreference = 'network.offline_preference';
  static const String keySession = 'auth.session';
  static const String keyCachedReports = 'cache.reports';
  static const String keyCachedIncidents = 'cache.incidents';
  static const String keyCachedNotifications = 'cache.notifications';
  static const String keyOutbox = 'queue.outbox';
  static const String keyLastSync = 'sync.last_at';

  static Future<LocalStore> init() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return LocalStore(prefs);
  }

  // ---------------------------------------------------------------- primitives

  String? getString(String key) => _prefs.getString(key);

  bool getBool(String key, {bool fallback = false}) =>
      _prefs.getBool(key) ?? fallback;

  int getInt(String key, {int fallback = 0}) => _prefs.getInt(key) ?? fallback;

  Future<void> setString(String key, String value) =>
      _prefs.setString(key, value);

  Future<void> setBool(String key, bool value) => _prefs.setBool(key, value);

  Future<void> setInt(String key, int value) => _prefs.setInt(key, value);

  Future<void> remove(String key) => _prefs.remove(key);

  // ------------------------------------------------------------------ json

  Map<String, dynamic>? getJson(String key) {
    final String? raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final dynamic decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> setJson(String key, Map<String, dynamic> value) =>
      _prefs.setString(key, jsonEncode(value));

  List<Map<String, dynamic>> getJsonList(String key) {
    final String? raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map<dynamic, dynamic>>()
            .map((Map<dynamic, dynamic> e) => e.cast<String, dynamic>())
            .toList(growable: false);
      }
      return <Map<String, dynamic>>[];
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> setJsonList(String key, List<Map<String, dynamic>> value) =>
      _prefs.setString(key, jsonEncode(value));

  Future<void> appendJsonItem(
    String key,
    Map<String, dynamic> item, {
    int maxItems = 200,
  }) async {
    final List<Map<String, dynamic>> items = getJsonList(key)..insert(0, item);
    final List<Map<String, dynamic>> trimmed = items.length > maxItems
        ? items.sublist(0, maxItems)
        : items;
    await setJsonList(key, trimmed);
  }

  Future<void> clearAll() => _prefs.clear();
}
