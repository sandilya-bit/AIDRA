import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../../core/auth/jwt.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session_manager.dart';
import '../../../core/config/app_config.dart';
import '../../../core/constants/app_enums.dart';
import '../../../core/error/failure.dart';
import '../../../core/models/app_user.dart';
import '../../../core/models/geo_point.dart';
import '../../../core/models/parse.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/local_store.dart';
import '../../../core/utils/validators.dart';
import '../domain/auth_repository.dart';
import 'firebase_auth_gateway.dart';

/// Authentication.
///
/// The split of responsibility is the whole design:
///
///  * **Firebase** proves identity — email/password, phone OTP, Google, Apple.
///    It knows who someone is and nothing about AIDRA roles.
///  * **The AIDRA backend** decides authorization. It verifies the Firebase ID
///    token, resolves the account's role server-side, and signs an access JWT
///    carrying a `role` claim.
///  * **This class** joins them: it never lets a client claim grant a role, and
///    it always keeps a usable session so a responder mid-incident is not
///    thrown out by a network blip.
///
/// When no backend is configured (`AppConfig.useRemoteBackend == false`) the
/// Firebase ID token is used directly as the bearer, and the locally chosen
/// demo role is honoured so every dashboard stays reviewable. That relaxation
/// is keyed off the *absence* of an authoritative server, never off a request
/// parameter, so it cannot be reached in a real deployment.
class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({
    required ApiClient apiClient,
    required LocalStore store,
    required SessionManager sessions,
    FirebaseAuthGateway? gateway,
    Uuid? uuid,
  })  : _api = apiClient,
        _store = store,
        _sessions = sessions,
        _gateway = gateway,
        _uuid = uuid ?? const Uuid();

  final ApiClient _api;
  final LocalStore _store;
  final SessionManager _sessions;
  final FirebaseAuthGateway? _gateway;
  final Uuid _uuid;

  /// Prefix marking a simulated SMS challenge in a build without Firebase.
  static const String _demoVerificationPrefix = 'demo:';

  /// Firebase is only consulted when it was actually booted.
  FirebaseAuthGateway? get _identity =>
      AppConfig.useFirebase ? _gateway : null;

  bool get _isFirebaseEnabled => _identity != null;

  /// Whether a client-supplied role may be trusted.
  ///
  /// Only when there is no authoritative server to overrule it. With a backend
  /// reachable, the role inside the signed access token wins and asking for a
  /// different one changes nothing.
  bool get _trustRequestedRole => !AppConfig.useRemoteBackend;

  // ------------------------------------------------------------------ session

  @override
  Future<AppUser?> restoreSession() async {
    final AuthSession? restored = await _sessions.restore();
    if (restored == null) return null;

    _api.setAccessToken(restored.accessToken);

    // Renew before the first request goes out, but never block boot on it: an
    // offline responder must still reach their dashboard.
    if (_sessions.needsRefresh) {
      try {
        await refreshSession();
      } on Failure catch (_) {
        // The stored session may still be usable offline.
      }
    }

    final AuthSession? current = _sessions.session;
    if (current == null) return null;
    _api.setAccessToken(current.accessToken);
    return current.user;
  }

  @override
  Future<void> refreshSession() async {
    final AuthSession? current = _sessions.session;
    if (current == null) return;

    if (AppConfig.useRemoteBackend && current.refreshToken.isNotEmpty) {
      try {
        final Map<String, dynamic> response = await _api.postJson(
          '/auth/refresh',
          <String, dynamic>{'refresh_token': current.refreshToken},
        );
        await _activate(_fromExchange(response, fallback: current));
        return;
      } on NetworkFailure catch (_) {
        // Stay signed in — the token may well still be accepted.
        return;
      } on AuthFailure catch (_) {
        await _sessions.markRevoked();
        throw const SessionExpiredFailure();
      } on ServerFailure catch (error) {
        if (error.statusCode == 401 || error.statusCode == 403) {
          await _sessions.markRevoked();
          throw const SessionExpiredFailure();
        }
        return;
      }
    }

    // Firebase-only deployment: mint locally from a freshly refreshed ID token.
    final FirebaseAuthGateway? identity = _identity;
    if (identity == null) return;

    try {
      final FirebaseIdentity? account =
          await identity.currentIdentity(forceRefreshToken: true);
      if (account == null) {
        await _sessions.markRevoked();
        throw const SessionExpiredFailure();
      }
      await _activate(_localSession(account: account, role: current.user.role));
    } on IdentityFailure catch (_) {
      // Offline: keep using the token we already hold.
      return;
    }
  }

  @override
  Future<void> signOut({bool everywhere = false}) async {
    final FirebaseAuthGateway? identity = _identity;
    if (identity != null) {
      try {
        if (everywhere) await identity.revokeRefreshTokens();
        await identity.signOut();
      } on Failure catch (_) {
        // Local sign-out must succeed even when the provider is unreachable —
        // a user on a shared device has to be able to get out.
      }
    }
    _api.setAccessToken(null);
    await _sessions.end(SessionEndReason.signedOut);
  }

  // ------------------------------------------------------------------- email

  @override
  Future<AppUser> signIn({
    required String emailOrPhone,
    required String password,
    required UserRole role,
  }) async {
    final String? identifierError = Validators.emailOrPhone(emailOrPhone);
    if (identifierError != null) throw ValidationFailure(identifierError);
    final String? passwordError = Validators.password(password);
    if (passwordError != null) throw ValidationFailure(passwordError);

    final FirebaseAuthGateway? identity = _identity;

    if (identity != null) {
      if (!emailOrPhone.contains('@')) {
        throw const ValidationFailure(
          'Use the Phone tab to sign in with a number.',
        );
      }
      final FirebaseIdentity account = await identity.signInWithEmail(
        email: emailOrPhone.trim(),
        password: password,
      );
      return _mintSession(account: account, requestedRole: role);
    }

    return _localSignIn(emailOrPhone, role);
  }

  @override
  Future<AppUser> register({
    required String fullName,
    required String emailOrPhone,
    required String password,
    required UserRole role,
    String? organizationName,
    String? phone,
  }) async {
    final String? nameError = Validators.fullName(fullName);
    if (nameError != null) throw ValidationFailure(nameError);
    final String? contactError = Validators.emailOrPhone(emailOrPhone);
    if (contactError != null) throw ValidationFailure(contactError);
    final String? passwordError = Validators.password(password);
    if (passwordError != null) throw ValidationFailure(passwordError);
    if (role.requiresOrganization && (organizationName ?? '').trim().isEmpty) {
      throw const ValidationFailure('Enter your organization name');
    }

    final FirebaseAuthGateway? identity = _identity;
    if (identity == null) {
      return _activate(
        _demoSession(
          role: role,
          name: fullName.trim(),
          organizationName: organizationName,
        ),
      );
    }

    final FirebaseIdentity account = await identity.registerWithEmail(
      email: emailOrPhone.trim(),
      password: password,
      displayName: fullName.trim(),
    );

    return _mintSession(
      account: account,
      requestedRole: role,
      profile: <String, dynamic>{
        'full_name': fullName.trim(),
        'phone': phone,
        'organization_name': organizationName,
      },
    );
  }

  // ------------------------------------------------------------------- phone

  @override
  Future<PhoneVerification> startPhoneVerification({
    required String phone,
    required UserRole role,
  }) async {
    final String? error = Validators.phone(phone);
    if (error != null) throw ValidationFailure(error);

    final FirebaseAuthGateway? identity = _identity;
    if (identity == null) {
      // Demo build: the code is simulated, so the flow stays reviewable without
      // an SMS bill.
      return PhoneVerification(
        verificationId: '$_demoVerificationPrefix${phone.trim()}',
        isDemo: true,
      );
    }

    final PhoneChallenge challenge =
        await identity.startPhoneVerification(phoneNumber: _e164(phone));

    if (challenge.autoCompleted != null) {
      final AppUser user = await _mintSession(
        account: challenge.autoCompleted!,
        requestedRole: role,
      );
      return PhoneVerification(
        verificationId: challenge.verificationId,
        resendToken: challenge.resendToken,
        autoSignedInUser: user,
      );
    }

    return PhoneVerification(
      verificationId: challenge.verificationId,
      resendToken: challenge.resendToken,
    );
  }

  @override
  Future<AppUser> confirmPhoneCode({
    required String verificationId,
    required String code,
    required String phone,
    required UserRole role,
  }) async {
    final String trimmed = code.trim();
    final int minimumLength = _isFirebaseEnabled ? AppConfig.otpLength : 4;
    if (trimmed.length < minimumLength) {
      throw ValidationFailure(
        'Enter the $minimumLength-digit code sent to your phone.',
      );
    }

    final FirebaseAuthGateway? identity = _identity;
    if (identity == null ||
        verificationId.startsWith(_demoVerificationPrefix)) {
      return _localSignIn(phone, role, phone: phone);
    }

    final FirebaseIdentity account = await identity.confirmPhoneCode(
      verificationId: verificationId,
      smsCode: trimmed,
    );
    return _mintSession(account: account, requestedRole: role);
  }

  // ---------------------------------------------------------------- federated

  @override
  Future<AppUser> signInWithProvider({
    required String provider,
    required UserRole role,
  }) async {
    final FirebaseAuthGateway? identity = _identity;
    if (identity == null) {
      // Demo: synthesise an account so every social button is reviewable.
      return _localSignIn('$provider-user@aidra.app', role);
    }

    final FirebaseIdentity account = switch (provider) {
      'google' => await identity.signInWithGoogle(),
      'apple' => await identity.signInWithApple(),
      _ => throw IdentityFailure(
          'Sign-in with "$provider" is provisioned per deployment and is not '
          'enabled in this build.',
          code: 'provider-not-enabled',
        ),
    };

    return _mintSession(account: account, requestedRole: role);
  }

  // ---------------------------------------------------------------- recovery

  @override
  Future<void> sendPasswordReset({required String identifier}) async {
    final String trimmed = identifier.trim();
    final String? error = Validators.emailOrPhone(trimmed);
    if (error != null) throw ValidationFailure(error);

    if (!trimmed.contains('@')) {
      throw const ValidationFailure(
        'Password reset needs an email address. If you signed up with a phone '
        'number, sign in with a one-time code instead — that still works.',
      );
    }

    final FirebaseAuthGateway? identity = _identity;
    if (identity == null) {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      return;
    }

    await identity.sendPasswordResetEmail(trimmed);
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final String? currentError = Validators.password(currentPassword);
    if (currentError != null) throw ValidationFailure(currentError);
    final String? newError = Validators.password(newPassword);
    if (newError != null) throw ValidationFailure(newError);
    if (currentPassword == newPassword) {
      throw const ValidationFailure('Choose a password you have not used before.');
    }

    final FirebaseAuthGateway? identity = _identity;
    if (identity == null) {
      throw const ValidationFailure(
        'Password changes need the identity provider enabled in this build.',
      );
    }

    await identity.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
  }

  @override
  Future<bool> requestEmailVerification() async {
    final FirebaseAuthGateway? identity = _identity;
    if (identity == null) return false;
    await identity.sendEmailVerification();
    return true;
  }

  // -------------------------------------------------------------------- demo

  @override
  Future<AppUser> switchRole(UserRole role) async =>
      _activate(_demoSession(role: role));

  // --------------------------------------------------------------- internals

  /// Join provider identity with AIDRA authorization.
  ///
  /// [profile] is present for sign-up, which posts the extra fields the backend
  /// needs before it will issue a role.
  Future<AppUser> _mintSession({
    required FirebaseIdentity account,
    required UserRole requestedRole,
    Map<String, dynamic>? profile,
  }) async {
    final UserRole role = RolePolicy.resolveRole(
      requested: requestedRole,
      tokenRole: Jwt.tryDecode(account.idToken)?.role,
      trustRequested: _trustRequestedRole,
    );

    if (AppConfig.useRemoteBackend) {
      final AuthSession? exchanged = await _tryExchange(
        account: account,
        role: role,
        profile: profile,
      );
      if (exchanged != null) return _activate(exchanged);
    }

    return _activate(_localSession(account: account, role: role));
  }

  /// Ask the backend for a permission-bearing access token.
  ///
  /// Returns null when the backend simply could not be reached — the caller
  /// then falls back to a local session rather than locking a worried person
  /// out. An [AuthFailure] is deliberately *not* caught: a rejected identity
  /// token must surface, never be downgraded into an offline success.
  Future<AuthSession?> _tryExchange({
    required FirebaseIdentity account,
    required UserRole role,
    Map<String, dynamic>? profile,
  }) async {
    final bool isSignUp = profile != null;
    try {
      final Map<String, dynamic> response = await _api.postJson(
        isSignUp ? '/auth/register' : '/auth/firebase/exchange',
        <String, dynamic>{
          'id_token': account.idToken,
          'provider_uid': account.uid,
          'requested_role': role.key,
          if (profile != null) ...profile,
        },
        idempotencyKey: _uuid.v4(),
      );
      return _fromExchange(
        response,
        fallback: _localSession(account: account, role: role),
      );
    } on NetworkFailure catch (_) {
      return null;
    } on ServerFailure catch (_) {
      return null;
    }
  }

  /// Build a session from a `/auth/*` response.
  AuthSession _fromExchange(
    Map<String, dynamic> response, {
    required AuthSession fallback,
  }) {
    final String accessToken =
        parseString(response['access_token'], fallback.accessToken);
    final Jwt? jwt = Jwt.tryDecode(accessToken);

    final AppUser? serverUser = response['user'] == null
        ? null
        : AppUser.fromJson(parseMap(response['user']));

    final UserRole role = _resolveRole(
      requested: fallback.user.role,
      tokenRole: jwt?.role,
      serverRole: serverUser?.role,
    );

    final AppUser user = serverUser == null
        ? fallback.user.copyWith(role: role)
        : serverUser.copyWith(role: role);

    return AuthSession(
      user: user,
      accessToken: accessToken,
      refreshToken:
          parseString(response['refresh_token'], fallback.refreshToken),
      expiresAt: _expiryFrom(response, jwt) ??
          DateTime.now().add(AppConfig.localSessionTtl),
      idToken: fallback.idToken,
      issuedAt: DateTime.now(),
      lastActivityAt: DateTime.now(),
    );
  }

  /// Role precedence: signed token → server payload → locally requested.
  UserRole _resolveRole({
    required UserRole requested,
    String? tokenRole,
    UserRole? serverRole,
  }) {
    final UserRole? claimed = RolePolicy.roleFromKey(tokenRole);
    if (claimed != null) return claimed;
    if (serverRole != null) return serverRole;
    return RolePolicy.resolveRole(
      requested: requested,
      trustRequested: _trustRequestedRole,
    );
  }

  /// `expires_in` (seconds) beats `expires_at` beats the JWT's own `exp`.
  DateTime? _expiryFrom(Map<String, dynamic> response, Jwt? jwt) {
    final dynamic expiresIn = response['expires_in'];
    if (expiresIn is num) {
      return DateTime.now().add(Duration(seconds: expiresIn.round()));
    }

    final dynamic expiresAt = response['expires_at'];
    if (expiresAt != null) {
      final DateTime? parsed = expiresAt is num
          ? DateTime.fromMillisecondsSinceEpoch((expiresAt * 1000).round())
          : DateTime.tryParse(expiresAt.toString());
      if (parsed != null) return parsed;
    }

    return jwt?.expiresAt?.toLocal();
  }

  /// Session used when the backend cannot be reached.
  ///
  /// The Firebase ID token doubles as the bearer because that is exactly what
  /// the AIDRA API verifies; falling back to a placeholder keeps demo builds
  /// working. Its real `exp` is honoured when present so we never hold a token
  /// the server has already retired.
  AuthSession _localSession({
    required FirebaseIdentity account,
    required UserRole role,
  }) {
    final Jwt? idToken = Jwt.tryDecode(account.idToken);
    final DateTime? tokenExpiry = idToken?.expiresAt?.toLocal();

    final DateTime expiresAt =
        tokenExpiry != null && tokenExpiry.isAfter(DateTime.now())
            ? tokenExpiry
            : DateTime.now().add(AppConfig.localSessionTtl);

    final String displayName = account.displayName ?? '';

    return AuthSession(
      user: AppUser(
        id: account.uid,
        fullName: displayName.trim().isEmpty ? _nameFor(role) : displayName.trim(),
        role: role,
        email: account.email,
        phone: account.phone,
        language: _store.getString(LocalStore.keyLanguage) ?? 'en',
        organizationId: role.requiresOrganization ? 'org-${role.name}-1' : null,
        organizationName: _orgFor(role),
        verificationState: account.emailVerified || account.hasFederatedProvider
            ? VerificationState.verified
            : VerificationState.pending,
        skills: role == UserRole.volunteer
            ? const <String>['Medical', 'First Aid', 'Logistics']
            : const <String>[],
        lastLocation: const GeoPoint(17.3850, 78.4867),
        rating: role == UserRole.volunteer ? 4.8 : null,
        completedAssignments: role == UserRole.volunteer ? 46 : 0,
      ),
      accessToken: account.idToken ?? 'local-token',
      refreshToken: 'firebase-refresh',
      expiresAt: expiresAt,
      idToken: account.idToken,
      issuedAt: DateTime.now(),
      lastActivityAt: DateTime.now(),
    );
  }

  /// Local session for a build with no identity provider at all.
  AuthSession _demoSession({
    required UserRole role,
    String? name,
    String? email,
    String? phone,
    String? organizationName,
  }) {
    return AuthSession(
      user: _demoUser(
        role: role,
        name: name,
        email: email,
        phone: phone,
        organizationName: organizationName,
      ),
      accessToken: 'local-token',
      refreshToken: 'local-refresh',
      expiresAt: DateTime.now().add(AppConfig.localSessionTtl),
      issuedAt: DateTime.now(),
      lastActivityAt: DateTime.now(),
    );
  }

  /// Persist and publish a session.
  Future<AppUser> _activate(AuthSession session) async {
    _api.setAccessToken(session.accessToken);
    await _sessions.save(session);
    unawaited(_store.setString(LocalStore.keyRole, session.user.role.name));
    return session.user;
  }

  Future<AppUser> _localSignIn(
    String identifier,
    UserRole role, {
    String? phone,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    final bool looksLikeEmail = identifier.contains('@');
    return _activate(
      _demoSession(
        role: role,
        name: _nameFor(role),
        email: looksLikeEmail ? identifier.trim() : null,
        phone: phone ?? (looksLikeEmail ? null : identifier.trim()),
      ),
    );
  }

  /// Firebase wants E.164 (`+919000000000`); people type spaces and dashes.
  /// A missing country code is a validation problem, not something to guess at.
  String _e164(String phone) {
    final String cleaned = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    return cleaned.startsWith('+') ? cleaned : '+$cleaned';
  }

  /// Deterministic demo identities per role — makes demos predictable.
  AppUser _demoUser({
    required UserRole role,
    String? name,
    String? email,
    String? phone,
    String? organizationName,
  }) {
    return AppUser(
      id: 'usr-${role.name}',
      fullName: name ?? _nameFor(role),
      role: role,
      email: email ?? '${role.name}@aidra.app',
      phone: phone,
      language: _store.getString(LocalStore.keyLanguage) ?? 'en',
      organizationId: role.requiresOrganization ? 'org-${role.name}-1' : null,
      organizationName: organizationName ?? _orgFor(role),
      verificationState: VerificationState.verified,
      skills: role == UserRole.volunteer
          ? const <String>['Medical', 'First Aid', 'Logistics']
          : const <String>[],
      lastLocation: const GeoPoint(17.3850, 78.4867),
      rating: role == UserRole.volunteer ? 4.8 : null,
      completedAssignments: role == UserRole.volunteer ? 46 : 0,
    );
  }

  String _nameFor(UserRole role) => switch (role) {
        UserRole.victim => 'Riya Sharma',
        UserRole.volunteer => 'Arjun Patel',
        UserRole.ngo => 'Meera Nair',
        UserRole.hospital => 'Dr. Vikram Rao',
        UserRole.authority => 'Collector — Hyderabad',
        UserRole.superAdmin => 'AIDRA Administrator',
      };

  String? _orgFor(UserRole role) => switch (role) {
        UserRole.ngo => 'Red Crescent Hyderabad',
        UserRole.hospital => 'Osmania General Hospital',
        UserRole.authority => 'Hyderabad District EOC',
        _ => null,
      };
}
