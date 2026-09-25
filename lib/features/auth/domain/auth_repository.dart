import '../../../core/constants/app_enums.dart';
import '../../../core/models/app_user.dart';

/// A phone challenge that has been sent but not yet confirmed.
class PhoneVerification {
  const PhoneVerification({
    required this.verificationId,
    this.resendToken,
    this.autoSignedInUser,
    this.isDemo = false,
  });

  /// Opaque handle to hand back with the code the user typed.
  final String verificationId;

  /// Present when the platform asked for it on resend.
  final int? resendToken;

  /// Set when the device read the SMS itself (Android instant verification) —
  /// the caller can skip the code step entirely.
  final AppUser? autoSignedInUser;

  /// True when no identity provider is configured and the code is simulated.
  final bool isDemo;

  /// True when the user is already signed in and no code is needed.
  bool get isComplete => autoSignedInUser != null;
}

/// Auth boundary. The domain layer knows nothing about Firebase, Dio, the
/// Keychain or demo data — only this interface.
///
/// Splitting identity from authorization is deliberate: Firebase proves *who*
/// someone is, AIDRA's backend decides *what they may do* and signs that into
/// the access token. Nothing in this interface lets the caller grant a role.
abstract class AuthRepository {
  /// Restore a persisted session on cold start, refreshing it if it is inside
  /// the refresh window. Returns null when there is no usable session.
  Future<AppUser?> restoreSession();

  /// Email (or phone-as-identifier) + password.
  Future<AppUser> signIn({
    required String emailOrPhone,
    required String password,
    required UserRole role,
  });

  /// Send an SMS code. Completes with [PhoneVerification.isComplete] when the
  /// platform verified the number without user input.
  Future<PhoneVerification> startPhoneVerification({
    required String phone,
    required UserRole role,
  });

  /// Exchange the typed code for a session.
  Future<AppUser> confirmPhoneCode({
    required String verificationId,
    required String code,
    required String phone,
    required UserRole role,
  });

  /// Google / Apple / enterprise SSO. Unsupported providers throw rather than
  /// silently degrading to a fake account.
  Future<AppUser> signInWithProvider({
    required String provider,
    required UserRole role,
  });

  /// Create an account (FR-1103).
  Future<AppUser> register({
    required String fullName,
    required String emailOrPhone,
    required String password,
    required UserRole role,
    String? organizationName,
    String? phone,
  });

  /// Account recovery. Sends a reset link to [identifier]; phone-only accounts
  /// are directed to code sign-in instead, which is a real recovery path for a
  /// user who has lost their password *and* their phone number is intact.
  Future<void> sendPasswordReset({required String identifier});

  /// Change the password of the signed-in account. Requires the current one.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  });

  /// Re-send the email verification link. Returns false when no identity
  /// provider is configured.
  Future<bool> requestEmailVerification();

  /// Renew the access token, or end the session when the refresh token is dead.
  Future<void> refreshSession();

  /// Clear the session locally and at the provider. [everywhere] also attempts
  /// to revoke the refresh token so other devices are signed out.
  Future<void> signOut({bool everywhere = false});

  /// Demo/dev helper: rebuild the session for a different role so every
  /// dashboard can be reviewed without separate accounts.
  ///
  /// Honoured only when no authoritative backend is configured; with one, the
  /// role inside the signed access token wins.
  Future<AppUser> switchRole(UserRole role);
}
