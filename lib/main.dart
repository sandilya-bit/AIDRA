import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/config/app_config.dart';
import 'core/di/providers.dart';
import 'core/storage/local_store.dart';
import 'features/auth/data/firebase_auth_gateway.dart';
import 'firebase_options.dart';

/// AIDRA bootstrap.
///
/// 1. Initialise the platform bindings.
/// 2. Load local persistence (settings, cache, offline outbox) once.
/// 3. Boot Firebase when the build enables it.
/// 4. Inject both through `ProviderScope` overrides so no other layer needs to
///    touch a plugin singleton — which is also what makes repositories
///    unit-testable with a fake store.
///
/// Firebase is deliberately *optional*. `flutter run` with no `--dart-define`
/// boots the full app against local demo identities, and a build that names a
/// Firebase project but has a broken config degrades to that same path rather
/// than refusing to start: someone in a flood does not need a crash-on-launch.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Portrait-first on phones; tablets/web remain unconstrained.
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  final LocalStore store = await LocalStore.init();

  if (AppConfig.useFirebase) {
    await _bootFirebase();
  }

  runApp(
    ProviderScope(
      overrides: <Override>[
        localStoreProvider.overrideWithValue(store),
      ],
      child: const AidraApp(),
    ),
  );
}

/// Never lets an identity-provider problem stop the app from opening.
Future<void> _bootFirebase() async {
  try {
    await FirebaseAuthGateway.initialize();
  } on FirebaseNotConfigured {
    // Instructions live on the exception so the console output is actionable.
    debugPrint(FirebaseNotConfigured.instructions);
  } catch (error) {
    debugPrint(
      'Firebase initialisation failed, continuing with local identities: $error',
    );
  }
}
