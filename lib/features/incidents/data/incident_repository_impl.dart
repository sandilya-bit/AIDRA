import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../../core/config/app_config.dart';
import '../../../core/constants/app_enums.dart';
import '../../../core/data/demo_data.dart';
import '../../../core/error/failure.dart';
import '../../../core/models/incident.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/local_store.dart';
import '../domain/incident_repository.dart';

/// Incidents: remote-first with a local cache, and the bundled demo dataset as
/// the last resort so a Command Center is always renderable — including on a
/// tablet with no SIM card in a field camp.
class IncidentRepositoryImpl implements IncidentRepository {
  IncidentRepositoryImpl({
    required ApiClient apiClient,
    required LocalStore store,
    Uuid? uuid,
  })  : _api = apiClient,
        _store = store,
        _uuid = uuid ?? const Uuid();

  final ApiClient _api;
  final LocalStore _store;
  final Uuid _uuid;

  @override
  Future<List<Incident>> fetchIncidents({
    int limit = 50,
    UrgencyLevel? urgency,
    bool activeOnly = false,
  }) async {
    if (AppConfig.useRemoteBackend) {
      try {
        final List<dynamic> items = await _api.getList(
          '/incidents',
          query: <String, dynamic>{
            'limit': limit,
            if (urgency != null) 'severity': urgency.key,
            if (activeOnly) 'status': 'open,assigned,in_progress',
          },
        );
        final List<Incident> incidents = items
            .whereType<Map<dynamic, dynamic>>()
            .map((Map<dynamic, dynamic> e) =>
                Incident.fromJson(e.cast<String, dynamic>()))
            .toList(growable: false);
        await _cache(incidents);
        return _applyFilters(incidents, urgency: urgency, activeOnly: activeOnly, limit: limit);
      } on Failure catch (_) {
        return _fallback(urgency: urgency, activeOnly: activeOnly, limit: limit);
      }
    }
    return _fallback(urgency: urgency, activeOnly: activeOnly, limit: limit);
  }

  @override
  Future<Incident?> fetchIncident(String id) async {
    if (AppConfig.useRemoteBackend) {
      try {
        final Map<String, dynamic> json = await _api.getJson('/incidents/$id');
        final dynamic data = json['incident'] ?? json;
        if (data is Map<String, dynamic>) return Incident.fromJson(data);
      } on Failure catch (_) {
        return _fromCacheOrDemo(id);
      }
    }
    return _fromCacheOrDemo(id);
  }

  @override
  Future<List<DisasterEvent>> fetchEvents() async {
    if (AppConfig.useRemoteBackend) {
      try {
        final List<dynamic> items = await _api.getList('/events', query: <String, dynamic>{'status': 'active'});
        return items
            .whereType<Map<dynamic, dynamic>>()
            .map((Map<dynamic, dynamic> e) => DisasterEvent.fromJson(e.cast<String, dynamic>()))
            .toList(growable: false);
      } on Failure catch (_) {
        return DemoData.events();
      }
    }
    return DemoData.events();
  }

  @override
  Future<IncidentKpis> fetchKpis() async {
    if (AppConfig.useRemoteBackend) {
      try {
        final Map<String, dynamic> json = await _api.getJson('/analytics/kpis');
        return IncidentKpis.fromJson(json);
      } on Failure catch (_) {
        return IncidentKpis.fromIncidents(_localIncidents());
      }
    }
    return IncidentKpis.fromIncidents(_localIncidents());
  }

  @override
  Future<Incident> updateStatus(
    String incidentId,
    IncidentStatus status, {
    String? note,
  }) async {
    // Optimistic local update first: the UI must respond instantly even when
    // the request will be replayed later (offline-first).
    final List<Incident> current = _localIncidents();
    final int index = current.indexWhere((Incident i) => i.id == incidentId);
    Incident? updated;
    if (index != -1) {
      updated = _withStatus(current[index], status, note);
      current[index] = updated;
      await _cache(current);
    }

    if (AppConfig.useRemoteBackend) {
      try {
        await _api.patchJson('/incidents/$incidentId', <String, dynamic>{
          'status': status.key,
          if (note != null) 'note': note,
        });
      } on Failure catch (_) {
        // Queued by the caller's outbox; the optimistic value stands until the
        // next successful sync reconciles it.
      }
    }

    if (updated != null) return updated;
    return Incident(
      id: incidentId,
      code: 'INC-UNKNOWN',
      title: 'Incident',
      hazardType: 'other',
      severity: UrgencyLevel.medium,
      status: status,
      point: DemoData.center,
      createdAt: DateTime.now(),
    );
  }

  // ------------------------------------------------------------------ helpers

  Incident _withStatus(Incident incident, IncidentStatus status, String? note) {
    final bool resolving = status == IncidentStatus.resolved;
    return Incident(
      id: incident.id,
      code: incident.code,
      title: incident.title,
      hazardType: incident.hazardType,
      severity: incident.severity,
      status: status,
      source: incident.source,
      eventId: incident.eventId,
      eventName: incident.eventName,
      point: incident.point,
      addressText: incident.addressText,
      victimsCount: incident.victimsCount,
      casualties: incident.casualties,
      rescuedCount: incident.rescuedCount,
      needs: incident.needs,
      isPublic: incident.isPublic,
      reportCount: incident.reportCount,
      assignedResponders: incident.assignedResponders,
      slaDueAt: incident.slaDueAt,
      firstAssignedAt: incident.firstAssignedAt,
      firstOnSceneAt: incident.firstOnSceneAt,
      resolvedAt: resolving ? DateTime.now() : incident.resolvedAt,
      createdAt: incident.createdAt,
      updatedAt: DateTime.now(),
      updates: <IncidentUpdate>[
        IncidentUpdate(
          id: _uuid.v4(),
          type: 'status_change',
          fromStatus: incident.status,
          toStatus: status,
          note: note,
          createdAt: DateTime.now(),
        ),
        ...incident.updates,
      ],
    );
  }

  Future<void> _cache(List<Incident> incidents) => _store.setJsonList(
        LocalStore.keyCachedIncidents,
        incidents.map((Incident i) => i.toJson()).toList(growable: false),
      );

  List<Incident> _localIncidents() {
    final List<Map<String, dynamic>> cached =
        _store.getJsonList(LocalStore.keyCachedIncidents);
    if (cached.isEmpty) return DemoData.incidents();
    return cached.map(Incident.fromJson).toList(growable: false);
  }

  List<Incident> _fallback({
    UrgencyLevel? urgency,
    bool activeOnly = false,
    int limit = 50,
  }) =>
      _applyFilters(_localIncidents(), urgency: urgency, activeOnly: activeOnly, limit: limit);

  List<Incident> _applyFilters(
    List<Incident> incidents, {
    UrgencyLevel? urgency,
    bool activeOnly = false,
    int limit = 50,
  }) {
    Iterable<Incident> filtered = incidents;
    if (urgency != null) {
      filtered = filtered.where((Incident i) => i.severity == urgency);
    }
    if (activeOnly) {
      filtered = filtered.where((Incident i) => i.isActive);
    }
    final List<Incident> list = filtered.toList(growable: false)
      ..sort((Incident a, Incident b) => b.createdAt.compareTo(a.createdAt));
    return list.length > limit ? list.sublist(0, limit) : list;
  }

  Incident? _fromCacheOrDemo(String id) {
    for (final Incident incident in _localIncidents()) {
      if (incident.id == id) return incident;
    }
    return null;
  }

  /// Exposed for the fake/simulated feed so screens can show activity.
  Future<void> touch() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}
