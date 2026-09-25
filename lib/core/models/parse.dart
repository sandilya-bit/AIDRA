/// Defensive JSON coercion.
///
/// The backend may return numbers as strings, dates in two flavours, or omit
/// optional fields entirely. Every model parses through these helpers so a
/// single malformed field can never crash a screen (NFR reliability).
library;

double parseDouble(dynamic value, [double fallback = 0]) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

int parseInt(dynamic value, [int fallback = 0]) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

String parseString(dynamic value, [String fallback = '']) {
  if (value == null) return fallback;
  if (value is String) return value;
  return value.toString();
}

bool parseBool(dynamic value, [bool fallback = false]) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final String v = value.toLowerCase();
    if (v == 'true' || v == '1' || v == 'yes') return true;
    if (v == 'false' || v == '0' || v == 'no') return false;
  }
  return fallback;
}

DateTime parseDate(dynamic value, [DateTime? fallback]) {
  if (value is DateTime) return value;
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt() * 1000);
  }
  if (value is String && value.isNotEmpty) {
    final DateTime? parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed.toLocal();
  }
  return fallback ?? DateTime.now();
}

DateTime? parseDateOrNull(dynamic value) {
  if (value == null) return null;
  if (value is String && value.isEmpty) return null;
  return parseDate(value, null);
}

List<String> parseStringList(dynamic value) {
  if (value is List) {
    return value.map((dynamic e) => parseString(e)).toList(growable: false);
  }
  if (value is String && value.isNotEmpty) {
    return value.split(',').map((String e) => e.trim()).toList(growable: false);
  }
  return const <String>[];
}

Map<String, dynamic> parseMap(dynamic value) {
  if (value is Map) return value.cast<String, dynamic>();
  return const <String, dynamic>{};
}

List<Map<String, dynamic>> parseMapList(dynamic value) {
  if (value is List) {
    return value
        .whereType<Map<dynamic, dynamic>>()
        .map((Map<dynamic, dynamic> e) => e.cast<String, dynamic>())
        .toList(growable: false);
  }
  return const <Map<String, dynamic>>[];
}
