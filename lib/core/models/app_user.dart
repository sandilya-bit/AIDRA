import '../constants/app_enums.dart';
import 'geo_point.dart';
import 'parse.dart';

/// Authenticated user. Role extensions (victim/volunteer/authority profiles in
/// the database design) are carried inline where the UI needs them.
class AppUser {
  const AppUser({
    required this.id,
    required this.fullName,
    required this.role,
    this.email,
    this.phone,
    this.language = 'en',
    this.organizationId,
    this.organizationName,
    this.avatarUrl,
    this.verificationState = VerificationState.unverified,
    this.skills = const <String>[],
    this.lastLocation,
    this.rating,
    this.completedAssignments = 0,
  });

  final String id;
  final String fullName;
  final UserRole role;
  final String? email;
  final String? phone;
  final String language;
  final String? organizationId;
  final String? organizationName;
  final String? avatarUrl;
  final VerificationState verificationState;
  final List<String> skills;
  final GeoPoint? lastLocation;
  final double? rating;
  final int completedAssignments;

  bool get isVerified => verificationState == VerificationState.verified;

  bool get isResponder => role == UserRole.volunteer || role == UserRole.ngo;

  String get initials => FormattersInitials.of(fullName);

  String get primaryContact => email ?? phone ?? '—';

  AppUser copyWith({
    String? fullName,
    UserRole? role,
    String? email,
    String? phone,
    String? language,
    String? organizationId,
    String? organizationName,
    String? avatarUrl,
    VerificationState? verificationState,
    List<String>? skills,
    GeoPoint? lastLocation,
  }) {
    return AppUser(
      id: id,
      fullName: fullName ?? this.fullName,
      role: role ?? this.role,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      language: language ?? this.language,
      organizationId: organizationId ?? this.organizationId,
      organizationName: organizationName ?? this.organizationName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      verificationState: verificationState ?? this.verificationState,
      skills: skills ?? this.skills,
      lastLocation: lastLocation ?? this.lastLocation,
      rating: rating,
      completedAssignments: completedAssignments,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'full_name': fullName,
        'role': role.key,
        'email': email,
        'phone': phone,
        'language': language,
        'organization_id': organizationId,
        'organization_name': organizationName,
        'avatar_url': avatarUrl,
        'verification_state': verificationState.key,
        'skills': skills,
        if (lastLocation != null) 'last_location': lastLocation!.toJson(),
        'rating': rating,
        'completed_assignments': completedAssignments,
      };

  static AppUser fromJson(Map<String, dynamic> json) {
    final UserRole role = enumFromKey(
      UserRole.values,
      json['role']?.toString(),
      UserRole.victim,
    );
    return AppUser(
      id: parseString(json['id'], 'u-${json.hashCode}'),
      fullName: parseString(json['full_name'] ?? json['name'], 'AIDRA User'),
      role: role,
      email: json['email']?.toString(),
      phone: json['phone']?.toString(),
      language: parseString(json['language'], 'en'),
      organizationId: json['organization_id']?.toString(),
      organizationName: json['organization_name']?.toString(),
      avatarUrl: json['avatar_url']?.toString(),
      verificationState: enumFromKey(
        VerificationState.values,
        json['verification_state']?.toString(),
        VerificationState.unverified,
      ),
      skills: parseStringList(json['skills']),
      lastLocation: json['last_location'] == null
          ? null
          : GeoPoint.fromJson(parseMap(json['last_location'])),
      rating: json['rating'] == null ? null : parseDouble(json['rating']),
      completedAssignments: parseInt(json['completed_assignments']),
    );
  }
}

/// Volunteer/NGO verification lifecycle (DB enum `verification_state`).
enum VerificationState { unverified, pending, verified, rejected, suspended }

extension VerificationStateX on VerificationState {
  String get key => name;

  String get label => switch (this) {
        VerificationState.unverified => 'Unverified',
        VerificationState.pending => 'Verification pending',
        VerificationState.verified => 'Verified',
        VerificationState.rejected => 'Verification rejected',
        VerificationState.suspended => 'Suspended',
      };

  bool get isVerified => this == VerificationState.verified;
}

/// Access + refresh token pair plus the identity-provider ID token.
///
/// The access token is the AIDRA-issued JWT carrying the `role` claim; the ID
/// token is Firebase's JWT proving *who* the user is and is what the backend
/// accepts at `/auth/refresh`. Both are stored only in secure storage.
class AuthSession {
  const AuthSession({
    required this.user,
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    this.idToken,
    this.issuedAt,
    this.lastActivityAt,
  });

  final AppUser user;
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;

  /// Firebase ID token (JWT). Null in demo mode.
  final String? idToken;

  /// When this session was minted — used for "signed in at" telemetry.
  final DateTime? issuedAt;

  /// Last user interaction, for the idle-timeout auto-logout.
  final DateTime? lastActivityAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// True once the token is inside the refresh window — refresh *before* the
  /// token dies so a request is never sent with a nearly-dead credential.
  bool expiresWithin(Duration window) =>
      DateTime.now().add(window).isAfter(expiresAt);

  Duration get remaining {
    final Duration left = expiresAt.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  AuthSession copyWith({
    AppUser? user,
    String? accessToken,
    String? refreshToken,
    DateTime? expiresAt,
    String? idToken,
    DateTime? lastActivityAt,
  }) {
    return AuthSession(
      user: user ?? this.user,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      expiresAt: expiresAt ?? this.expiresAt,
      idToken: idToken ?? this.idToken,
      issuedAt: issuedAt,
      lastActivityAt: lastActivityAt ?? this.lastActivityAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'user': user.toJson(),
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'expires_at': expiresAt.toIso8601String(),
        'id_token': idToken,
        'issued_at': issuedAt?.toIso8601String(),
        'last_activity_at': lastActivityAt?.toIso8601String(),
      };

  static AuthSession fromJson(Map<String, dynamic> json) => AuthSession(
        user: AppUser.fromJson(parseMap(json['user'])),
        accessToken: parseString(json['access_token']),
        refreshToken: parseString(json['refresh_token']),
        expiresAt: parseDate(json['expires_at'], DateTime.now().add(const Duration(hours: 12))),
        idToken: json['id_token']?.toString(),
        issuedAt: json['issued_at'] == null ? null : parseDate(json['issued_at']),
        lastActivityAt:
            json['last_activity_at'] == null ? null : parseDate(json['last_activity_at']),
      );
}

/// Tiny helper so `AppUser` stays free of UI helpers.
abstract final class FormattersInitials {
  static String of(String name) {
    final List<String> parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((String p) => p.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}
