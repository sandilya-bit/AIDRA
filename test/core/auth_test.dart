import 'dart:convert';

import 'package:aidra/core/auth/jwt.dart';
import 'package:aidra/core/auth/permissions.dart';
import 'package:aidra/core/auth/session_manager.dart';
import 'package:aidra/core/auth/session_store.dart';
import 'package:aidra/core/constants/app_enums.dart';
import 'package:aidra/core/models/app_user.dart';
import 'package:flutter_test/flutter_test.dart';

/// Build a compact JWS with the given payload.
///
/// The signature is a placeholder — these tests cover *decoding and lifetime*,
/// which is all the client is allowed to do. Verification is the server's job,
/// and it is exactly that split these tests pin down.
String token(Map<String, dynamic> payload, {Map<String, dynamic>? header}) {
  String segment(Map<String, dynamic> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${segment(header ?? <String, dynamic>{'alg': 'RS256', 'typ': 'JWT'})}'
      '.${segment(payload)}'
      '.not-a-real-signature';
}

DateTime get _now => DateTime.now().toUtc();

int epoch(DateTime moment) => moment.millisecondsSinceEpoch ~/ 1000;

AppUser user(UserRole role) => AppUser(
      id: 'usr-1',
      fullName: 'Riya Sharma',
      role: role,
    );

AuthSession session({
  required UserRole role,
  required DateTime expiresAt,
  String accessToken = 'local-token',
}) {
  return AuthSession(
    user: user(role),
    accessToken: accessToken,
    refreshToken: 'refresh',
    expiresAt: expiresAt,
  );
}

void main() {
  group('Jwt decoding', () {
    test('reads subject, role and expiry from a real token', () {
      final DateTime expiry = _now.add(const Duration(hours: 1));
      final Jwt jwt = Jwt.tryDecode(
        token(<String, dynamic>{
          'sub': 'firebase-uid-1',
          'email': 'riya@aidra.app',
          'role': 'volunteer',
          'iat': epoch(_now),
          'exp': epoch(expiry),
        }),
      )!;

      expect(jwt.subject, 'firebase-uid-1');
      expect(jwt.email, 'riya@aidra.app');
      expect(jwt.role, 'volunteer');
      expect(jwt.algorithm, 'RS256');
      expect(jwt.isExpired, isFalse);
      expect(jwt.audiences, isEmpty);
    });

    test('accepts an audience list and a string alike', () {
      final Jwt asString = Jwt.tryDecode(
        token(<String, dynamic>{'aud': 'aidra.app', 'exp': epoch(_now.add(const Duration(hours: 1)))}),
      )!;
      final Jwt asList = Jwt.tryDecode(
        token(<String, dynamic>{
          'aud': <String>['aidra.app', 'aidra-web'],
          'exp': epoch(_now.add(const Duration(hours: 1))),
        }),
      )!;

      expect(asString.audiences, <String>['aidra.app']);
      expect(asList.audiences, <String>['aidra.app', 'aidra-web']);
    });

    test('returns null instead of throwing on malformed input', () {
      expect(Jwt.tryDecode(null), isNull);
      expect(Jwt.tryDecode(''), isNull);
      expect(Jwt.tryDecode('a.b'), isNull);
      expect(Jwt.tryDecode('not-a-token'), isNull);
      expect(Jwt.tryDecode('!!!.???.***'), isNull);
      // Valid base64, but the payload is not a JSON object.
      expect(Jwt.tryDecode('${token(<String, dynamic>{'exp': 1})}.extra'), isNull);
    });

    test('treats a token with no exp as expired (fail closed)', () {
      final Jwt jwt = Jwt.tryDecode(token(<String, dynamic>{'sub': 'x'}))!;

      expect(jwt.hasNoExpiry, isTrue);
      expect(jwt.isExpired, isTrue);
      expect(jwt.check(), JwtCheck.noExpiry);
    });

    test('classifies lifetime states', () {
      final Jwt fresh = Jwt.tryDecode(
        token(<String, dynamic>{'exp': epoch(_now.add(const Duration(hours: 2)))}),
      )!;
      final Jwt soon = Jwt.tryDecode(
        token(<String, dynamic>{'exp': epoch(_now.add(const Duration(minutes: 1)))}),
      )!;
      final Jwt dead = Jwt.tryDecode(
        token(<String, dynamic>{'exp': epoch(_now.subtract(const Duration(minutes: 1)))}),
      )!;
      final Jwt future = Jwt.tryDecode(
        token(<String, dynamic>{
          'nbf': epoch(_now.add(const Duration(minutes: 10))),
          'exp': epoch(_now.add(const Duration(hours: 1))),
        }),
      )!;

      expect(fresh.check(), JwtCheck.valid);
      expect(soon.check(), JwtCheck.expiringSoon);
      expect(dead.check(), JwtCheck.expired);
      expect(future.check(), JwtCheck.notYetValid);
    });

    test('flags an unsigned token', () {
      final Jwt none = Jwt.tryDecode(
        token(<String, dynamic>{'exp': epoch(_now.add(const Duration(hours: 1)))},
            header: <String, dynamic>{'alg': 'none'}),
      )!;

      expect(none.isUnsigned, isTrue);
    });

    test('never prints the raw token in toString', () {
      final Jwt jwt = Jwt.tryDecode(
        token(<String, dynamic>{'sub': 'uid', 'exp': epoch(_now.add(const Duration(hours: 1)))}),
      )!;

      expect(jwt.toString(), isNot(contains('not-a-real-signature')));
    });
  });

  group('RolePolicy', () {
    test('grants each role exactly what the PRD role matrix allows', () {
      expect(RolePolicy.can(UserRole.victim, Permission.reportEmergency), isTrue);
      expect(RolePolicy.can(UserRole.victim, Permission.manageResources), isFalse);
      expect(
        RolePolicy.can(UserRole.victim, Permission.manageHospitalCapacity),
        isFalse,
      );

      expect(
        RolePolicy.can(UserRole.volunteer, Permission.respondToAssignments),
        isTrue,
      );
      expect(RolePolicy.can(UserRole.volunteer, Permission.viewCommandCentre), isFalse);

      expect(RolePolicy.can(UserRole.ngo, Permission.coordinateNgoTeams), isTrue);
      expect(
        RolePolicy.can(UserRole.hospital, Permission.manageHospitalCapacity),
        isTrue,
      );
      expect(RolePolicy.can(UserRole.hospital, Permission.coordinateNgoTeams), isFalse);
      expect(RolePolicy.can(UserRole.authority, Permission.viewCommandCentre), isTrue);
      expect(RolePolicy.can(UserRole.authority, Permission.administerPlatform), isFalse);
      expect(
        RolePolicy.can(UserRole.superAdmin, Permission.administerPlatform),
        isTrue,
      );
    });

    test('super admin is a superset of every other role', () {
      final Set<Permission> all = RolePolicy.permissionsOf(UserRole.superAdmin);
      for (final UserRole role in UserRole.values) {
        expect(
          RolePolicy.permissionsOf(role).difference(all),
          isEmpty,
          reason: '$role has permissions superAdmin lacks',
        );
      }
    });

    test('parses tokens, including the SQL snake_case spelling', () {
      expect(RolePolicy.roleFromKey('volunteer'), UserRole.volunteer);
      expect(RolePolicy.roleFromKey('SUPER_ADMIN'), UserRole.superAdmin);
      expect(RolePolicy.roleFromKey('superAdmin'), UserRole.superAdmin);
      expect(RolePolicy.roleFromKey('nonsense'), isNull);
      expect(RolePolicy.roleFromKey(''), isNull);
      expect(RolePolicy.roleFromKey(null), isNull);
    });

    test('the signed token always beats the requested role', () {
      expect(
        RolePolicy.resolveRole(
          requested: UserRole.superAdmin,
          tokenRole: 'victim',
          trustRequested: true,
        ),
        UserRole.victim,
      );
    });

    test('a requested role is honoured only when nothing overrules it', () {
      expect(
        RolePolicy.resolveRole(requested: UserRole.ngo, trustRequested: true),
        UserRole.ngo,
      );
      // With an authoritative backend and no claim, the safest role wins.
      expect(
        RolePolicy.resolveRole(requested: UserRole.ngo, trustRequested: false),
        UserRole.victim,
      );
    });

    test('guards the agency destinations', () {
      expect(RolePolicy.canAccessRoute(UserRole.victim, '/home'), isTrue);
      expect(RolePolicy.canAccessRoute(UserRole.victim, '/hospital'), isFalse);
      expect(RolePolicy.canAccessRoute(UserRole.hospital, '/hospital'), isTrue);
      expect(RolePolicy.canAccessRoute(UserRole.victim, '/ngo'), isFalse);
      expect(RolePolicy.canAccessRoute(UserRole.ngo, '/ngo'), isTrue);
      expect(
        RolePolicy.canAccessRoute(UserRole.authority, '/resources/history'),
        isTrue,
      );
      expect(RolePolicy.canAccessRoute(UserRole.victim, '/resources'), isFalse);
      expect(RolePolicy.guardFor('/reports/new'), isNull);
      expect(RolePolicy.guardFor('/hospital'), '/hospital');
    });
  });

  group('SessionManager', () {
    test('restores a live session and exposes its token', () async {
      final InMemorySessionStore store = InMemorySessionStore(
        session(
          role: UserRole.volunteer,
          expiresAt: DateTime.now().add(const Duration(hours: 4)),
        ),
      );
      final SessionManager manager = SessionManager(store: store);
      addTearDown(manager.dispose);

      final AuthSession? restored = await manager.restore();

      expect(restored, isNotNull);
      expect(manager.isAuthenticated, isTrue);
      expect(manager.accessToken, 'local-token');
      expect(manager.user?.role, UserRole.volunteer);
    });

    test('refuses to restore a lapsed session and wipes it', () async {
      final InMemorySessionStore store = InMemorySessionStore(
        session(
          role: UserRole.victim,
          expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
        ),
      );
      final SessionManager manager = SessionManager(store: store);
      addTearDown(manager.dispose);

      expect(await manager.restore(), isNull);
      expect(manager.isAuthenticated, isFalse);
      expect(store.clearCount, 1, reason: 'a dead token must not be left behind');
    });

    test('the token\'s own exp beats our stored deadline', () async {
      final String expiredJwt = token(<String, dynamic>{
        'sub': 'uid',
        'exp': epoch(_now.subtract(const Duration(minutes: 5))),
      });

      final SessionManager manager = SessionManager(
        store: InMemorySessionStore(
          session(
            role: UserRole.victim,
            // Our own record says four more hours, but the server disagrees.
            expiresAt: DateTime.now().add(const Duration(hours: 4)),
            accessToken: expiredJwt,
          ),
        ),
      );
      addTearDown(manager.dispose);

      expect(await manager.restore(), isNull);
      expect(manager.isAuthenticated, isFalse);
    });

    test('ask to refresh inside the window, not after it', () async {
      final SessionManager manager = SessionManager(
        store: InMemorySessionStore(
          session(
            role: UserRole.victim,
            expiresAt: DateTime.now().add(const Duration(minutes: 2)),
          ),
        ),
      );
      addTearDown(manager.dispose);
      await manager.restore();

      // Default refresh skew is five minutes, so a token with two minutes left
      // is already due.
      expect(manager.needsRefresh, isTrue);

      await manager.save(
        session(
          role: UserRole.victim,
          expiresAt: DateTime.now().add(const Duration(hours: 6)),
        ),
      );
      expect(manager.needsRefresh, isFalse);
    });

    test('ends the session on expiry and reports why', () async {
      final InMemorySessionStore store = InMemorySessionStore();
      final SessionManager manager = SessionManager(
        store: store,
        watchInterval: const Duration(milliseconds: 20),
      );
      addTearDown(manager.dispose);

      final Future<SessionEvent> ended = manager.events.first;

      await manager.save(
        session(
          role: UserRole.victim,
          expiresAt: DateTime.now().add(const Duration(milliseconds: 40)),
        ),
      );

      final SessionEvent event = await ended;
      expect(event.kind, SessionEventKind.ended);
      expect(event.reason, SessionEndReason.expired);
      expect(manager.session, isNull);
      expect(store.clearCount, 1);
    });

    test('auto-logs-out an idle device but not an active one', () async {
      final SessionManager manager = SessionManager(
        store: InMemorySessionStore(),
        idleTimeout: const Duration(milliseconds: 120),
        watchInterval: const Duration(milliseconds: 20),
      );
      addTearDown(manager.dispose);

      await manager.save(
        session(
          role: UserRole.authority,
          expiresAt: DateTime.now().add(const Duration(hours: 8)),
        ),
      );

      // Stay active for longer than the idle timeout would allow.
      for (int i = 0; i < 4; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 60));
        manager.noteActivity();
      }
      expect(manager.isAuthenticated, isTrue, reason: 'activity must reset the clock');

      // Now go quiet.
      await Future<void>.delayed(const Duration(milliseconds: 260));
      expect(manager.isAuthenticated, isFalse);
    });

    test('warns before the idle timeout fires', () async {
      final SessionManager manager = SessionManager(
        store: InMemorySessionStore(),
        idleTimeout: const Duration(milliseconds: 300),
        watchInterval: const Duration(milliseconds: 20),
      );
      addTearDown(manager.dispose);

      final Future<SessionEvent> warning = manager.events
          .firstWhere((SessionEvent e) => e.kind == SessionEventKind.warning);

      await manager.save(
        session(
          role: UserRole.ngo,
          expiresAt: DateTime.now().add(const Duration(hours: 8)),
        ),
      );

      final SessionEvent event = await warning;
      expect(event.kind, SessionEventKind.warning);
      expect(event.remaining, isNotNull);
    });

    test('sign-out clears storage and stays silent', () async {
      final InMemorySessionStore store = InMemorySessionStore();
      final SessionManager manager = SessionManager(store: store);
      addTearDown(manager.dispose);

      bool notified = false;
      manager.events.listen((SessionEvent _) => notified = true);

      await manager.save(
        session(
          role: UserRole.victim,
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      );
      await manager.end(SessionEndReason.signedOut);

      expect(manager.session, isNull);
      expect(store.current, isNull);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(notified, isFalse, reason: 'the caller already knows it signed out');
    });

    test('persists a saved session so the next launch restores it', () async {
      final InMemorySessionStore store = InMemorySessionStore();
      final SessionManager first = SessionManager(store: store);
      addTearDown(first.dispose);

      await first.save(
        session(
          role: UserRole.hospital,
          expiresAt: DateTime.now().add(const Duration(hours: 3)),
        ),
      );
      first.dispose();

      final SessionManager second = SessionManager(store: store);
      addTearDown(second.dispose);

      expect((await second.restore())?.user.role, UserRole.hospital);
    });
  });

  group('AuthSession serialisation', () {
    test('round-trips the identity token and activity stamp', () {
      final AuthSession original = AuthSession(
        user: user(UserRole.volunteer),
        accessToken: 'access',
        refreshToken: 'refresh',
        expiresAt: DateTime.parse('2030-01-01T00:00:00.000Z'),
        idToken: 'id-token',
        issuedAt: DateTime.parse('2029-12-31T12:00:00.000Z'),
        lastActivityAt: DateTime.parse('2029-12-31T12:30:00.000Z'),
      );

      final AuthSession restored = AuthSession.fromJson(original.toJson());

      expect(restored.accessToken, 'access');
      expect(restored.refreshToken, 'refresh');
      expect(restored.idToken, 'id-token');
      expect(restored.user.fullName, 'Riya Sharma');
      expect(restored.expiresAt, original.expiresAt);
      expect(restored.lastActivityAt, original.lastActivityAt);
    });

    test('survives a session stored before these fields existed', () {
      final AuthSession legacy = AuthSession.fromJson(<String, dynamic>{
        'user': user(UserRole.victim).toJson(),
        'access_token': 'access',
        'refresh_token': 'refresh',
        'expires_at': '2030-01-01T00:00:00.000Z',
      });

      expect(legacy.idToken, isNull);
      expect(legacy.issuedAt, isNull);
      expect(legacy.accessToken, 'access');
      expect(legacy.isExpired, isFalse);
    });
  });
}
