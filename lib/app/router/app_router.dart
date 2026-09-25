import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/permissions.dart';
import '../../core/constants/app_enums.dart';
import '../../core/widgets/app_widgets.dart';
import '../../features/auth/presentation/auth_providers.dart';
import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/otp_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/chat/presentation/incident_chat_screen.dart';
import '../../features/chat/presentation/support_chat_screen.dart';
import '../../features/dashboard/presentation/home_dashboard_screen.dart';
import '../../features/hospital/presentation/hospital_screen.dart';
import '../../features/map/presentation/live_map_screen.dart';
import '../../features/ngo/presentation/ngo_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/reports/presentation/emergency_report_screen.dart';
import '../../features/reports/presentation/reports_list_screen.dart';
import '../../features/resources/presentation/resources_screen.dart';
import '../../features/volunteer/presentation/volunteer_screen.dart';
import '../shell/app_shell.dart';

/// Route paths, kept in one place so deep links and notifications agree.
abstract final class AppRoutes {
  static const String splash = '/splash';
  static const String login = '/login';
  static const String register = '/register';
  static const String otp = '/otp';
  static const String forgotPassword = '/forgot-password';
  static const String home = '/home';
  static const String map = '/map';
  static const String reports = '/reports';
  static const String newReport = '/reports/new';
  static const String more = '/more';
  static const String volunteers = '/volunteers';
  static const String hospital = '/hospital';
  static const String resources = '/resources';
  static const String ngo = '/ngo';
  static const String notifications = '/notifications';
  static const String profile = '/profile';
  static const String support = '/support';
  static const String chat = '/chat/:id';
}

/// Bridges Riverpod auth state into GoRouter's `refreshListenable` so the
/// redirect re-evaluates the moment a session is created or destroyed.
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    _subscription = ref.listen<AuthState>(
      authControllerProvider,
      (AuthState? previous, AuthState next) {
        if (previous?.status != next.status ||
            previous?.user?.id != next.user?.id) {
          notifyListeners();
        }
      },
    );
  }

  late final ProviderSubscription<AuthState> _subscription;

  @override
  void dispose() {
    _subscription.close();
    super.dispose();
  }
}

final Provider<GoRouter> routerProvider = Provider<GoRouter>((Ref ref) {
  final _AuthRefreshNotifier refresh = _AuthRefreshNotifier(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: refresh,
    debugLogDiagnostics: false,
    redirect: (BuildContext context, GoRouterState state) {
      final AuthState auth = ref.read(authControllerProvider);
      final UserRole role = ref.read(effectiveRoleProvider);
      final String location = state.matchedLocation;
      final bool inAuthFlow = location == AppRoutes.splash ||
          location == AppRoutes.login ||
          location == AppRoutes.register ||
          location == AppRoutes.otp ||
          location == AppRoutes.forgotPassword;

      // Session restore in flight: stay on the splash screen.
      if (auth.status == AuthStatus.unknown) {
        return location == AppRoutes.splash ? null : AppRoutes.splash;
      }
      if (auth.status == AuthStatus.unauthenticated && !inAuthFlow) {
        return AppRoutes.login;
      }
      if (auth.status == AuthStatus.authenticated && inAuthFlow) {
        return AppRoutes.home;
      }

      // Role-based access: a destination that is not for this role never
      // renders, including via a deep link. The server applies the same rule
      // through row-level security, so this is for clarity, not protection.
      if (auth.status == AuthStatus.authenticated &&
          !RolePolicy.canAccessRoute(role, location)) {
        return AppRoutes.home;
      }

      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.splash,
        builder: (BuildContext context, GoRouterState state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (BuildContext context, GoRouterState state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.register,
        builder: (BuildContext context, GoRouterState state) => const RegisterScreen(),
      ),
      GoRoute(
        path: AppRoutes.otp,
        builder: (BuildContext context, GoRouterState state) => const OtpScreen(),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        builder: (BuildContext context, GoRouterState state) =>
            const ForgotPasswordScreen(),
      ),

      // ------------------------------------------------------- tab shell
      StatefulShellRoute.indexedStack(
        builder: (
          BuildContext context,
          GoRouterState state,
          StatefulNavigationShell navigationShell,
        ) =>
            AppShell(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.home,
                builder: (BuildContext context, GoRouterState state) =>
                    const HomeDashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.map,
                builder: (BuildContext context, GoRouterState state) =>
                    const LiveMapScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.reports,
                builder: (BuildContext context, GoRouterState state) =>
                    const ReportsListScreen(),
                routes: <RouteBase>[
                  // Full-screen report composer, pushed above the tab shell.
                  GoRoute(
                    path: 'new',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (BuildContext context, GoRouterState state) =>
                        const EmergencyReportScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.more,
                builder: (BuildContext context, GoRouterState state) =>
                    const MoreScreen(),
              ),
            ],
          ),
        ],
      ),

      // ------------------------------------------- pushed feature screens
      GoRoute(
        path: AppRoutes.volunteers,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (BuildContext context, GoRouterState state) => const VolunteerScreen(),
      ),
      GoRoute(
        path: AppRoutes.hospital,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (BuildContext context, GoRouterState state) => const HospitalScreen(),
      ),
      GoRoute(
        path: AppRoutes.resources,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (BuildContext context, GoRouterState state) => const ResourcesScreen(),
      ),
      GoRoute(
        path: AppRoutes.ngo,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (BuildContext context, GoRouterState state) => const NgoScreen(),
      ),
      GoRoute(
        path: AppRoutes.notifications,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (BuildContext context, GoRouterState state) =>
            const NotificationsScreen(),
      ),
      GoRoute(
        path: AppRoutes.profile,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (BuildContext context, GoRouterState state) => const ProfileScreen(),
      ),
      GoRoute(
        path: AppRoutes.support,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (BuildContext context, GoRouterState state) =>
            const SupportChatScreen(),
      ),
      GoRoute(
        path: AppRoutes.chat,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (BuildContext context, GoRouterState state) {
          final String conversationId = state.pathParameters['id'] ?? 'general';
          return IncidentChatScreen(conversationId: conversationId);
        },
      ),
    ],
    errorBuilder: (BuildContext context, GoRouterState state) => _RouteNotFound(
      location: state.uri.toString(),
    ),
  );
});

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

class _RouteNotFound extends StatelessWidget {
  const _RouteNotFound({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: EmptyState(
          icon: Icons.explore_off_outlined,
          title: 'Screen not found',
          message: 'No AIDRA route matches "$location".',
          actionLabel: 'Go home',
          onAction: () => context.go(AppRoutes.home),
        ),
      ),
    );
  }
}
