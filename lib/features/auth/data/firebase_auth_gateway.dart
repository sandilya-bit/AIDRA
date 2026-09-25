import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/config/app_config.dart';
import '../../../core/error/failure.dart';
import '../../../firebase_options.dart';

/// Identity as the provider sees it — deliberately not [AppUser].
///
/// Firebase knows who someone is; AIDRA knows what they are allowed to do. The
/// two are merged in `AuthRepositoryImpl`, never here.
class FirebaseIdentity {
  const FirebaseIdentity({
    required this.uid,
    this.idToken,
    this.email,
    this.phone,
    this.displayName,
    this.emailVerified = false,
    this.providerIds = const <String>[],
    this.isAnonymous = false,
  });

  /// Firebase UID — stable across sign-in methods for the same account.
  final String uid;

  /// Firebase ID token: a JWT proving identity to the AIDRA backend. Null when
  /// the device is offline and no cached token is available.
  final String? idToken;

  final String? email;
  final String? phone;
  final String? displayName;
  final bool emailVerified;
  final List<String> providerIds;
  final bool isAnonymous;

  /// `true` when this account came from Google/Apple rather than a password, in
  /// which case email verification is the provider's problem, not ours.
  bool get hasFederatedProvider => providerIds.any(
        (String id) => id == 'google.com' || id == 'apple.com',
      );

  @override
  String toString() => 'FirebaseIdentity(uid: $uid, providers: $providerIds)';
}

/// A pending SMS challenge.
class PhoneChallenge {
  const PhoneChallenge({
    required this.verificationId,
    this.resendToken,
    this.autoCompleted,
  });

  /// Passed back with the typed code to build a credential.
  final String verificationId;

  /// Present when the platform wants this echoed on resend.
  final int? resendToken;

  /// Set when Android read the SMS itself and the user is already signed in —
  /// the UI can skip the code step entirely.
  final FirebaseIdentity? autoCompleted;
}

/// Every call into Firebase Auth and Google Sign-In goes through here.
///
/// Deliberately one file. These SDKs move fast — `google_sign_in` 7.x replaced
/// the all-in-one `signIn()` with `initialize()` + `authenticate()`, and moved
/// `accessToken` behind `authorizationClient` — so keeping them behind a single
/// boundary means a plugin upgrade touches this file and nothing else. Callers
/// depend on [FirebaseIdentity] and typed [Failure]s.
///
/// The APIs used below follow the official FlutterFire federated-auth guide and
/// the google_sign_in 7.x README.
class FirebaseAuthGateway {
  FirebaseAuthGateway({FirebaseAuth? auth, GoogleSignIn? googleSignIn})
      : _auth = auth ?? FirebaseAuth.instance,
        _google = googleSignIn ?? GoogleSignIn.instance;

  final FirebaseAuth _auth;
  final GoogleSignIn _google;

  static bool _firebaseReady = false;
  static bool _googleReady = false;

  /// True once [initialize] has succeeded. Dependency injection checks this
  /// before handing out a gateway, so a build with broken Firebase config
  /// degrades to the local identity path instead of throwing on first use.
  static bool get isReady => _firebaseReady;

  /// Boot Firebase once per process.
  static Future<void> initialize() async {
    if (_firebaseReady) return;
    if (!DefaultFirebaseOptions.isConfigured) {
      throw const FirebaseNotConfigured();
    }
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    _firebaseReady = true;
  }

  /// Google Sign-In needs its own initialisation, and a *server* client ID on
  /// Android or no `idToken` is returned.
  static Future<void> _ensureGoogleReady() async {
    if (_googleReady) return;
    await GoogleSignIn.instance.initialize(
      serverClientId: AppConfig.googleServerClientId.isEmpty
          ? null
          : AppConfig.googleServerClientId,
    );
    _googleReady = true;
  }

  // --------------------------------------------------------------- email

  Future<FirebaseIdentity> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return _identityFrom(result.user);
    } on FirebaseAuthException catch (error) {
      throw _mapAuthException(error);
    }
  }

  Future<FirebaseIdentity> registerWithEmail({
    required String email,
    required String password,
    required String displayName,
  }) async {
    try {
      final UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final User? user = result.user;
      if (user != null) {
        if (displayName.trim().isNotEmpty) {
          await user.updateDisplayName(displayName.trim());
        }
        // Verified email matters for responder trust, but a failure here must
        // not block account creation — the user can resend later.
        try {
          if (!user.emailVerified) await user.sendEmailVerification();
        } catch (_) {}
      }
      return _identityFrom(user);
    } on FirebaseAuthException catch (error) {
      throw _mapAuthException(error);
    }
  }

  // --------------------------------------------------------------- phone

  /// Start an SMS challenge. Completes on `codeSent` (the normal path) or on
  /// `verificationCompleted` (Android instant retrieval).
  Future<PhoneChallenge> startPhoneVerification({
    required String phoneNumber,
    Duration timeout = const Duration(seconds: 60),
    int? resendToken,
  }) {
    final Completer<PhoneChallenge> completer = Completer<PhoneChallenge>();

    void fail(Object error) {
      if (!completer.isCompleted) completer.completeError(error);
    }

    // The callback contract is what delivers the result; the returned future is
    // only for immediate errors, so it is explicitly fire-and-forget.
    unawaited(_auth
        .verifyPhoneNumber(
      phoneNumber: phoneNumber,
      timeout: timeout,
      forceResendingToken: resendToken,
      verificationCompleted: (PhoneAuthCredential credential) async {
        try {
          final UserCredential result =
              await _auth.signInWithCredential(credential);
          if (!completer.isCompleted) {
            completer.complete(
              PhoneChallenge(
                verificationId: credential.verificationId ?? '',
                autoCompleted: await _identityFrom(result.user),
              ),
            );
          }
        } catch (error) {
          fail(error);
        }
      },
      verificationFailed: (FirebaseAuthException error) {
        fail(_mapAuthException(error));
      },
      codeSent: (String verificationId, int? token) {
        if (!completer.isCompleted) {
          completer.complete(
            PhoneChallenge(verificationId: verificationId, resendToken: token),
          );
        }
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        // Not an error: the SMS simply has to be typed by hand.
      },
    )
        .catchError((Object error) {
      fail(
        error is FirebaseAuthException
            ? _mapAuthException(error)
            : IdentityFailure('Could not send the code: $error'),
      );
    }));

    return completer.future.timeout(
      timeout + const Duration(seconds: 5),
      onTimeout: () => throw const IdentityFailure(
        'The code took too long to arrive. Check your signal and try again.',
        code: 'timeout',
      ),
    );
  }

  Future<FirebaseIdentity> confirmPhoneCode({
    required String verificationId,
    required String smsCode,
  }) async {
    try {
      final PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode.trim(),
      );
      final UserCredential result =
          await _auth.signInWithCredential(credential);
      return _identityFrom(result.user);
    } on FirebaseAuthException catch (error) {
      throw _mapAuthException(error);
    }
  }

  // -------------------------------------------------------------- google

  /// Interactive Google sign-in.
  ///
  /// Web uses the Firebase SDK's popup; native platforms must use the
  /// `google_sign_in` plugin to obtain an `idToken`, which is then exchanged
  /// for a Firebase credential (per the FlutterFire guide).
  Future<FirebaseIdentity> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        final UserCredential result =
            await _auth.signInWithPopup(GoogleAuthProvider());
        return _identityFrom(result.user);
      }

      await _ensureGoogleReady();
      final GoogleSignInAccount account = await _google.authenticate();
      final String? idToken = account.authentication.idToken;

      if (idToken == null) {
        // Almost always a missing server client ID on Android.
        throw const IdentityFailure(
          'Google did not return an identity token. Check that the Google '
          'provider is enabled and AIDRA_GOOGLE_SERVER_CLIENT_ID is set.',
          code: 'google-id-token-missing',
        );
      }

      final OAuthCredential credential =
          GoogleAuthProvider.credential(idToken: idToken);
      final UserCredential result =
          await _auth.signInWithCredential(credential);
      return _identityFrom(result.user);
    } on GoogleSignInException catch (error) {
      throw IdentityFailure(_googleMessage(error), code: error.code.name);
    } on FirebaseAuthException catch (error) {
      throw _mapAuthException(error);
    }
  }

  /// Apple sign-in.
  ///
  /// Native platforms go through `signInWithProvider`, web through a popup —
  /// the split the FlutterFire guide prescribes. Requires Apple to be enabled
  /// in the Firebase console and, on Apple platforms, the "Sign in with Apple"
  /// capability; until then it throws a typed [IdentityFailure].
  Future<FirebaseIdentity> signInWithApple() async {
    try {
      final AppleAuthProvider provider = AppleAuthProvider();
      final UserCredential result = kIsWeb
          ? await _auth.signInWithPopup(provider)
          : await _auth.signInWithProvider(provider);
      return _identityFrom(result.user);
    } on FirebaseAuthException catch (error) {
      throw _mapAuthException(error);
    }
  }

  // ------------------------------------------------------------ recovery

  /// Password reset email. Firebase sends it; AIDRA never sees the password.
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (error) {
      throw _mapAuthException(error);
    }
  }

  Future<void> sendEmailVerification() async {
    final User? user = _auth.currentUser;
    if (user == null) {
      throw const IdentityFailure('Sign in before verifying your email.');
    }
    try {
      await user.sendEmailVerification();
    } on FirebaseAuthException catch (error) {
      throw _mapAuthException(error);
    }
  }

  /// Changing a password requires a recent login — Firebase demands the current
  /// credential even for a session that looks healthy.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final User? user = _auth.currentUser;
    final String? email = user?.email;
    if (user == null || email == null) {
      throw const IdentityFailure(
        'Sign in with your email and password to change it.',
        code: 'no-password-provider',
      );
    }
    try {
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: email, password: currentPassword),
      );
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (error) {
      throw _mapAuthException(error);
    }
  }

  Future<void> deleteAccount() async {
    final User? user = _auth.currentUser;
    if (user == null) {
      throw const IdentityFailure('You are not signed in.', code: 'no-user');
    }
    try {
      await user.delete();
    } on FirebaseAuthException catch (error) {
      throw _mapAuthException(error);
    }
  }

  // ------------------------------------------------------------- session

  Future<FirebaseIdentity?> currentIdentity({
    bool forceRefreshToken = false,
  }) async {
    final User? user = _auth.currentUser;
    if (user == null) return null;
    return _identityFrom(user, forceRefreshToken: forceRefreshToken);
  }

  /// Reload from the server (picks up an email that was verified elsewhere).
  Future<FirebaseIdentity?> refreshedIdentity() async {
    final User? user = _auth.currentUser;
    if (user == null) return null;
    try {
      await user.reload();
    } on FirebaseAuthException catch (_) {
      // Offline reload failure is survivable: the cached user is still valid
      // until its token expires.
    }
    return _identityFrom(_auth.currentUser);
  }

  /// Fires on sign-in, sign-out and token invalidation.
  Stream<FirebaseIdentity?> get identityChanges => _auth
      .authStateChanges()
      .asyncMap((User? user) async =>
          user == null ? null : await _identityFrom(user));

  Future<void> signOut() async {
    try {
      if (!kIsWeb && _googleReady) {
        try {
          await _google.disconnect();
        } catch (_) {
          // Google may already be signed out; Firebase sign-out is what matters.
        }
      }
      await _auth.signOut();
    } on FirebaseAuthException catch (error) {
      throw _mapAuthException(error);
    }
  }

  /// Best-effort revoke of the refresh token. Used when an account is removed
  /// from a shared device.
  Future<void> revokeRefreshTokens() async {
    final User? user = _auth.currentUser;
    if (user == null) return;
    try {
      await user.getIdToken(true);
    } catch (_) {
      // Ignored: the local session is being torn down regardless.
    }
  }

  // ------------------------------------------------------------ internals

  Future<FirebaseIdentity> _identityFrom(
    User? user, {
    bool forceRefreshToken = false,
  }) async {
    if (user == null) {
      throw const IdentityFailure(
        'The identity provider returned no account.',
        code: 'no-user',
      );
    }

    String? idToken;
    try {
      idToken = await user.getIdToken(forceRefreshToken);
    } catch (_) {
      // Offline: the backend can still validate a cached token, so missing one
      // is not fatal here.
      idToken = null;
    }

    return FirebaseIdentity(
      uid: user.uid,
      idToken: idToken,
      email: user.email,
      phone: user.phoneNumber,
      displayName: user.displayName,
      emailVerified: user.emailVerified,
      providerIds:
          user.providerData.map((UserInfo info) => info.providerId).toList(
                growable: false,
              ),
      isAnonymous: user.isAnonymous,
    );
  }

  /// Only `canceled` is special-cased, matching the plugin's own example; every
  /// other code falls through to the SDK description, so a future enum member
  /// can never break sign-in with a non-exhaustive switch.
  String _googleMessage(GoogleSignInException error) => switch (error.code) {
        GoogleSignInExceptionCode.canceled => 'Google sign-in was cancelled.',
        _ => 'Google sign-in failed: ${error.description}. '
            'Please try again or use email instead.',
      };

  /// Turn provider error codes into copy a worried person can act on.
  ///
  /// `invalid-credential`, `wrong-password` and `user-not-found` deliberately
  /// collapse into one message: telling an attacker which half was wrong turns
  /// sign-in into an account-enumeration oracle.
  IdentityFailure _mapAuthException(FirebaseAuthException error) {
    final String code = error.code;
    final String message = switch (code) {
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' =>
        'That email and password combination is not recognised.',
      'invalid-email' => 'Enter a valid email address.',
      'email-already-in-use' =>
        'An account already exists for that email. Sign in instead.',
      'weak-password' => 'Choose a password of at least 8 characters.',
      'user-disabled' =>
        'This account is disabled. Contact your AIDRA coordinator.',
      'operation-not-allowed' =>
        'That sign-in method is not enabled for AIDRA yet.',
      'too-many-requests' =>
        'Too many attempts. Wait a few minutes and try again.',
      'invalid-phone-number' =>
        'Enter a phone number in international format, e.g. +91 90000 00000.',
      'invalid-verification-code' =>
        'That code is not correct. Check the SMS and try again.',
      'invalid-verification-id' || 'session-expired' =>
        'That code has expired. Request a new one.',
      'missing-phone-number' => 'Enter your phone number.',
      'quota-exceeded' =>
        'SMS limit reached for this device. Try again in a little while.',
      'requires-recent-login' =>
        'For security, sign in again before changing this.',
      'network-request-failed' =>
        'No connection to the identity service. Check your signal.',
      'credential-already-in-use' =>
        'That identity is already linked to another AIDRA account.',
      'account-exists-with-different-credential' =>
        'You already registered with a different method. Sign in that way first.',
      'unauthorized-domain' =>
        'This domain is not authorised for sign-in. Ask your AIDRA administrator.',
      'second-factor-required' || 'multi-factor-auth-required' =>
        'This account needs a second factor to sign in.',
      'captcha-check-failed' =>
        'The security check failed. Try again.',
      _ => error.message ?? 'Sign-in failed. Please try again.',
    };
    return IdentityFailure(message, code: code);
  }
}
