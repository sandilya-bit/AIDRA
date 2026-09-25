import '../constants/app_enums.dart';
import 'geo_point.dart';
import 'parse.dart';

/// Hospital with live capacity (FR-401/402, DB `hospitals`).
class Hospital {
  const Hospital({
    required this.id,
    required this.name,
    required this.point,
    required this.bedsTotal,
    required this.bedsAvailable,
    required this.icuTotal,
    required this.icuAvailable,
    this.organizationId,
    this.organizationName,
    this.addressText,
    this.contactPhone,
    this.traumaLevel,
    this.oxygenUnits = 0,
    this.ventilatorsAvailable = 0,
    this.bloodInventory = const <String, int>{},
    this.specialties = const <String>[],
    this.status = 'operational',
    this.isAccepting = true,
    this.capacityUpdatedAt,
    this.distanceMetres,
    this.inboundCasualties = 0,
    this.etaMinutes,
  });

  final String id;
  final String name;
  final String? organizationId;
  final String? organizationName;
  final GeoPoint point;
  final String? addressText;
  final String? contactPhone;
  final int? traumaLevel;
  final int bedsTotal;
  final int bedsAvailable;
  final int icuTotal;
  final int icuAvailable;
  final int oxygenUnits;
  final int ventilatorsAvailable;
  final Map<String, int> bloodInventory;
  final List<String> specialties;
  final String status; // operational | diversion | full | closed
  final bool isAccepting;
  final DateTime? capacityUpdatedAt;
  final double? distanceMetres;
  final int inboundCasualties;
  final int? etaMinutes;

  bool get isFull => bedsAvailable <= 0 || icuAvailable <= 0 || !isAccepting;

  double get bedOccupancyPercent =>
      bedsTotal == 0 ? 0 : ((bedsTotal - bedsAvailable) / bedsTotal) * 100;

  double get icuOccupancyPercent =>
      icuTotal == 0 ? 0 : ((icuTotal - icuAvailable) / icuTotal) * 100;

  /// KPI §3.3: capacity data is "fresh" when updated within 30 minutes.
  bool get isCapacityFresh {
    final DateTime? updated = capacityUpdatedAt;
    if (updated == null) return false;
    return DateTime.now().difference(updated) <= const Duration(minutes: 30);
  }

  int get totalBloodUnits =>
      bloodInventory.values.fold<int>(0, (int sum, int units) => sum + units);

  String get statusLabel => switch (status) {
        'operational' => 'Operational',
        'diversion' => 'On diversion',
        'full' => 'At capacity',
        'closed' => 'Closed',
        _ => status,
      };

  static Hospital fromJson(Map<String, dynamic> json) => Hospital(
        id: parseString(json['id'], 'h-${json.hashCode}'),
        name: parseString(json['name'], 'Hospital'),
        organizationId: json['organization_id']?.toString(),
        organizationName: json['organization_name']?.toString(),
        point: GeoPoint(
          parseDouble(json['latitude']),
          parseDouble(json['longitude']),
        ),
        addressText: json['address_text']?.toString(),
        contactPhone: json['contact_phone']?.toString(),
        traumaLevel: json['trauma_level'] == null ? null : parseInt(json['trauma_level']),
        bedsTotal: parseInt(json['beds_total']),
        bedsAvailable: parseInt(json['beds_available']),
        icuTotal: parseInt(json['icu_total']),
        icuAvailable: parseInt(json['icu_available']),
        oxygenUnits: parseInt(json['oxygen_units']),
        ventilatorsAvailable: parseInt(json['ventilators_available']),
        bloodInventory: parseMap(json['blood_inventory']).map(
          (String key, dynamic value) =>
              MapEntry<String, int>(key, parseInt(value)),
        ),
        specialties: parseStringList(json['specialties']),
        status: parseString(json['status'], 'operational'),
        isAccepting: parseBool(json['is_accepting'], true),
        capacityUpdatedAt: parseDateOrNull(json['capacity_updated_at']),
        distanceMetres: json['distance_m'] == null ? null : parseDouble(json['distance_m']),
        inboundCasualties: parseInt(json['inbound_casualties']),
        etaMinutes: json['eta_minutes'] == null ? null : parseInt(json['eta_minutes']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'organization_id': organizationId,
        'organization_name': organizationName,
        'latitude': point.latitude,
        'longitude': point.longitude,
        'address_text': addressText,
        'contact_phone': contactPhone,
        'trauma_level': traumaLevel,
        'beds_total': bedsTotal,
        'beds_available': bedsAvailable,
        'icu_total': icuTotal,
        'icu_available': icuAvailable,
        'oxygen_units': oxygenUnits,
        'ventilators_available': ventilatorsAvailable,
        'blood_inventory': bloodInventory,
        'specialties': specialties,
        'status': status,
        'is_accepting': isAccepting,
        if (capacityUpdatedAt != null)
          'capacity_updated_at': capacityUpdatedAt!.toIso8601String(),
        'inbound_casualties': inboundCasualties,
      };
}

/// Casualty pre-alert sent ahead of patient arrival (FR-402).
class CasualtyPreAlert {
  const CasualtyPreAlert({
    required this.id,
    required this.hospitalId,
    required this.hospitalName,
    required this.incidentId,
    required this.patientCount,
    required this.sentAt,
    this.incidentTitle,
    this.severity = UrgencyLevel.high,
    this.triageTags = const <String, int>{},
    this.conditionSummary,
    this.etaAt,
    this.status = 'sent',
    this.acknowledgedAt,
  });

  final String id;
  final String hospitalId;
  final String hospitalName;
  final String incidentId;
  final String? incidentTitle;
  final UrgencyLevel severity;
  final int patientCount;
  final Map<String, int> triageTags;
  final String? conditionSummary;
  final DateTime? etaAt;
  final String status; // sent | acknowledged | arrived | cancelled | redirected
  final DateTime sentAt;
  final DateTime? acknowledgedAt;

  bool get isAcknowledged => acknowledgedAt != null || status != 'sent';

  /// KPI: pre-alert acknowledge SLA is 5 minutes.
  bool get isAckSlaBreached =>
      !isAcknowledged &&
      DateTime.now().difference(sentAt) > const Duration(minutes: 5);

  Duration? get etaIn {
    final DateTime? eta = etaAt;
    if (eta == null) return null;
    return eta.difference(DateTime.now());
  }

  CasualtyPreAlert copyWith({String? status, DateTime? acknowledgedAt}) =>
      CasualtyPreAlert(
        id: id,
        hospitalId: hospitalId,
        hospitalName: hospitalName,
        incidentId: incidentId,
        incidentTitle: incidentTitle,
        severity: severity,
        patientCount: patientCount,
        triageTags: triageTags,
        conditionSummary: conditionSummary,
        etaAt: etaAt,
        status: status ?? this.status,
        sentAt: sentAt,
        acknowledgedAt: acknowledgedAt ?? this.acknowledgedAt,
      );

  static CasualtyPreAlert fromJson(Map<String, dynamic> json) => CasualtyPreAlert(
        id: parseString(json['id'], 'pa-${json.hashCode}'),
        hospitalId: parseString(json['hospital_id']),
        hospitalName: parseString(json['hospital_name'], 'Hospital'),
        incidentId: parseString(json['incident_id']),
        incidentTitle: json['incident_title']?.toString(),
        severity: enumFromKey(
          UrgencyLevel.values,
          json['severity']?.toString(),
          UrgencyLevel.high,
        ),
        patientCount: parseInt(json['patient_count'], 1),
        triageTags: parseMap(json['triage_tags']).map(
          (String key, dynamic value) => MapEntry<String, int>(key, parseInt(value)),
        ),
        conditionSummary: json['condition_summary']?.toString(),
        etaAt: parseDateOrNull(json['eta_at']),
        status: parseString(json['status'], 'sent'),
        sentAt: parseDate(json['created_at']),
        acknowledgedAt: parseDateOrNull(json['acknowledged_at']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'hospital_id': hospitalId,
        'incident_id': incidentId,
        'patient_count': patientCount,
        'triage_tags': triageTags,
        'condition_summary': conditionSummary,
        if (etaAt != null) 'eta_at': etaAt!.toIso8601String(),
        'status': status,
        'created_at': sentAt.toIso8601String(),
      };
}
