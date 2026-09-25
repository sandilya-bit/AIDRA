import 'dart:async';

import '../config/app_config.dart';
import '../models/app_user.dart';
import 'jwt.dart';
import 'session_store.dart';

/// Why a session ended.
enum SessionEndReason {
  /// The access token's `exp` passed.
  expired,

  /// No user interaction for [AppConfig.idleTimeout].
  idleTimeout,

  /// The server rejected the refresh token (revoked, password changed, or
  /// signed out on another device).
  revoked,

  /// The user tapped sign out.
  signedOut,
}

enum SessionEventKind { warning, ended }

/// Emitted on the [SessionManager.events] stream so the UI can react without
/// polling — show a "signing out soon" banner, or bounce to login.
class SessionEvent {
  const SessionEvent.warning(Duration this.remaining)
      : kind = SessionEventKind.warning,
        reason = null;

  const SessionEvent.ended(SessionEndReason this.reason)
      : kind = SessionEventKind.ended,
        remaining = null;

  final SessionEventKind kind;

  /// Set for [SessionEventKind.warning].
  final Duration? remaining;

  /// Set for [SessionEventKind.ended].
  final SessionEndReason? reason;

  @override
  String toString() =>
      '$kind(reason: $reason, remaining: ${remaining?.inSeconds}s)';
}

/// Owns auto-logout and the refresh decision.
///
/// Three independent things can end a session, and all three are enforced here
/// so no screen has to remember to check:
///
///  1. the access token's own `exp`, read from the JWT — authoritative, because
///     the server rejects the token regardless of what we believe;
///  2. the stored session deadline ([AuthSession.expiresAt]), which covers the
///     demo path where the bearer is not a real JWT;
///  3. inactivity past [AppConfig.idleTimeout] — shelters and command centres
///     run on shared tablets that must not stay signed in forever.
class SessionManager {
  SessionManager({
    required SessionStore store,
    DateTime Function()? clock,
    Duration idleTimeout = AppConfig.idleTimeout,
    Duration refreshSkew = AppConfig.refreshSkew,
    Duration watchInterval = AppConfig.sessionWatchInterval,
  })  : _store = store,
        _now = clock ?? DateTime.now,
        _idleTimeout = idleTimeout,
        _refreshSkew = refreshSkew,
        _watchInterval = watchInterval;

  final SessionStore _store;
  final DateTime Function() _now;
  final Duration _idleTimeout;
  final Duration _refreshSkew;
  final Duration _watchInterval;

  final StreamController<SessionEvent> _events =
      StreamController<SessionEvent>.broadcast();

  AuthSession? _session;
  DateTime? _lastActivity;
  Timer? _watchdog;
  bool _idleWarned = false;

  Stream<SessionEvent> get events => _events.stream;

  AuthSession? get session => _session;

  AppUser? get user => _session?.user;

  String? get accessToken => _session?.accessToken;

  Duration get idleTimeout => _idleTimeout;

  Duration get refreshSkew => _refreshSkew;

  /// Decoded access token, so the server's own expiry wins over our bookkeeping.
  Jwt? get accessJwt => Jwt.tryDecode(_session?.accessToken);

  /// True when the token is inside the refresh window and should be renewed
  /// before the next request goes out.
  bool get needsRefresh {
    final AuthSession? current = _session;
    if (current == null) return false;
    final Jwt? jwt = accessJwt;
    if (jwt != null) {
      return jwt.check(refreshWindow: _refreshSkew, now: _now()) ==
          JwtCheck.expiringSoon;
    }
    return current.expiresWithin(_refreshSkew);
  }

  /// True while a usable session exists.
  bool get isAuthenticated => _session != null && !hasLapsed;

  /// True when the session exists but has lapsed (expired token or deadline).
  bool get hasLapsed {
    final AuthSession? current = _session;
    if (current == null) return true;
    if (current.isExpired) return true;
    final Jwt? jwt = accessJwt;
    // Only applies when the bearer really is a JWT — the demo token is not —
    // and when it carries an expiry to compare against.
    if (jwt != null && !jwt.hasNoExpiry && jwt.isExpiredAt(_now().toUtc())) {
      return true;
    }
    return false;
  }

  Duration get idleRemaining {
    final DateTime? last = _lastActivity;
    if (last == null) return _idleTimeout;
    final Duration left = _idleTimeout - _now().difference(last);
    return left.isNegative ? Duration.zero : left;
  }

  bool get isIdle => _session != null && idleRemaining == Duration.zero;

  Duration? get timeUntilExpiry {
    final AuthSession? current = _session;
    if (current == null) return null;
    return current.expiresAt.difference(_now());
  }

  // ------------------------------------------------------------------ lifecycle

  /// Load a persisted session. Returns null (and clears storage) when the
  /// stored session has already lapsed, so a stale token is never handed to a
  /// repository.
  Future<AuthSession?> restore() async {
    final AuthSession? stored = await _store.read();
    if (stored == null) return null;

    _session = stored;
    _lastActivity = _now();

    if (hasLapsed) {
      await end(SessionEndReason.expired, notify: false);
      return null;
    }

    startWatchdog();
    return stored;
  }

  /// Persist a freshly minted session.
  Future<void> save(AuthSession session) async {
    _session = session;
    _lastActivity = _now();
    _idleWarned = false;
    await _store.write(session);
    startWatchdog();
  }

  /// Mark user interaction. In-memory only — persisting on every pointer event
  /// would hammer the Keychain for no benefit, and a crash simply re-locks the
  /// screen sooner than strictly necessary.
  void noteActivity() {
    if (_session == null) return;
    _lastActivity = _now();
    _idleWarned = false;
  }

  /// End the session and wipe the stored credentials.
  ///
  /// [notify] is false during restore, where the caller is already handling the
  /// unauthenticated state and a stream event would double-handle it.
  Future<void> end(SessionEndReason reason, {bool notify = true}) async {
    _stopWatchdog();
    final bool hadSession = _session != null;
    _session = null;
    _lastActivity = null;
    _idleWarned = false;
    await _store.clear();
    if (notify && hadSession && !_events.isClosed) {
      _events.add(SessionEvent.ended(reason));
    }
  }

  void startWatchdog() {
    _stopWatchdog();
    _watchdog = Timer.periodic(_watchInterval, (_) => unawaited(_tick()));
  }

  void _stopWatchdog() {
    _watchdog?.cancel();
    _watchdog = null;
  }

  Future<void> _tick() async {
    if (_session == null) return;

    if (hasLapsed) {
      await end(SessionEndReason.expired);
      return;
    }

    if (isIdle) {
      await end(SessionEndReason.idleTimeout);
      return;
    }

    // Warn once while the idle deadline is inside the next two ticks.
    final Duration remaining = idleRemaining;
    if (!_idleWarned && remaining <= _watchInterval * 2) {
      _idleWarned = true;
      if (!_events.isClosed) _events.add(SessionEvent.warning(remaining));
    }
  }

  /// Called by the auth layer when the server tells us the refresh token is
  /// dead, so the next launch does not retry it.
  Future<void> markRevoked() => end(SessionEndReason.revoked);

  void dispose() {
    _stopWatchdog();
    if (!_events.isClosed) _events.close();
  }
}
