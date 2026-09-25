import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_manager.dart';
import '../../../core/auth/session_store.dart';
import '../../../core/config/app_config.dart';
import '../../../core/constants/app_enums.dart';
import '../../../core/di/providers.dart';
import '../../../core/error/failure.dart';
import '../../../core/models/app_user.dart';
import '../../../core/settings/settings_controller.dart';
import '../data/auth_repository_impl.dart';
import '../data/firebase_auth_gateway.dart';
import '../domain/auth_repository.dart';

/// Secure storage whenever real tokens exist; the demo path (placeholder
/// tokens only) can use SharedPreferences.
final Provider<SessionStore> sessionStoreProvider = Provider<SessionStore>(
  (Ref ref) => AppConfig.useFirebase
      ? SecureSessionStore()
      : PrefsSessionStore(ref.watch(localStoreProvider)),
);

/// Owns token lifetime, idle timeout and the auto-logout watchdog.
final Provider<SessionManager> sessionManagerProvider =
    Provider<SessionManager>((Ref ref) {
  final SessionManager manager =
      SessionManager(store: ref.watch(sessionStoreProvider));
  ref.onDispose(manager.dispose);
  return manager;
});

/// Null whenever Firebase is off *or* failed to boot — both mean "use the
/// local identity path", which is a legitimate mode, not an error state.
final Provider<FirebaseAuthGateway?> firebaseAuthGatewayProvider =
    Provider<FirebaseAuthGateway?>((Ref ref) {
  if (!AppConfig.useFirebase || !FirebaseAuthGateway.isReady) return null;
  return FirebaseAuthGateway();
});

final Provider<AuthRepository> authRepositoryProvider =
    Provider<AuthRepository>((Ref ref) {
  return AuthRepositoryImpl(
    apiClient: ref.watch(apiClientProvider),
    store: ref.watch(localStoreProvider),
    sessions: ref.watch(sessionManagerProvider),
    gateway: ref.watch(firebaseAuthGatewayProvider),
  );
});

/// A challenge that has been sent and is waiting for a code.
class PhoneChallengeArgs {
  const PhoneChallengeArgs({
    required this.phone,
    required this.verificationId,
    required this.role,
    this.resendToken,
    this.isDemo = false,
  });

  final String phone;
  final String verificationId;
  final UserRole role;
  final int? resendToken;
  final bool isDemo;
}

/// Held between the login screen and the OTP screen.
///
/// A provider rather than a router `extra` so the challenge survives a rebuild
/// (a rotation, or the keyboard pushing the route) instead of being lost to a
/// stale route argument.
class PendingPhoneChallenge extends Notifier<PhoneChallengeArgs?> {
  @override
  PhoneChallengeArgs? build() => null;

  void set(PhoneChallengeArgs args) => state = args;

  void clear() => state = null;
}

final NotifierProvider<PendingPhoneChallenge, PhoneChallengeArgs?>
    pendingPhoneChallengeProvider =
    NotifierProvider<PendingPhoneChallenge, PhoneChallengeArgs?>(
  PendingPhoneChallenge.new,
);

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  const AuthState({
    this.status = AuthStatus.unknown,
    this.user,
    this.isBusy = false,
    this.error,
    this.notice,
    this.idleWarning,
  });

  final AuthStatus status;
  final AppUser? user;
  final bool isBusy;

  /// Failure copy for the screen that triggered the action.
  final String? error;

  /// Informational copy that outlives the action — "your session expired".
  final String? notice;

  /// Set while the idle timeout is close, so the UI can offer "stay signed in".
  final Duration? idleWarning;

  bool get isAuthenticated =>
      status == AuthStatus.authenticated && user != null;

  AuthState copyWith({
    AuthStatus? status,
    AppUser? user,
    bool? isBusy,
    String? error,
    String? notice,
    Duration? idleWarning,
    bool clearError = false,
    bool clearNotice = false,
    bool clearUser = false,
    bool clearIdleWarning = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: clearUser ? null : (user ?? this.user),
      isBusy: isBusy ?? this.isBusy,
      error: clearError ? null : (error ?? this.error),
      notice: clearNotice ? null : (notice ?? this.notice),
      idleWarning: clearIdleWarning ? null : (idleWarning ?? this.idleWarning),
    );
  }
}

final NotifierProvider<AuthController, AuthState> authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    final SessionManager sessions = ref.watch(sessionManagerProvider);

    // Auto-logout arrives as an event rather than a return value, because the
    // watchdog fires while the user is sitting on any screen.
    final StreamSubscription<SessionEvent> subscription =
        sessions.events.listen(_onSessionEvent);
    ref.onDispose(subscription.cancel);

    unawaited(_restore());
    return const AuthState();
  }

  AuthRepository get _repository => ref.read(authRepositoryProvider);

  void _onSessionEvent(SessionEvent event) {
    state = switch (event.kind) {
      SessionEventKind.ended => AuthState(
          status: AuthStatus.unauthenticated,
          notice: _noticeFor(event.reason),
        ),
      SessionEventKind.warning => state.copyWith(idleWarning: event.remaining),
    };
  }

  String _noticeFor(SessionEndReason? reason) => switch (reason) {
        SessionEndReason.expired => 'Your session expired. Please sign in again.',
        SessionEndReason.idleTimeout =>
          'Signed out after a period of inactivity.',
        SessionEndReason.revoked =>
          'Your session was ended on another device.',
        SessionEndReason.signedOut => 'You are signed out.',
        null => 'Please sign in again.',
      };

  /// Keep the idle clock alive. Called from the root pointer listener.
  void noteActivity() => ref.read(sessionManagerProvider).noteActivity();

  /// Dismiss the "signing out soon" banner (the user tapped "stay signed in").
  void keepAlive() {
    noteActivity();
    if (state.idleWarning != null) {
      state = state.copyWith(clearIdleWarning: true);
    }
  }

  void clearNotice() {
    if (state.notice != null) state = state.copyWith(clearNotice: true);
  }

  Future<void> _restore() async {
    final AppUser? user = await _repository.restoreSession();
    state = state.copyWith(
      status:
          user == null ? AuthStatus.unauthenticated : AuthStatus.authenticated,
      user: user,
      clearUser: user == null,
      clearError: true,
    );
  }

  // ------------------------------------------------------------------ actions

  Future<bool> signIn({
    required String emailOrPhone,
    required String password,
    required UserRole role,
  }) =>
      _run(() => _repository.signIn(
            emailOrPhone: emailOrPhone,
            password: password,
            role: role,
          ));

  /// Send an SMS code and remember the challenge for the OTP screen.
  Future<PhoneVerificationResult> requestPhoneCode({
    required String phone,
    required UserRole role,
  }) async {
    state = state.copyWith(isBusy: true, clearError: true, clearNotice: true);
    try {
      final PhoneVerification challenge =
          await _repository.startPhoneVerification(phone: phone, role: role);

      final AppUser? signedIn = challenge.autoSignedInUser;
      if (signedIn != null) {
        // Android read the SMS itself — no code step to show.
        ref.read(pendingPhoneChallengeProvider.notifier).clear();
        state = AuthState(status: AuthStatus.authenticated, user: signedIn);
        return PhoneVerificationResult.autoSignedIn;
      }

      ref.read(pendingPhoneChallengeProvider.notifier).set(
            PhoneChallengeArgs(
              phone: phone,
              verificationId: challenge.verificationId,
              role: role,
              resendToken: challenge.resendToken,
              isDemo: challenge.isDemo,
            ),
          );
      state = state.copyWith(isBusy: false);
      return PhoneVerificationResult.codeSent;
    } on Failure catch (failure) {
      state = state.copyWith(isBusy: false, error: failure.message);
      return PhoneVerificationResult.failed;
    } catch (error) {
      state = state.copyWith(
        isBusy: false,
        error: 'Unexpected error: $error',
      );
      return PhoneVerificationResult.failed;
    }
  }

  /// Confirm the code for the challenge currently pending.
  Future<bool> confirmPendingPhoneCode(String code) async {
    final PhoneChallengeArgs? pending = ref.read(pendingPhoneChallengeProvider);
    if (pending == null) {
      state = state.copyWith(
        error: 'Request a new code, then enter it here.',
      );
      return false;
    }

    final bool ok = await _run(
      () => _repository.confirmPhoneCode(
        verificationId: pending.verificationId,
        code: code,
        phone: pending.phone,
        role: pending.role,
      ),
    );
    if (ok) ref.read(pendingPhoneChallengeProvider.notifier).clear();
    return ok;
  }

  /// Re-request a code for the pending number (SMS never arrived, expired, …).
  Future<PhoneVerificationResult> resendPhoneCode() {
    final PhoneChallengeArgs? pending = ref.read(pendingPhoneChallengeProvider);
    if (pending == null) {
      state = state.copyWith(error: 'Enter your number again to get a code.');
      return Future<PhoneVerificationResult>.value(
        PhoneVerificationResult.failed,
      );
    }
    return requestPhoneCode(phone: pending.phone, role: pending.role);
  }

  Future<bool> signInWithProvider({
    required String provider,
    required UserRole role,
  }) =>
      _run(() => _repository.signInWithProvider(provider: provider, role: role));

  Future<bool> register({
    required String fullName,
    required String emailOrPhone,
    required String password,
    required UserRole role,
    String? organizationName,
    String? phone,
  }) =>
      _run(() => _repository.register(
            fullName: fullName,
            emailOrPhone: emailOrPhone,
            password: password,
            role: role,
            organizationName: organizationName,
            phone: phone,
          ));

  /// Account recovery. Never reveals whether the address exists.
  Future<bool> sendPasswordReset({required String identifier}) =>
      _runVoid(() => _repository.sendPasswordReset(identifier: identifier));

  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) =>
      _runVoid(() => _repository.changePassword(
            currentPassword: currentPassword,
            newPassword: newPassword,
          ));

  Future<bool> requestEmailVerification() =>
      _runVoid(() => _repository.requestEmailVerification());

  Future<void> refreshSession() async {
    try {
      await _repository.refreshSession();
    } on Failure catch (failure) {
      state = AuthState(
        status: AuthStatus.unauthenticated,
        notice: failure.message,
      );
    }
  }

  Future<void> signOut({bool everywhere = false}) async {
    await _repository.signOut(everywhere: everywhere);
    state = const AuthState(
      status: AuthStatus.unauthenticated,
      notice: 'You are signed out.',
    );
  }

  /// Demo affordance: rebuild the session as another role so every dashboard
  /// can be reviewed in the same build.
  Future<void> switchRole(UserRole role) => _run(() => _repository.switchRole(role));

  // -------------------------------------------------------------------- plumbing

  Future<bool> _run(Future<AppUser> Function() action) async {
    state = state.copyWith(
      isBusy: true,
      clearError: true,
      clearNotice: true,
      clearIdleWarning: true,
    );
    try {
      final AppUser user = await action();
      state = AuthState(status: AuthStatus.authenticated, user: user);
      return true;
    } on Failure catch (failure) {
      state = state.copyWith(
        isBusy: false,
        status: AuthStatus.unauthenticated,
        user: null,
        clearUser: true,
        error: failure.message,
      );
      return false;
    } catch (error) {
      state = state.copyWith(
        isBusy: false,
        status: AuthStatus.unauthenticated,
        error: 'Unexpected error: $error',
      );
      return false;
    }
  }

  /// For actions that do not produce a new session state (reset, change, verify).
  Future<bool> _runVoid(Future<Object?> Function() action) async {
    state = state.copyWith(isBusy: true, clearError: true, clearNotice: true);
    try {
      await action();
      state = state.copyWith(isBusy: false);
      return true;
    } on Failure catch (failure) {
      state = state.copyWith(isBusy: false, error: failure.message);
      return false;
    } catch (error) {
      state = state.copyWith(
        isBusy: false,
        error: 'Unexpected error: $error',
      );
      return false;
    }
  }
}

/// What happened when an OTP was requested.
enum PhoneVerificationResult {
  /// SMS sent; ask the user for the code.
  codeSent,

  /// The platform verified the number silently and the user is signed in.
  autoSignedIn,

  /// The request failed; `AuthState.error` explains why.
  failed,
}

/// Convenience: the signed-in user, or null.
final Provider<AppUser?> currentUserProvider =
    Provider<AppUser?>((Ref ref) => ref.watch(authControllerProvider).user);

/// Effective role for UI decisions: the session's role, falling back to the
/// locally selected demo role before sign-in.
final Provider<UserRole> effectiveRoleProvider = Provider<UserRole>((Ref ref) {
  final AppUser? user = ref.watch(currentUserProvider);
  return user?.role ?? ref.watch(appSettingsProvider).role;
});
