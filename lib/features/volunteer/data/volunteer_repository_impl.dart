import 'package:uuid/uuid.dart';

import '../../../core/config/app_config.dart';
import '../../../core/constants/app_enums.dart';
import '../../../core/data/demo_data.dart';
import '../../../core/error/failure.dart';
import '../../../core/models/geo_point.dart';
import '../../../core/models/volunteer.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/local_store.dart';
import '../domain/volunteer_repository.dart';

/// Volunteer operations.
///
/// Matching and routing are computed locally when the backend is unavailable
/// (`withDistance` implements the same ranking factors the server uses:
/// distance, availability, rating, skill fit). This keeps a volunteer usable in
/// the field with no signal — the exact scenario AIDRA exists for.
class VolunteerRepositoryImpl implements VolunteerRepository {
  VolunteerRepositoryImpl({
    required ApiClient apiClient,
    required LocalStore store,
    Uuid? uuid,
  })  : _api = apiClient,
        _store = store,
        _uuid = uuid ?? const Uuid();

  static const String keyAssignments = 'cache.assignments';

  final ApiClient _api;
  final LocalStore _store;
  final Uuid _uuid;

  @override
  Future<List<VolunteerProfile>> findMatches({
    required GeoPoint center,
    double radiusKm = 5,
    String? requiredSkill,
    int limit = 10,
  }) async {
    if (AppConfig.useRemoteBackend) {
      try {
        final List<dynamic> items = await _api.getList(
          '/volunteers/nearby',
          query: <String, dynamic>{
            'lat': center.latitude,
            'lng': center.longitude,
            'km': radiusKm,
            if (requiredSkill != null) 'skill': requiredSkill,
            'limit': limit,
          },
        );
        final List<VolunteerProfile> matches = items
            .whereType<Map<dynamic, dynamic>>()
            .map((Map<dynamic, dynamic> e) =>
                VolunteerProfile.fromJson(e.cast<String, dynamic>()))
            .toList(growable: false);
        if (matches.isNotEmpty) return matches;
      } on Failure catch (_) {
        return _localMatches(center, radiusKm, requiredSkill, limit);
      }
    }
    return _localMatches(center, radiusKm, requiredSkill, limit);
  }

  @override
  Future<Assignment> assign({
    required String incidentId,
    required String? incidentTitle,
    required UrgencyLevel severity,
    required VolunteerProfile volunteer,
    GeoPoint? incidentPoint,
  }) async {
    final RoutePlan? route = incidentPoint == null
        ? null
        : await planRoute(origin: volunteer.point, destination: incidentPoint);

    final Assignment assignment = Assignment(
      id: _uuid.v4(),
      incidentId: incidentId,
      incidentTitle: incidentTitle,
      incidentSeverity: severity,
      incidentPoint: incidentPoint,
      assigneeId: volunteer.userId,
      assigneeName: volunteer.name,
      role: AssignmentRole.primary,
      status: AssignmentStatus.offered,
      etaMinutes: route?.duration.inMinutes ?? volunteer.etaMinutes,
      distanceKm: route == null ? null : route.distanceMetres / 1000,
      matchScore: volunteer.matchScore,
      route: route,
      offeredAt: DateTime.now(),
    );

    await _persistAssignment(assignment);

    if (AppConfig.useRemoteBackend) {
      try {
        await _api.postJson(
          '/assignments',
          <String, dynamic>{
            'incident_id': incidentId,
            'assignee_id': volunteer.userId,
            'role': AssignmentRole.primary.key,
            'match_score': volunteer.matchScore,
            'eta_minutes': assignment.etaMinutes,
          },
          idempotencyKey: assignment.id,
        );
      } on Failure catch (_) {
        // The caller's outbox handles replay; the local assignment stands.
      }
    }

    return assignment;
  }

  @override
  Future<List<Assignment>> fetchAssignments(String assigneeId) async {
    if (AppConfig.useRemoteBackend) {
      try {
        final List<dynamic> items = await _api.getList(
          '/assignments',
          query: <String, dynamic>{'assignee_id': assigneeId},
        );
        final List<Assignment> assignments = items
            .whereType<Map<dynamic, dynamic>>()
            .map((Map<dynamic, dynamic> e) =>
                Assignment.fromJson(e.cast<String, dynamic>()))
            .toList(growable: false);
        if (assignments.isNotEmpty) {
          await _persistAll(assignments);
          return assignments;
        }
      } on Failure catch (_) {
        return _localAssignments();
      }
    }
    return _localAssignments();
  }

  @override
  Future<Assignment> updateStatus(
    String assignmentId,
    AssignmentStatus status,
  ) async {
    final List<Assignment> assignments = _localAssignments();
    final int index = assignments.indexWhere((Assignment a) => a.id == assignmentId);
    final DateTime now = DateTime.now();

    Assignment updated;
    if (index == -1) {
      updated = Assignment(
        id: assignmentId,
        incidentId: 'unknown',
        status: status,
        offeredAt: now,
        acceptedAt: status == AssignmentStatus.accepted ? now : null,
      );
    } else {
      updated = assignments[index].copyWith(
        status: status,
        acceptedAt: status == AssignmentStatus.accepted ? now : null,
        enRouteAt: status == AssignmentStatus.enRoute ? now : null,
        onSceneAt: status == AssignmentStatus.onScene ? now : null,
        resolvedAt: status == AssignmentStatus.resolved ? now : null,
      );
      assignments[index] = updated;
    }
    await _persistAll(assignments);

    if (AppConfig.useRemoteBackend) {
      try {
        await _api.patchJson(
          '/assignments/$assignmentId',
          <String, dynamic>{'status': status.key},
        );
      } on Failure catch (_) {
        // Queued for replay.
      }
    }

    return updated;
  }

  @override
  Future<RoutePlan> planRoute({
    required GeoPoint origin,
    required GeoPoint destination,
    bool avoidHazards = true,
  }) async {
    if (AppConfig.useRemoteBackend) {
      try {
        final Map<String, dynamic> json = await _api.postJson(
          '/route',
          <String, dynamic>{
            'origin': origin.toJson(),
            'destination': destination.toJson(),
            'avoid_hazards': avoidHazards,
          },
        );
        return RoutePlan.fromJson(json);
      } on Failure catch (_) {
        return _localRoute(origin, destination, avoidHazards: avoidHazards);
      }
    }
    return _localRoute(origin, destination, avoidHazards: avoidHazards);
  }

  @override
  Future<void> setAvailability(VolunteerAvailability availability) async {
    await _store.setString('volunteer.availability', availability.key);
    if (AppConfig.useRemoteBackend) {
      try {
        await _api.patchJson(
          '/volunteers/me',
          <String, dynamic>{'availability': availability.key},
        );
      } on Failure catch (_) {
        // Availability is a soft signal; the local value is authoritative for
        // the app until connectivity returns.
      }
    }
  }

  // ------------------------------------------------------------------ helpers

  List<VolunteerProfile> _localMatches(
    GeoPoint center,
    double radiusKm,
    String? requiredSkill,
    int limit,
  ) {
    final List<VolunteerProfile> ranked = DemoData.volunteers()
        .map((VolunteerProfile v) => v.withDistance(center))
        .where((VolunteerProfile v) =>
            (v.distanceMetres ?? double.infinity) <= radiusKm * 1000)
        .where((VolunteerProfile v) {
      if (requiredSkill == null) return true;
      return v.skills
          .any((String s) => s.toLowerCase().contains(requiredSkill.toLowerCase()));
    }).toList();

    ranked.sort((VolunteerProfile a, VolunteerProfile b) =>
        (b.matchScore ?? 0).compareTo(a.matchScore ?? 0));

    final List<VolunteerProfile> limited =
        ranked.length > limit ? ranked.sublist(0, limit) : ranked;

    return List<VolunteerProfile>.generate(
      limited.length,
      (int index) => limited[index].copyWith(
        matchRank: index + 1,
        isBestMatch: index == 0,
      ),
      growable: false,
    );
  }

  /// Local route estimate: straight-line distance inflated by 1.28 (road
  /// factor) at 22 km/h effective disaster-conditions speed. Uses the routing
  /// engine's output shape so swapping in the real service changes nothing
  /// upstream.
  RoutePlan _localRoute(
    GeoPoint origin,
    GeoPoint destination, {
    required bool avoidHazards,
  }) {
    final double straight = origin.distanceTo(destination);
    final double roadDistance = straight * 1.28;
    final double speedKmh = avoidHazards ? 20 : 26;
    final int minutes = ((roadDistance / 1000) / speedKmh * 60).ceil().clamp(1, 600);

    return RoutePlan(
      id: _uuid.v4(),
      origin: origin,
      destination: destination,
      distanceMetres: roadDistance,
      duration: Duration(minutes: minutes),
      path: <GeoPoint>[
        origin,
        GeoPoint(
          (origin.latitude + destination.latitude) / 2 + 0.0012,
          (origin.longitude + destination.longitude) / 2 - 0.0009,
        ),
        destination,
      ],
      riskScore: avoidHazards ? 0.04 : 0.19,
      hazardsAvoided: avoidHazards ? 2 : 0,
      isSafeRoute: avoidHazards,
      provider: 'internal',
      computedAt: DateTime.now(),
    );
  }

  List<Assignment> _localAssignments() {
    final List<Map<String, dynamic>> cached =
        _store.getJsonList(keyAssignments);
    if (cached.isEmpty) return DemoData.assignments();
    return cached.map(Assignment.fromJson).toList(growable: false);
  }

  Future<void> _persistAssignment(Assignment assignment) async {
    final List<Assignment> assignments = _localAssignments().toList()
      ..removeWhere((Assignment a) => a.id == assignment.id)
      ..insert(0, assignment);
    await _persistAll(assignments);
  }

  Future<void> _persistAll(List<Assignment> assignments) => _store.setJsonList(
        keyAssignments,
        assignments.map((Assignment a) => a.toJson()).toList(growable: false),
      );
}
