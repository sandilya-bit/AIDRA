/// Domain-level failures. Repositories translate transport/IO exceptions into
/// these so the presentation layer never depends on Dio/Platform types.
sealed class Failure {
  const Failure(this.message, {this.cause});

  final String message;
  final Object? cause;

  /// True when the operation can be retried once connectivity returns.
  bool get isRetryable => true;

  @override
  String toString() => '$runtimeType($message)';
}

/// No connectivity / request could not reach the server.
final class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'No connection. Changes will sync when you are back online.'])
      : super(cause: null);

  const NetworkFailure.withCause(String message, Object cause) : super(message, cause: cause);
}

/// Device is offline — the mutation was queued locally (FR-105).
final class OfflineQueuedFailure extends Failure {
  const OfflineQueuedFailure([super.message = 'Saved offline. It will sync automatically.']);
}

/// The server answered with a non-success status.
final class ServerFailure extends Failure {
  const ServerFailure(this.statusCode, String message, {Object? cause})
      : super(message, cause: cause);

  final int statusCode;

  @override
  bool get isRetryable => statusCode >= 500 || statusCode == 408 || statusCode == 429;
}

/// Credentials rejected / session expired (PRD FR-1101).
final class AuthFailure extends Failure {
  const AuthFailure([super.message = 'Invalid credentials. Please try again.']);

  @override
  bool get isRetryable => false;
}

/// The session ended without the user asking: token expiry, idle timeout, or
/// a server-side revocation. Distinct from [AuthFailure] so the UI can say
/// "your session ended, sign in again" instead of "wrong password".
final class SessionExpiredFailure extends Failure {
  const SessionExpiredFailure([
    super.message = 'Your session ended for security. Please sign in again.',
  ]);

  @override
  bool get isRetryable => false;
}

/// The identity provider rejected the attempt for a reason the user can act on
/// (wrong password, unverified email, too many requests, expired OTP).
final class IdentityFailure extends Failure {
  const IdentityFailure(super.message, {this.code});

  /// Provider error code, e.g. `wrong-password`, `invalid-verification-code`.
  /// Kept for telemetry and for precise copy elsewhere; never shown raw.
  final String? code;

  @override
  bool get isRetryable => code == 'too-many-requests' || code == 'network-request-failed';
}

/// Client-side validation (missing fields, bad phone number, etc.).
final class ValidationFailure extends Failure {
  const ValidationFailure(super.message);

  @override
  bool get isRetryable => false;
}

/// Local cache/parsing problem — the app can continue with remote data.
final class CacheFailure extends Failure {
  const CacheFailure([super.message = 'Local data could not be read.']);
}

final class UnknownFailure extends Failure {
  const UnknownFailure([super.message = 'Something went wrong. Please retry.']);
}
