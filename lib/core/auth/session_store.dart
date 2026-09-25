import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/app_user.dart';
import '../storage/local_store.dart';

/// Where the session lives.
///
/// Abstracted so unit tests never touch the Keychain, and so the demo/desktop
/// path can degrade to SharedPreferences without any caller noticing.
abstract interface class SessionStore {
  Future<AuthSession?> read();

  Future<void> write(AuthSession session);

  Future<void> clear();
}

/// Production storage: iOS/macOS Keychain, Android Keystore-backed AES-GCM.
///
/// Tokens are bearer credentials — a stolen access token is a stolen identity,
/// so they must never sit in SharedPreferences where any file-level read gets
/// them. The default `FlutterSecureStorage()` configuration is the hardened
/// one (RSA-OAEP key wrapping + AES-GCM on Android).
///
/// Note: the default iOS accessibility is `unlocked`, meaning the token is
/// unreadable while the device is locked. That is the correct default for a
/// credential; if AIDRA later needs background alerting while locked, relax it
/// to `first_unlock` *and* keep the refresh token in a separate key.
class SecureSessionStore implements SessionStore {
  SecureSessionStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  /// Versioned so a schema change can be migrated rather than mis-parsed.
  static const String storageKey = 'aidra.session.v1';

  final FlutterSecureStorage _storage;

  @override
  Future<AuthSession?> read() async {
    try {
      final String? raw = await _storage.read(key: storageKey);
      return _parse(raw);
    } catch (_) {
      // An unreadable Keychain (locked, wiped, migrated between devices) means
      // "no session". Failing closed logs the user out; failing open would be
      // a security hole, and throwing would break app boot.
      return null;
    }
  }

  @override
  Future<void> write(AuthSession session) async {
    try {
      await _storage.write(key: storageKey, value: jsonEncode(session.toJson()));
    } catch (_) {
      // A write failure must not crash the sign-in path; the caller keeps the
      // session in memory and the next launch simply asks again.
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: storageKey);
    } catch (_) {
      // Ignored — see write().
    }
  }

  AuthSession? _parse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return AuthSession.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }
}

/// Non-secure fallback for demo builds and platforms where secure storage is
/// unavailable (plain-HTTP web origins).
///
/// Only appropriate while `AppConfig.useFirebase` is false and the "token" is a
/// locally minted placeholder. `SessionManager` never chooses this in a real
/// deployment — see `sessionStoreProvider`.
class PrefsSessionStore implements SessionStore {
  PrefsSessionStore(this._store);

  final LocalStore _store;

  @override
  Future<AuthSession?> read() async {
    final Map<String, dynamic>? json = _store.getJson(LocalStore.keySession);
    if (json == null) return null;
    try {
      return AuthSession.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(AuthSession session) =>
      _store.setJson(LocalStore.keySession, session.toJson());

  @override
  Future<void> clear() => _store.remove(LocalStore.keySession);
}

/// Test double.
class InMemorySessionStore implements SessionStore {
  InMemorySessionStore([this._session]);

  AuthSession? _session;

  int writeCount = 0;
  int clearCount = 0;

  AuthSession? get current => _session;

  @override
  Future<AuthSession?> read() async => _session;

  @override
  Future<void> write(AuthSession session) async {
    _session = session;
    writeCount++;
  }

  @override
  Future<void> clear() async {
    _session = null;
    clearCount++;
  }
}
