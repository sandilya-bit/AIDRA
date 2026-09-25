import 'package:aidra/core/constants/app_enums.dart';
import 'package:aidra/core/models/emergency_report.dart';
import 'package:aidra/core/models/geo_point.dart';
import 'package:aidra/core/models/incident.dart';
import 'package:flutter_test/flutter_test.dart';

EmergencyReport _report({
  UrgencyLevel user = UrgencyLevel.medium,
  UrgencyLevel? ai,
  double? confidence,
}) {
  return EmergencyReport(
    id: 'r1',
    code: 'AID-2026-000001',
    reporterId: 'u1',
    inputType: ReportInputType.text,
    description: '5 people trapped in a building near the river.',
    point: const GeoPoint(17.385, 78.4867),
    urgencyUser: user,
    urgencyAi: ai,
    aiConfidence: confidence,
    status: ReportStatus.submitted,
    createdAt: DateTime.now(),
  );
}

Incident _incident({
  required UrgencyLevel severity,
  required DateTime createdAt,
  DateTime? onSceneAt,
  int victims = 2,
}) {
  return Incident(
    id: 'i-${severity.name}',
    code: 'INC-1',
    title: 'Test incident',
    hazardType: 'flood',
    severity: severity,
    status: IncidentStatus.inProgress,
    point: const GeoPoint(17.385, 78.4867),
    createdAt: createdAt,
    firstOnSceneAt: onSceneAt,
    victimsCount: victims,
    assignedResponders: 1,
  );
}

void main() {
  group('Severity framework (L1–L4)', () {
    test('maps urgency to the documented response targets', () {
      expect(UrgencyLevel.low.responseTarget, const Duration(hours: 4));
      expect(UrgencyLevel.medium.responseTarget, const Duration(minutes: 30));
      expect(UrgencyLevel.high.responseTarget, const Duration(minutes: 10));
      expect(UrgencyLevel.critical.responseTarget, const Duration(minutes: 5));
    });

    test('high and critical are treated as emergencies', () {
      expect(UrgencyLevel.high.isEmergency, isTrue);
      expect(UrgencyLevel.critical.isEmergency, isTrue);
      expect(UrgencyLevel.medium.isEmergency, isFalse);
    });
  });

  group('AI triage authority', () {
    test('trusts a confident AI verdict over the user selection', () {
      final EmergencyReport report = _report(
        user: UrgencyLevel.medium,
        ai: UrgencyLevel.critical,
        confidence: 0.91,
      );
      expect(report.effectiveUrgency, UrgencyLevel.critical);
    });

    test('keeps the human level when the model is unsure', () {
      final EmergencyReport report = _report(
        user: UrgencyLevel.high,
        ai: UrgencyLevel.low,
        confidence: 0.42,
      );
      expect(report.effectiveUrgency, UrgencyLevel.high);
    });

    test('flags a two-level disagreement for verification (AC-T3)', () {
      final EmergencyReport report = _report(
        user: UrgencyLevel.low,
        ai: UrgencyLevel.critical,
        confidence: 0.88,
      );
      expect(report.needsHumanVerification, isTrue);
    });

    test('does not flag agreement', () {
      final EmergencyReport report = _report(
        user: UrgencyLevel.high,
        ai: UrgencyLevel.high,
        confidence: 0.93,
      );
      expect(report.needsHumanVerification, isFalse);
    });
  });

  group('North Star metric (golden-hour rescue rate)', () {
    test('counts a response inside 60 minutes as met', () {
      final DateTime created = DateTime(2026, 9, 25, 10, 0);
      final Incident incident = _incident(
        severity: UrgencyLevel.high,
        createdAt: created,
        onSceneAt: created.add(const Duration(minutes: 46)),
      );
      expect(incident.isGoldenHourMet, isTrue);
    });

    test('counts a late response as missed', () {
      final DateTime created = DateTime(2026, 9, 25, 10, 0);
      final Incident incident = _incident(
        severity: UrgencyLevel.critical,
        createdAt: created,
        onSceneAt: created.add(const Duration(minutes: 92)),
      );
      expect(incident.isGoldenHourMet, isFalse);
    });

    test('derives GHRR from the incident feed', () {
      final DateTime created = DateTime(2026, 9, 25, 10, 0);
      final List<Incident> incidents = <Incident>[
        _incident(
          severity: UrgencyLevel.high,
          createdAt: created,
          onSceneAt: created.add(const Duration(minutes: 30)),
          victims: 5,
        ),
        _incident(
          severity: UrgencyLevel.critical,
          createdAt: created,
          onSceneAt: created.add(const Duration(minutes: 90)),
          victims: 3,
        ),
        _incident(
          severity: UrgencyLevel.low,
          createdAt: created,
          onSceneAt: created.add(const Duration(hours: 3)),
          victims: 1,
        ),
      ];

      final IncidentKpis kpis = IncidentKpis.fromIncidents(incidents);
      expect(kpis.activeIncidents, 3);
      expect(kpis.peopleInNeed, 9);
      // Only the L3/L4 incidents count toward the golden-hour denominator.
      expect(kpis.goldenHourRatePercent, closeTo(50, 0.01));
    });
  });

  group('Incident SLA state', () {
    test('flags a breach while the incident is still active', () {
      final Incident incident = Incident(
        id: 'i1',
        code: 'INC-1',
        title: 'Breached',
        hazardType: 'fire',
        severity: UrgencyLevel.critical,
        status: IncidentStatus.assigned,
        point: const GeoPoint(17.385, 78.4867),
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
        slaDueAt: DateTime.now().subtract(const Duration(minutes: 4)),
      );
      expect(incident.isSlaBreached, isTrue);
    });

    test('does not flag a resolved incident', () {
      final Incident incident = Incident(
        id: 'i2',
        code: 'INC-2',
        title: 'Resolved',
        hazardType: 'fire',
        severity: UrgencyLevel.critical,
        status: IncidentStatus.resolved,
        point: const GeoPoint(17.385, 78.4867),
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
        slaDueAt: DateTime.now().subtract(const Duration(hours: 1)),
      );
      expect(incident.isSlaBreached, isFalse);
    });
  });
}
