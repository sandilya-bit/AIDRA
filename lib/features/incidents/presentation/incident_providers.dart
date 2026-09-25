import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_enums.dart';
import '../../../core/di/providers.dart';
import '../../../core/models/geo_point.dart';
import '../../../core/models/incident.dart';
import '../data/incident_repository_impl.dart';
import '../domain/incident_repository.dart';

final Provider<IncidentRepository> incidentRepositoryProvider =
    Provider<IncidentRepository>(
  (Ref ref) => IncidentRepositoryImpl(
    apiClient: ref.watch(apiClientProvider),
    store: ref.watch(localStoreProvider),
  ),
);

/// Live incident feed with poll-based refresh. Kept as an `AsyncNotifier` so
/// pull-to-refresh, optimistic updates and error states are all in one place.
final AsyncNotifierProvider<IncidentsController, List<Incident>> incidentsProvider =
    AsyncNotifierProvider<IncidentsController, List<Incident>>(
  IncidentsController.new,
);

class IncidentsController extends AsyncNotifier<List<Incident>> {
  Timer? _poller;

  @override
  Future<List<Incident>> build() async {
    _poller = Timer.periodic(const Duration(seconds: 45), (_) {
      unawaited(refresh(silent: true));
    });
    ref.onDispose(() => _poller?.cancel());
    return ref.read(incidentRepositoryProvider).fetchIncidents();
  }

  /// `silent` skips the loading state (background refresh keeps the map stable).
  Future<void> refresh({bool silent = false}) async {
    if (!silent) state = const AsyncValue<List<Incident>>.loading();
    try {
      final List<Incident> incidents =
          await ref.read(incidentRepositoryProvider).fetchIncidents();
      state = AsyncValue<List<Incident>>.data(incidents);
    } catch (error, stackTrace) {
      state = AsyncValue<List<Incident>>.error(error, stackTrace);
    }
  }

  /// Optimistic status transition (authority / volunteer actions).
  Future<void> updateStatus(
    String incidentId,
    IncidentStatus status, {
    String? note,
  }) async {
    final List<Incident>? current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue<List<Incident>>.data(
        current
            .map((Incident i) => i.id == incidentId
                ? _localTransition(i, status, note)
                : i)
            .toList(growable: false),
      );
    }
    try {
      await ref
          .read(incidentRepositoryProvider)
          .updateStatus(incidentId, status, note: note);
      await refresh(silent: true);
    } catch (_) {
      // The write is queued in the outbox; the optimistic value stays.
    }
  }

  Incident _localTransition(Incident incident, IncidentStatus status, String? note) {
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
      firstOnSceneAt: status == IncidentStatus.inProgress && incident.firstOnSceneAt == null
          ? DateTime.now()
          : incident.firstOnSceneAt,
      resolvedAt: status == IncidentStatus.resolved ? DateTime.now() : incident.resolvedAt,
      createdAt: incident.createdAt,
      updatedAt: DateTime.now(),
    );
  }
}

/// Convenience selectors -----------------------------------------------------

final Provider<List<Incident>> activeIncidentsProvider =
    Provider<List<Incident>>((Ref ref) {
  final List<Incident> incidents =
      ref.watch(incidentsProvider).valueOrNull ?? const <Incident>[];
  return incidents.where((Incident i) => i.isActive).toList(growable: false);
});

final Provider<List<Incident>> criticalIncidentsProvider =
    Provider<List<Incident>>((Ref ref) {
  final List<Incident> incidents = ref.watch(activeIncidentsProvider);
  return incidents
      .where((Incident i) => i.severity.isEmergency)
      .toList(growable: false);
});

/// Incidents within [radiusKm] of a point — uses client-side haversine so it
/// also works offline (the server does the same maths with PostGIS).
final ProviderFamily<List<Incident>, NearbyQuery> nearbyIncidentsProvider =
    Provider.family<List<Incident>, NearbyQuery>((Ref ref, NearbyQuery query) {
  final List<Incident> incidents =
      ref.watch(incidentsProvider).valueOrNull ?? const <Incident>[];
  return incidents
      .where((Incident i) => i.point.distanceTo(query.center) <= query.radiusKm * 1000)
      .toList(growable: false);
});

class NearbyQuery {
  const NearbyQuery(this.center, {this.radiusKm = 5});

  final GeoPoint center;
  final double radiusKm;

  @override
  bool operator ==(Object other) =>
      other is NearbyQuery &&
      other.center == center &&
      other.radiusKm == radiusKm;

  @override
  int get hashCode => Object.hash(center, radiusKm);
}

/// Command Center KPI cards. Derived from the live feed when offline, or from
/// `/analytics/kpis` when the backend is reachable.
final FutureProvider<IncidentKpis> kpisProvider = FutureProvider<IncidentKpis>(
  (Ref ref) async {
    ref.watch(incidentsProvider);
    return ref.watch(incidentRepositoryProvider).fetchKpis();
  },
);

final FutureProvider<List<DisasterEvent>> eventsProvider =
    FutureProvider<List<DisasterEvent>>(
  (Ref ref) => ref.watch(incidentRepositoryProvider).fetchEvents(),
);

/// Single incident, refreshed whenever the feed changes.
final ProviderFamily<Incident?, String> incidentByIdProvider =
    Provider.family<Incident?, String>((Ref ref, String id) {
  final List<Incident> incidents =
      ref.watch(incidentsProvider).valueOrNull ?? const <Incident>[];
  for (final Incident incident in incidents) {
    if (incident.id == id) return incident;
  }
  return null;
});

/// List-level filter (severity + active-only toggle) for the incidents screen.
class IncidentFilter {
  const IncidentFilter({this.urgency, this.activeOnly = false});

  final UrgencyLevel? urgency;
  final bool activeOnly;

  IncidentFilter copyWith({
    UrgencyLevel? urgency,
    bool clearUrgency = false,
    bool? activeOnly,
  }) {
    return IncidentFilter(
      urgency: clearUrgency ? null : (urgency ?? this.urgency),
      activeOnly: activeOnly ?? this.activeOnly,
    );
  }
}

final NotifierProvider<IncidentFilterController, IncidentFilter>
    incidentFilterProvider =
    NotifierProvider<IncidentFilterController, IncidentFilter>(
  IncidentFilterController.new,
);

class IncidentFilterController extends Notifier<IncidentFilter> {
  @override
  IncidentFilter build() => const IncidentFilter();

  void setUrgency(UrgencyLevel? urgency) {
    state = urgency == null
        ? state.copyWith(clearUrgency: true)
        : state.copyWith(urgency: urgency);
  }

  void toggleActiveOnly() {
    state = state.copyWith(activeOnly: !state.activeOnly);
  }
}

final Provider<List<Incident>> filteredIncidentsProvider =
    Provider<List<Incident>>((Ref ref) {
  final List<Incident> incidents =
      ref.watch(incidentsProvider).valueOrNull ?? const <Incident>[];
  final IncidentFilter filter = ref.watch(incidentFilterProvider);
  Iterable<Incident> result = incidents;
  if (filter.urgency != null) {
    result = result.where((Incident i) => i.severity == filter.urgency);
  }
  if (filter.activeOnly) {
    result = result.where((Incident i) => i.isActive);
  }
  return result.toList(growable: false);
});
