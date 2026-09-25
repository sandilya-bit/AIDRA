import 'package:aidra/core/models/geo_point.dart';
import 'package:aidra/core/utils/formatters.dart';
import 'package:aidra/core/utils/validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GeoPoint', () {
    test('returns zero distance to itself', () {
      const GeoPoint point = GeoPoint(17.3850, 78.4867);
      expect(point.distanceTo(point), lessThan(0.01));
    });

    test('uses the haversine approximation for short hops', () {
      const GeoPoint hyderabad = GeoPoint(17.3850, 78.4867);
      // ~1.11 km due north.
      const GeoPoint north = GeoPoint(17.3950, 78.4867);
      final double metres = hyderabad.distanceTo(north);
      expect(metres, greaterThan(1000));
      expect(metres, lessThan(1200));
    });

    test('reports unusable coordinates', () {
      expect(GeoPoint.unknown.isUsable, isFalse);
      expect(const GeoPoint(17.38, 78.48).isUsable, isTrue);
    });
  });

  group('Formatters', () {
    test('distance switches units at one kilometre', () {
      expect(Formatters.distance(640), '640 m');
      expect(Formatters.distance(2400), '2.4 km');
      expect(Formatters.distance(18400), '18 km');
    });

    test('route callout matches the design-system format', () {
      expect(
        Formatters.routeCallout(2800, const Duration(minutes: 8)),
        '2.8 km · 8 min',
      );
    });

    test('relative time buckets correctly', () {
      final DateTime now = DateTime(2026, 9, 25, 12, 0);
      expect(Formatters.relativeTime(now.subtract(const Duration(seconds: 10)), now: now),
          'just now');
      expect(Formatters.relativeTime(now.subtract(const Duration(minutes: 12)), now: now),
          '12 min ago');
      expect(Formatters.relativeTime(now.subtract(const Duration(hours: 5)), now: now),
          '5 h ago');
      expect(Formatters.relativeTime(now.subtract(const Duration(days: 3)), now: now),
          '3 d ago');
    });

    test('greeting keys follow the time of day', () {
      expect(Formatters.greetingKey(DateTime(2026, 9, 25, 8)), 'dash.goodMorning');
      expect(Formatters.greetingKey(DateTime(2026, 9, 25, 14)), 'dash.goodAfternoon');
      expect(Formatters.greetingKey(DateTime(2026, 9, 25, 20)), 'dash.goodEvening');
    });

    test('initials handle single and multiple names', () {
      expect(Formatters.initials('Riya Sharma'), 'RS');
      expect(Formatters.initials('Arjun'), 'A');
      expect(Formatters.initials('   '), '?');
    });

    test('compact counts abbreviate thousands', () {
      expect(Formatters.compact(156), '156');
      expect(Formatters.compact(12400), '12.4k');
      expect(Formatters.compact(2400000), '2.4M');
    });
  });

  group('Validators', () {
    test('accepts email or phone in the combined login field', () {
      expect(Validators.emailOrPhone('riya@example.com'), isNull);
      expect(Validators.emailOrPhone('+919000000000'), isNull);
      expect(Validators.emailOrPhone(''), isNotNull);
      expect(Validators.emailOrPhone('not-an-identifier'), isNotNull);
    });

    test('enforces password length', () {
      expect(Validators.password('short'), isNotNull);
      expect(Validators.password('longenough1'), isNull);
    });

    test('requires detailed report descriptions', () {
      expect(Validators.reportDescription('help'), isNotNull);
      expect(Validators.reportDescription('5 people trapped near the river'), isNull);
      expect(
        Validators.reportDescription('x' * (Validators.maxReportLength + 1)),
        isNotNull,
      );
    });
  });
}
