import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/config/app_config.dart';
import '../core/settings/settings_controller.dart';
import '../features/auth/presentation/auth_providers.dart';
import 'l10n/app_localizations.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

/// Root widget: theme (light/dark/system), five languages, accessibility
/// scaling, and the router.
class AidraApp extends ConsumerWidget {
  const AidraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GoRouter router = ref.watch(routerProvider);
    final ThemeMode themeMode = ref.watch(themeModeProvider);
    final Locale locale = ref.watch(localeProvider);
    final AppSettings settings = ref.watch(appSettingsProvider);

    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(highContrast: settings.highContrast),
      darkTheme: AppTheme.dark(highContrast: settings.highContrast),
      themeMode: themeMode,
      locale: locale,
      supportedLocales: AppConfig.supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
      ],
      routerConfig: router,
      builder: (BuildContext context, Widget? child) {
        Widget result = child ?? const SizedBox.shrink();

        // Idle-timeout tracking. Any pointer interaction counts as activity, so
        // a responder who is reading the map but not tapping is still the only
        // one who can be signed out; `translucent` keeps hits flowing through
        // to the widgets underneath.
        result = Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) =>
              ref.read(authControllerProvider.notifier).noteActivity(),
          child: result,
        );

        // Accessibility: "larger text" scales the whole type ramp on top of the
        // platform text scale (NFR: WCAG 2.1 AA).
        if (settings.observeLargeText) {
          final ThemeData theme = Theme.of(context);
          result = Theme(
            data: theme.copyWith(
              textTheme: theme.textTheme.apply(fontSizeFactor: 1.15),
            ),
            child: result,
          );
        }

        // Accessibility: "reduce motion" disables implicit animations app-wide
        // (the map radar also checks MediaQuery.disableAnimations directly).
        if (settings.reduceMotion) {
          result = MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: result,
          );
        }

        return result;
      },
    );
  }
}
