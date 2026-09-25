import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'core/config/app_config.dart';

/// Firebase project options.
///
/// **This file is a placeholder that must be replaced per deployment.** The
/// FlutterFire CLI owns this filename, so the canonical setup is:
///
/// ```bash
/// dart pub global activate flutterfire_cli
/// flutterfire configure --project=<your-firebase-project>
/// ```
///
/// which overwrites this file with real per-platform values and generates the
/// Android/iOS config files. Until that is done, values are read from
/// `--dart-define` flags so CI and demo builds can inject them without a
/// generated file:
///
/// ```bash
/// flutter run \
///   --dart-define=AIDRA_USE_FIREBASE=true \
///   --dart-define=AIDRA_FIREBASE_API_KEY=... \
///   --dart-define=AIDRA_FIREBASE_PROJECT_ID=aidra-prod \
///   --dart-define=AIDRA_FIREBASE_APP_ID_ANDROID=1:123:android:abc \
///   --dart-define=AIDRA_FIREBASE_SENDER_ID=123456789 \
///   --dart-define=AIDRA_GOOGLE_SERVER_CLIENT_ID=123.apps.googleusercontent.com
/// ```
class DefaultFirebaseOptions {
  const DefaultFirebaseOptions._();

  /// True when enough is present to call `Firebase.initializeApp`.
  static bool get isConfigured =>
      AppConfig.firebaseApiKey.isNotEmpty &&
      AppConfig.firebaseProjectId.isNotEmpty &&
      AppConfig.firebaseMessagingSenderId.isNotEmpty &&
      _appIdForCurrentPlatform().isNotEmpty;

  static FirebaseOptions get currentPlatform {
    if (!isConfigured) throw const FirebaseNotConfigured();
    return FirebaseOptions(
      apiKey: AppConfig.firebaseApiKey,
      appId: _appIdForCurrentPlatform(),
      messagingSenderId: AppConfig.firebaseMessagingSenderId,
      projectId: AppConfig.firebaseProjectId,
      authDomain: _orNull(AppConfig.firebaseAuthDomain),
      storageBucket: _orNull(AppConfig.firebaseStorageBucket),
    );
  }

  static String _appIdForCurrentPlatform() {
    // `defaultTargetPlatform` reports the host OS even on web, so web must be
    // checked first or a browser build would pick the Android app ID.
    if (kIsWeb) return AppConfig.firebaseAppIdWeb;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => AppConfig.firebaseAppIdAndroid,
      TargetPlatform.iOS => AppConfig.firebaseAppIdIos,
      TargetPlatform.macOS => AppConfig.firebaseAppIdIos,
      _ => AppConfig.firebaseAppIdWeb,
    };
  }

  static String? _orNull(String value) => value.isEmpty ? null : value;
}

/// Thrown when Firebase is enabled but no project has been supplied.
///
/// A dedicated type so `main()` can print setup instructions rather than a
/// stack trace — a misconfigured build should explain itself.
class FirebaseNotConfigured implements Exception {
  const FirebaseNotConfigured();

  static const String instructions = '''
Firebase is enabled (AIDRA_USE_FIREBASE=true) but no project is configured.

Fix it with one of:
  1. flutterfire configure --project=<your-firebase-project>
     (this replaces lib/firebase_options.dart)
  2. pass the AIDRA_FIREBASE_* --dart-define values, see lib/firebase_options.dart
  3. run without Firebase: flutter run --dart-define=AIDRA_USE_FIREBASE=false
     which uses AIDRA's local demo identities instead.
''';

  @override
  String toString() => 'FirebaseNotConfigured\n$instructions';
}
