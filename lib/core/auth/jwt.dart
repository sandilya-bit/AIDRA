import 'dart:convert';

/// Read-only view over a JSON Web Token.
///
/// **This decodes, it does not verify.** Signature checking needs the issuer's
/// public key and happens on the AIDRA backend for every request. The client
/// reads claims only to drive UX — how long the token lives, which
/// destinations to offer — and must never treat a claim as authorization.
/// A tampered token cannot pass the server; it could only mislead its own UI,
/// which is why every claim here is treated as a hint, not a fact.
class Jwt {
  const Jwt._(this.raw, this.header, this.payload);

  /// The original compact serialisation (`header.payload.signature`).
  final String raw;

  final Map<String, dynamic> header;
  final Map<String, dynamic> payload;

  /// Decode without throwing. Returns null for anything that is not a
  /// three-part JWT whose header and payload are JSON objects.
  static Jwt? tryDecode(String? token) {
    if (token == null) return null;
    final String trimmed = token.trim();
    if (trimmed.isEmpty) return null;

    final List<String> parts = trimmed.split('.');
    if (parts.length != 3) return null;

    final Map<String, dynamic>? header = _segment(parts[0]);
    final Map<String, dynamic>? payload = _segment(parts[1]);
    if (header == null || payload == null) return null;

    return Jwt._(trimmed, header, payload);
  }

  static Map<String, dynamic>? _segment(String segment) {
    if (segment.isEmpty) return null;
    try {
      // JWT base64url omits padding; normalize() restores it.
      final String decoded = utf8.decode(base64Url.decode(base64Url.normalize(segment)));
      final dynamic json = jsonDecode(decoded);
      return json is Map<String, dynamic> ? json : null;
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------------ header

  String? get algorithm => header['alg']?.toString();

  String? get keyId => header['kid']?.toString();

  /// An unsigned token is never acceptable as proof of identity.
  bool get isUnsigned {
    final String? alg = algorithm;
    return alg == null || alg.toLowerCase() == 'none';
  }

  // --------------------------------------------------------------- identity

  String? get subject => _string('sub');

  String? get issuer => _string('iss');

  String? get email => _string('email');

  String? get phoneNumber => _string('phone_number');

  /// Role claim the backend signs into the access token. Checked against
  /// [UserRole] by the auth layer; unknown values fall back to the least
  /// privileged role rather than being trusted.
  String? get role => _string('role') ?? _string('https://aidra.app/role');

  /// `aud` may be a single string or a list, per RFC 7519.
  List<String> get audiences {
    final dynamic aud = payload['aud'];
    if (aud is String) return <String>[aud];
    if (aud is List) {
      return aud.map((dynamic e) => e.toString()).toList(growable: false);
    }
    return const <String>[];
  }

  // ---------------------------------------------------------------- lifetime

  DateTime? get issuedAt => _epoch('iat');

  DateTime? get notBefore => _epoch('nbf');

  DateTime? get expiresAt => _epoch('exp');

  /// True when `exp` is missing entirely — fail closed, since a token with no
  /// deadline cannot be trusted to still be valid.
  bool get hasNoExpiry => expiresAt == null;

  bool get isExpired => isExpiredAt(DateTime.now().toUtc());

  bool isExpiredAt(DateTime moment) {
    final DateTime? exp = expiresAt;
    if (exp == null) return true;
    return !moment.toUtc().isBefore(exp);
  }

  bool isNotYetValidAt(DateTime moment) {
    final DateTime? nbf = notBefore;
    if (nbf == null) return false;
    return moment.toUtc().isBefore(nbf);
  }

  bool expiresWithin(Duration window, {DateTime? now}) {
    final DateTime? exp = expiresAt;
    if (exp == null) return true;
    final DateTime moment = (now ?? DateTime.now()).toUtc();
    return !moment.add(window).isBefore(exp);
  }

  Duration? get timeToExpiry {
    final DateTime? exp = expiresAt;
    if (exp == null) return null;
    final Duration left = exp.difference(DateTime.now().toUtc());
    return left.isNegative ? Duration.zero : left;
  }

  /// Overall verdict, used by the session watchdog and asserted in tests.
  JwtCheck check({Duration refreshWindow = const Duration(minutes: 5), DateTime? now}) {
    final DateTime moment = (now ?? DateTime.now()).toUtc();
    if (hasNoExpiry) return JwtCheck.noExpiry;
    if (isNotYetValidAt(moment)) return JwtCheck.notYetValid;
    if (isExpiredAt(moment)) return JwtCheck.expired;
    if (expiresWithin(refreshWindow, now: moment)) return JwtCheck.expiringSoon;
    return JwtCheck.valid;
  }

  String? _string(String key) {
    final dynamic value = payload[key];
    if (value == null) return null;
    final String text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  /// Numeric-date claim (seconds since the Unix epoch).
  DateTime? _epoch(String key) {
    final dynamic value = payload[key];
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(
        (value * 1000).round(),
        isUtc: true,
      );
    }
    if (value is String) {
      final int? seconds = int.tryParse(value);
      if (seconds != null) {
        return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
      }
      final DateTime? parsed = DateTime.tryParse(value);
      return parsed?.toUtc();
    }
    return null;
  }

  /// Never log `raw` — it is a bearer credential.
  @override
  String toString() => 'Jwt(sub=$subject, role=$role, exp=$expiresAt, alg=$algorithm)';
}

/// Verdict for a decoded token.
enum JwtCheck {
  /// Comfortably inside its lifetime.
  valid,

  /// Still valid, but inside the refresh window.
  expiringSoon,

  /// Past `exp`.
  expired,

  /// Before `nbf`.
  notYetValid,

  /// No `exp` claim at all — treated as expired.
  noExpiry,
}
