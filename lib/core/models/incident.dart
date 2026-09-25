import '../constants/app_enums.dart';
import 'geo_point.dart';
import 'parse.dart';

/// A consolidated incident — what the Command Center actually dispatches
/// against (PRD entity "Incidents", DB `incidents`).
class Incident {
  const Incident({
    required this.id,
    required this.code,
    required this.title,
    required this.hazardType,
    required this.severity,
    required this.status,
    required this.point,
    required this.createdAt,
    this.source = IncidentSource.report,
    this.eventId,
    this.eventName,
    this.addressText,
    this.victimsCount = 0,
    this.casualties = 0,
    this.rescuedCount = 0,
    this.needs = const <String, bool>{},
    this.isPublic = true,
    this.reportCount = 1,
    this.assignedResponders = 0,
    this.slaDueAt,
    this.firstAssignedAt,
    this.firstOnSceneAt,
    this.resolvedAt,
    this.updatedAt,
    this.updates = const <IncidentUpdate>[],
  });

  final String id;
  final String code;
  final String title;
  final String hazardType;
  final UrgencyLevel severity;
  final IncidentStatus status;
  final IncidentSource source;
  final String? eventId;
  final String? eventName;
  final GeoPoint point;
  final String? addressText;
  final int victimsCount;
  final int casualties;
  final int rescuedCount;
  final Map<String, bool> needs;
  final bool isPublic;
  final int reportCount;
  final int assignedResponders;
  final DateTime? slaDueAt;
  final DateTime? firstAssignedAt;
  final DateTime? firstOnSceneAt;
  final DateTime? resolvedAt;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final List<IncidentUpdate> updates;

  /// Active = golden-hour clock is still running.
  bool get isActive =>
      status == IncidentStatus.open ||
      status == IncidentStatus.assigned ||
      status == IncidentStatus.inProgress;

  /// Did the response beat the severity SLA? Feeds the GHRR North Star metric.
  bool get isGoldenHourMet {
    final DateTime? onScene = firstOnSceneAt;
    if (onScene == null) return false;
    return onScene.difference(createdAt) <= const Duration(minutes: 60);
  }

  Duration? get slaRemaining {
    final DateTime? due = slaDueAt;
    if (due == null) return null;
    return due.difference(DateTime.now());
  }

  bool get isSlaBreached {
    final Duration? remaining = slaRemaining;
    return remaining != null && remaining.isNegative && isActive;
  }

  /// Human-readable needs list for the incident card ("Rescue, Medical").
  List<String> get needLabels => needs.entries
      .where((MapEntry<String, bool> e) => e.value)
      .map((MapEntry<String, bool> e) =>
          e.key.substring(0, 1).toUpperCase() + e.key.substring(1))
      .toList(growable: false);

  static Incident fromJson(Map<String, dynamic> json) => Incident(
        id: parseString(json['id'], 'i-${json.hashCode}'),
        code: parseString(json['incident_code'], 'INC-0000'),
        title: parseString(json['title'], 'Unnamed incident'),
        hazardType: parseString(json['hazard_type'], 'other'),
        severity: enumFromKey(
          UrgencyLevel.values,
          json['severity']?.toString(),
          UrgencyLevel.medium,
        ),
        status: enumFromKey(
          IncidentStatus.values,
          json['status']?.toString(),
          IncidentStatus.open,
        ),
        source: enumFromKey(
          IncidentSource.values,
          json['source']?.toString(),
          IncidentSource.report,
        ),
        eventId: json['event_id']?.toString(),
        eventName: json['event_name']?.toString(),
        point: GeoPoint(
          parseDouble(json['latitude']),
          parseDouble(json['longitude']),
        ),
        addressText: json['address_text']?.toString(),
        victimsCount: parseInt(json['victims_count']),
        casualties: parseInt(json['casualties']),
        rescuedCount: parseInt(json['rescued_count']),
        needs: parseMap(json['needs']).map(
          (String key, dynamic value) =>
              MapEntry<String, bool>(key, parseBool(value)),
        ),
        isPublic: parseBool(json['is_public'], true),
        reportCount: parseInt(json['report_count'], 1),
        assignedResponders: parseInt(json['assigned_responders']),
        slaDueAt: parseDateOrNull(json['sla_due_at']),
        firstAssignedAt: parseDateOrNull(json['first_assigned_at']),
        firstOnSceneAt: parseDateOrNull(json['first_on_scene_at']),
        resolvedAt: parseDateOrNull(json['resolved_at']),
        createdAt: parseDate(json['created_at']),
        updatedAt: parseDateOrNull(json['updated_at']),
        updates: parseMapList(json['updates'])
            .map(IncidentUpdate.fromJson)
            .toList(growable: false),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'incident_code': code,
        'title': title,
        'hazard_type': hazardType,
        'severity': severity.key,
        'status': status.key,
        'source': source.key,
        if (eventId != null) 'event_id': eventId,
        'latitude': point.latitude,
        'longitude': point.longitude,
        if (addressText != null) 'address_text': addressText,
        'victims_count': victimsCount,
        'casualties': casualties,
        'rescued_count': rescuedCount,
        'needs': needs,
        'is_public': isPublic,
        'report_count': reportCount,
        'assigned_responders': assignedResponders,
        if (slaDueAt != null) 'sla_due_at': slaDueAt!.toIso8601String(),
        if (firstAssignedAt != null)
          'first_assigned_at': firstAssignedAt!.toIso8601String(),
        if (firstOnSceneAt != null)
          'first_on_scene_at': firstOnSceneAt!.toIso8601String(),
        if (resolvedAt != null) 'resolved_at': resolvedAt!.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
      };
}

enum IncidentSource { report, authority, partnerApi, aiCluster, sensor }

/// One row of the incident timeline (DB `incident_updates`).
class IncidentUpdate {
  const IncidentUpdate({
    required this.id,
    required this.type,
    required this.createdAt,
    this.fromStatus,
    this.toStatus,
    this.actorName,
    this.note,
  });

  final String id;
  final String type;
  final IncidentStatus? fromStatus;
  final IncidentStatus? toStatus;
  final String? actorName;
  final String? note;
  final DateTime createdAt;

  static IncidentUpdate fromJson(Map<String, dynamic> json) => IncidentUpdate(
        id: parseString(json['id'], 'up-${json.hashCode}'),
        type: parseString(json['update_type'], 'note'),
        fromStatus: json['from_status'] == null
            ? null
            : enumFromKey(IncidentStatus.values, json['from_status']?.toString(),
                IncidentStatus.open),
        toStatus: json['to_status'] == null
            ? null
            : enumFromKey(IncidentStatus.values, json['to_status']?.toString(),
                IncidentStatus.open),
        actorName: json['actor_name']?.toString(),
        note: json['note']?.toString(),
        createdAt: parseDate(json['created_at']),
      );
}

/// Cluster/event raised when many high-severity reports converge
/// (PRD Volume II §4.2).
class DisasterEvent {
  const DisasterEvent({
    required this.id,
    required this.code,
    required this.name,
    required this.hazardType,
    required this.incidentCount,
    this.eventClass = 'watch',
    this.playbook,
    this.startedAt,
    this.populationAffected,
  });

  final String id;
  final String code;
  final String name;
  final String hazardType;
  final int incidentCount;
  final String eventClass; // watch | amber | red
  final String? playbook; // flood | cyclone | earthquake | wildfire | landslide
  final DateTime? startedAt;
  final int? populationAffected;

  static DisasterEvent fromJson(Map<String, dynamic> json) => DisasterEvent(
        id: parseString(json['id'], 'e-${json.hashCode}'),
        code: parseString(json['event_code'], 'EVT-0000'),
        name: parseString(json['name'], 'Active event'),
        hazardType: parseString(json['hazard_type'], 'other'),
        incidentCount: parseInt(json['incident_count']),
        eventClass: parseString(json['event_class'], 'watch'),
        playbook: json['playbook']?.toString(),
        startedAt: parseDateOrNull(json['started_at']),
        populationAffected: json['population_affected'] == null
            ? null
            : parseInt(json['population_affected']),
      );
}

/// Dashboard KPIs — exactly the four cards on the Command Center
/// (design system §5).
class IncidentKpis {
  const IncidentKpis({
    required this.activeIncidents,
    required this.peopleInNeed,
    required this.volunteersActive,
    required this.resourcesAvailable,
    this.incidentDelta = 0,
    this.peopleDeltaPercent = 0,
    this.volunteerDeltaPercent = 0,
    this.resourceDelta = 0,
    this.goldenHourRatePercent,
  });

  final int activeIncidents;
  final int peopleInNeed;
  final int volunteersActive;
  final int resourcesAvailable;
  final int incidentDelta;
  final double peopleDeltaPercent;
  final double volunteerDeltaPercent;
  final int resourceDelta;

  /// North Star (PRD Volume II §1.4).
  final double? goldenHourRatePercent;

  static IncidentKpis fromJson(Map<String, dynamic> json) => IncidentKpis(
        activeIncidents: parseInt(json['active_incidents']),
        peopleInNeed: parseInt(json['people_in_need']),
        volunteersActive: parseInt(json['volunteers_active']),
        resourcesAvailable: parseInt(json['resources_available']),
        incidentDelta: parseInt(json['incident_delta']),
        peopleDeltaPercent: parseDouble(json['people_delta_percent']),
        volunteerDeltaPercent: parseDouble(json['volunteer_delta_percent']),
        resourceDelta: parseInt(json['resource_delta']),
        goldenHourRatePercent: json['ghrr_percent'] == null
            ? null
            : parseDouble(json['ghrr_percent']),
      );

  /// Offline/demo fallback derived from the live incident list.
  factory IncidentKpis.fromIncidents(List<Incident> incidents) {
    final int active = incidents.where((Incident i) => i.isActive).length;
    final int people = incidents
        .where((Incident i) => i.isActive)
        .fold<int>(0, (int sum, Incident i) => sum + i.victimsCount);
    final int responders = incidents.fold<int>(
      0,
      (int sum, Incident i) => sum + i.assignedResponders,
    );
    final int goldenWindow =
        incidents.where((Incident i) => i.severity.isEmergency).length;
    final int goldenMet = incidents
        .where((Incident i) => i.severity.isEmergency && i.isGoldenHourMet)
        .length;
    return IncidentKpis(
      activeIncidents: active,
      peopleInNeed: people,
      volunteersActive: responders,
      resourcesAvailable: incidents.fold<int>(
        0,
        (int sum, Incident i) => sum + i.needLabels.length,
      ),
      goldenHourRatePercent:
          goldenWindow == 0 ? null : (goldenMet / goldenWindow) * 100,
    );
  }
}
