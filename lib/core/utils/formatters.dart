/// Formatting helpers.
///
/// Intentionally dependency-free (no `intl`) to avoid SDK-pinned version
/// conflicts; unit-safe and locale-neutral. Swap for `intl` when the app ships
/// to stores and needs locale-correct date/number skeletons.
abstract final class Formatters {
  static const List<String> _months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// "just now", "4 min ago", "2 h ago", "3 d ago".
  static String relativeTime(DateTime time, {DateTime? now}) {
    final DateTime reference = now ?? DateTime.now();
    final Duration diff = reference.difference(time);
    if (diff.inSeconds < 45) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    if (diff.inDays < 7) return '${diff.inDays} d ago';
    return shortDate(time);
  }

  /// "25 Sep", "25 Sep 2026".
  static String shortDate(DateTime time, {bool withYear = false}) {
    final String base = '${time.day} ${_months[time.month - 1]}';
    return withYear ? '$base ${time.year}' : base;
  }

  /// "12:05" (24 h) — incidents are timestamped precisely, never ambiguously.
  static String clock(DateTime time) {
    final String hh = time.hour.toString().padLeft(2, '0');
    final String mm = time.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  /// "25 Sep · 12:05"
  static String dateTime(DateTime time) => '${shortDate(time)} · ${clock(time)}';

  /// "600 m" / "2.4 km".
  static String distance(double metres) {
    if (metres < 1000) return '${metres.round()} m';
    final double km = metres / 1000;
    return '${km.toStringAsFixed(km < 10 ? 1 : 0)} km';
  }

  /// "2.8 km · 8 min" — the exact route-callout format from the design system.
  static String routeCallout(double metres, Duration eta) =>
      '${distance(metres)} · ${eta.inMinutes} min';

  /// "156", "12.4k".
  static String compact(int value) {
    if (value < 1000) return value.toString();
    if (value < 1000000) {
      final double k = value / 1000;
      return '${k.toStringAsFixed(k < 10 ? 1 : 0)}k';
    }
    final double m = value / 1000000;
    return '${m.toStringAsFixed(1)}M';
  }

  /// Percentage with one decimal, e.g. "65.4%".
  static String percent(double value) => '${value.toStringAsFixed(1)}%';

  /// Time-of-day aware greeting key.
  static String greetingKey(DateTime time) {
    if (time.hour < 12) return 'dash.goodMorning';
    if (time.hour < 17) return 'dash.goodAfternoon';
    return 'dash.goodEvening';
  }

  /// Initials for avatar fallbacks: "Riya Sharma" → "RS".
  static String initials(String name) {
    final List<String> parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((String p) => p.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return _firstLetter(parts.first);
    return '${_firstLetter(parts.first)}${_firstLetter(parts.last)}';
  }

  static String _firstLetter(String word) =>
      word.isEmpty ? '' : word.substring(0, 1).toUpperCase();
}
