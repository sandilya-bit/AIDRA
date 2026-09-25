import '../constants/app_enums.dart';
import 'geo_point.dart';
import 'parse.dart';

/// A ranked candidate returned by the matching engine (PRD Volume II §5.B).
class VolunteerProfile {
  const VolunteerProfile({
    required this.id,
    required this.userId,
    required this.name,
    required this.skills,
    required this.availability,
    required this.point,
    this.avatarUrl,
    this.organizationName,
    this.rating = 0,
    this.completedAssignments = 0,
    this.languages = const <String>['en'],
    this.hasVehicle = false,
    this.distanceMetres,
    this.etaMinutes,
    this.matchScore,
    this.matchRank,
    this.isBestMatch = false,
    this.isVerified = false,
    this.bloodGroup,
  });

  final String id;
  final String userId;
  final String name;
  final String? avatarUrl;
  final String? organizationName;
  final List<String> skills;
  final List<String> languages;
  final VolunteerAvailability availability;
  final GeoPoint point;
  final double rating;
  final int completedAssignments;
  final bool hasVehicle;
  final bool isVerified;
  final String? bloodGroup;

  /// Server-computed match metrics; recomputed client-side when offline so the
  /// screen is never empty (see [withDistance]).
  final double? distanceMetres;
  final int? etaMinutes;
  final double? matchScore;
  final int? matchRank;
  final bool isBestMatch;

  String get distanceLabel =>
      distanceMetres == null ? '—' : _metres(distanceMetres!);

  static String _metres(double metres) {
    if (metres < 1000) return '${metres.round()} m';
    return '${(metres / 1000).toStringAsFixed(1)} km';
  }

  /// Client-side ranking fallback: distance + skill fit + availability.
  VolunteerProfile withDistance(GeoPoint from) {
    final double metres = point.distanceTo(from);
    // ~22 km/h effective speed in disaster conditions (routing engine prior).
    final int eta = (metres / 1000 / 22 * 60).ceil().clamp(1, 600);
    final double availabilityBoost =
        availability == VolunteerAvailability.available ? 0.25 : 0.0;
    final double distanceScore = (1 - (metres / 20000)).clamp(0.0, 1.0);
    final double score =
        (distanceScore * 0.55 + availabilityBoost + (rating / 5) * 0.2)
            .clamp(0.0, 1.0);
    return VolunteerProfile(
      id: id,
      userId: userId,
      name: name,
      avatarUrl: avatarUrl,
      organizationName: organizationName,
      skills: skills,
      languages: languages,
      availability: availability,
      point: point,
      rating: rating,
      completedAssignments: completedAssignments,
      hasVehicle: hasVehicle,
      isVerified: isVerified,
      bloodGroup: bloodGroup,
      distanceMetres: metres,
      etaMinutes: eta,
      matchScore: score,
      matchRank: matchRank,
    );
  }

  VolunteerProfile copyWith({
    VolunteerAvailability? availability,
    double? distanceMetres,
    int? etaMinutes,
    double? matchScore,
    int? matchRank,
    bool? isBestMatch,
  }) {
    return VolunteerProfile(
      id: id,
      userId: userId,
      name: name,
      avatarUrl: avatarUrl,
      organizationName: organizationName,
      skills: skills,
      languages: languages,
      availability: availability ?? this.availability,
      point: point,
      rating: rating,
      completedAssignments: completedAssignments,
      hasVehicle: hasVehicle,
      isVerified: isVerified,
      bloodGroup: bloodGroup,
      distanceMetres: distanceMetres ?? this.distanceMetres,
      etaMinutes: etaMinutes ?? this.etaMinutes,
      matchScore: matchScore ?? this.matchScore,
      matchRank: matchRank ?? this.matchRank,
      isBestMatch: isBestMatch ?? this.isBestMatch,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'user_id': userId,
        'name': name,
        'avatar_url': avatarUrl,
        'organization_name': organizationName,
        'skills': skills,
        'languages': languages,
        'availability': availability.key,
        'latitude': point.latitude,
        'longitude': point.longitude,
        'rating': rating,
        'completed_assignments': completedAssignments,
        'has_vehicle': hasVehicle,
        'is_verified': isVerified,
        'blood_group': bloodGroup,
        if (distanceMetres != null) 'distance_m': distanceMetres,
        if (etaMinutes != null) 'eta_minutes': etaMinutes,
        if (matchScore != null) 'match_score': matchScore,
        if (matchRank != null) 'match_rank': matchRank,
      };

  static VolunteerProfile fromJson(Map<String, dynamic> json) => VolunteerProfile(
        id: parseString(json['id'] ?? json['user_id'], 'v-${json.hashCode}'),
        userId: parseString(json['user_id'] ?? json['id']),
        name: parseString(json['name'] ?? json['full_name'], 'Volunteer'),
        avatarUrl: json['avatar_url']?.toString(),
        organizationName: json['organization_name']?.toString(),
        skills: parseStringList(json['skills']),
        languages: parseStringList(json['languages']).isEmpty
            ? const <String>['en']
            : parseStringList(json['languages']),
        availability: enumFromKey(
          VolunteerAvailability.values,
          json['availability']?.toString(),
          VolunteerAvailability.unavailable,
        ),
        point: GeoPoint(
          parseDouble(json['latitude']),
          parseDouble(json['longitude']),
        ),
        rating: parseDouble(json['rating']),
        completedAssignments: parseInt(json['completed_assignments']),
        hasVehicle: parseBool(json['has_vehicle']),
        isVerified: parseBool(json['is_verified']),
        bloodGroup: json['blood_group']?.toString(),
        distanceMetres: json['distance_m'] == null ? null : parseDouble(json['distance_m']),
        etaMinutes: json['eta_minutes'] == null ? null : parseInt(json['eta_minutes']),
        matchScore: json['match_score'] == null ? null : parseDouble(json['match_score']),
        matchRank: json['match_rank'] == null ? null : parseInt(json['match_rank']),
      );
}

/// Safe-route recommendation from the Route Intelligence Engine
/// (PRD Volume II §5.C).
class RoutePlan {
  const RoutePlan({
    required this.id,
    required this.origin,
    required this.destination,
    required this.distanceMetres,
    required this.duration,
    this.path = const <GeoPoint>[],
    this.riskScore = 0,
    this.hazardsAvoided = 0,
    this.isSafeRoute = true,
    this.provider = 'internal',
    this.computedAt,
  });

  final String id;
  final GeoPoint origin;
  final GeoPoint destination;
  final double distanceMetres;
  final Duration duration;
  final List<GeoPoint> path;
  final double riskScore;
  final int hazardsAvoided;
  final bool isSafeRoute;
  final String provider;
  final DateTime? computedAt;

  String get callout =>
      '${(distanceMetres / 1000).toStringAsFixed(1)} km · ${duration.inMinutes} min';

  static RoutePlan fromJson(Map<String, dynamic> json) => RoutePlan(
        id: parseString(json['id'], 'rt-${json.hashCode}'),
        origin: GeoPoint.fromJson(parseMap(json['origin'])),
        destination: GeoPoint.fromJson(parseMap(json['destination'])),
        distanceMetres: parseDouble(json['distance_m']),
        duration: Duration(seconds: parseInt(json['duration_s'])),
        riskScore: parseDouble(json['risk_score']),
        hazardsAvoided: parseInt(json['hazards_avoided']),
        isSafeRoute: parseBool(json['is_safe_route'], true),
        provider: parseString(json['provider'], 'internal'),
        computedAt: parseDateOrNull(json['computed_at']),
      );
}

/// Dispatch record linking an incident to a volunteer or an org team
/// (DB `assignments`).
class Assignment {
  const Assignment({
    required this.id,
    required this.incidentId,
    required this.status,
    required this.offeredAt,
    this.incidentTitle,
    this.incidentSeverity = UrgencyLevel.medium,
    this.assigneeId,
    this.assigneeName,
    this.assigneeOrgId,
    this.assigneeOrgName,
    this.role = AssignmentRole.primary,
    this.incidentPoint,
    this.etaMinutes,
    this.distanceKm,
    this.matchScore,
    this.route,
    this.acceptedAt,
    this.enRouteAt,
    this.onSceneAt,
    this.resolvedAt,
    this.note,
  });

  final String id;
  final String incidentId;
  final String? incidentTitle;
  final UrgencyLevel incidentSeverity;
  final GeoPoint? incidentPoint;
  final String? assigneeId;
  final String? assigneeName;
  final String? assigneeOrgId;
  final String? assigneeOrgName;
  final AssignmentRole role;
  final AssignmentStatus status;
  final int? etaMinutes;
  final double? distanceKm;
  final double? matchScore;
  final RoutePlan? route;
  final DateTime offeredAt;
  final DateTime? acceptedAt;
  final DateTime? enRouteAt;
  final DateTime? onSceneAt;
  final DateTime? resolvedAt;
  final String? note;

  bool get isActive => status.isActive;

  Assignment copyWith({
    AssignmentStatus? status,
    DateTime? acceptedAt,
    DateTime? enRouteAt,
    DateTime? onSceneAt,
    DateTime? resolvedAt,
    RoutePlan? route,
  }) {
    return Assignment(
      id: id,
      incidentId: incidentId,
      incidentTitle: incidentTitle,
      incidentSeverity: incidentSeverity,
      incidentPoint: incidentPoint,
      assigneeId: assigneeId,
      assigneeName: assigneeName,
      assigneeOrgId: assigneeOrgId,
      assigneeOrgName: assigneeOrgName,
      role: role,
      status: status ?? this.status,
      etaMinutes: etaMinutes,
      distanceKm: distanceKm,
      matchScore: matchScore,
      route: route ?? this.route,
      offeredAt: offeredAt,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      enRouteAt: enRouteAt ?? this.enRouteAt,
      onSceneAt: onSceneAt ?? this.onSceneAt,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      note: note,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'incident_id': incidentId,
        'incident_title': incidentTitle,
        'incident_severity': incidentSeverity.key,
        'assignee_id': assigneeId,
        'assignee_org_id': assigneeOrgId,
        'role': role.key,
        'status': status.key,
        'eta_minutes': etaMinutes,
        'distance_km': distanceKm,
        'match_score': matchScore,
        'offered_at': offeredAt.toIso8601String(),
        if (acceptedAt != null) 'accepted_at': acceptedAt!.toIso8601String(),
        if (enRouteAt != null) 'en_route_at': enRouteAt!.toIso8601String(),
        if (onSceneAt != null) 'on_scene_at': onSceneAt!.toIso8601String(),
        if (resolvedAt != null) 'resolved_at': resolvedAt!.toIso8601String(),
        if (note != null) 'notes': note,
      };

  static Assignment fromJson(Map<String, dynamic> json) => Assignment(
        id: parseString(json['id'], 'a-${json.hashCode}'),
        incidentId: parseString(json['incident_id']),
        incidentTitle: json['incident_title']?.toString(),
        incidentSeverity: enumFromKey(
          UrgencyLevel.values,
          json['incident_severity']?.toString(),
          UrgencyLevel.medium,
        ),
        incidentPoint: json['incident_point'] == null
            ? null
            : GeoPoint.fromJson(parseMap(json['incident_point'])),
        assigneeId: json['assignee_id']?.toString(),
        assigneeName: json['assignee_name']?.toString(),
        assigneeOrgId: json['assignee_org_id']?.toString(),
        assigneeOrgName: json['assignee_org_name']?.toString(),
        role: enumFromKey(
          AssignmentRole.values,
          json['role']?.toString(),
          AssignmentRole.primary,
        ),
        status: enumFromKey(
          AssignmentStatus.values,
          json['status']?.toString(),
          AssignmentStatus.offered,
        ),
        etaMinutes: json['eta_minutes'] == null ? null : parseInt(json['eta_minutes']),
        distanceKm: json['distance_km'] == null ? null : parseDouble(json['distance_km']),
        matchScore: json['match_score'] == null ? null : parseDouble(json['match_score']),
        offeredAt: parseDate(json['offered_at']),
        acceptedAt: parseDateOrNull(json['accepted_at']),
        enRouteAt: parseDateOrNull(json['en_route_at']),
        onSceneAt: parseDateOrNull(json['on_scene_at']),
        resolvedAt: parseDateOrNull(json['resolved_at']),
        note: json['notes']?.toString(),
      );
}

enum AssignmentRole { primary, supporting, standby }

extension AssignmentRoleX on AssignmentRole {
  String get key => name;
  String get label => switch (this) {
        AssignmentRole.primary => 'Primary',
        AssignmentRole.supporting => 'Supporting',
        AssignmentRole.standby => 'Standby',
      };
}
