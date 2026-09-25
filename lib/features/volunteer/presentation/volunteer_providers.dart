import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_enums.dart';
import '../../../core/di/providers.dart';
import '../../../core/models/geo_point.dart';
import '../../../core/models/incident.dart';
import '../../../core/models/volunteer.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../incidents/presentation/incident_providers.dart';
import '../data/volunteer_repository_impl.dart';
import '../domain/volunteer_repository.dart';

final Provider<VolunteerRepository> volunteerRepositoryProvider =
    Provider<VolunteerRepository>(
  (Ref ref) => VolunteerRepositoryImpl(
    apiClient: ref.watch(apiClientProvider),
    store: ref.watch(localStoreProvider),
  ),
);

/// Ranked matches, recomputed whenever the incident focus or radius changes.
class MatchQuery {
  const MatchQuery({
    required this.center,
    this.radiusKm = 5,
    this.skill,
  });

  final GeoPoint center;
  final double radiusKm;
  final String? skill;

  @override
  bool operator ==(Object other) =>
      other is MatchQuery &&
      other.center == center &&
      other.radiusKm == radiusKm &&
      other.skill == skill;

  @override
  int get hashCode => Object.hash(center, radiusKm, skill);
}

final FutureProviderFamily<List<VolunteerProfile>, MatchQuery>
    volunteerMatchesProvider =
    FutureProvider.family<List<VolunteerProfile>, MatchQuery>(
  (Ref ref, MatchQuery query) => ref.watch(volunteerRepositoryProvider).findMatches(
        center: query.center,
        radiusKm: query.radiusKm,
        requiredSkill: query.skill,
      ),
);

/// The best-match banner: "Best Match Found · N volunteers within X km".
class MatchSummary {
  const MatchSummary({
    required this.count,
    required this.radiusKm,
    required this.best,
    required this.etaMinutes,
  });

  final int count;
  final double radiusKm;
  final VolunteerProfile? best;
  final int? etaMinutes;

  bool get hasMatch => count > 0;
}

final Provider<MatchSummary> matchSummaryProvider = Provider<MatchSummary>((Ref ref) {
  final AsyncValue<List<VolunteerProfile>> matches =
      ref.watch(volunteerMatchesProvider(const MatchQuery(center: kOpsCenter)));
  final List<VolunteerProfile> list = matches.valueOrNull ?? const <VolunteerProfile>[];
  final List<VolunteerProfile> within2km = list
      .where((VolunteerProfile v) => (v.distanceMetres ?? double.infinity) <= 2000)
      .toList(growable: false);

  return MatchSummary(
    count: within2km.length,
    radiusKm: 2,
    best: list.isEmpty ? null : list.first,
    etaMinutes: list.isEmpty ? null : list.first.etaMinutes,
  );
});

/// Default operational centre until a GPS fix arrives.
const GeoPoint kOpsCenter = GeoPoint(17.3850, 78.4867);

/// My active assignments (volunteer task list).
final AsyncNotifierProvider<AssignmentsController, List<Assignment>>
    myAssignmentsProvider =
    AsyncNotifierProvider<AssignmentsController, List<Assignment>>(
  AssignmentsController.new,
);

class AssignmentsController extends AsyncNotifier<List<Assignment>> {
  @override
  Future<List<Assignment>> build() async {
    final String assigneeId = ref.watch(currentUserProvider)?.id ?? 'usr-volunteer';
    return ref.watch(volunteerRepositoryProvider).fetchAssignments(assigneeId);
  }

  Future<void> refresh() async {
    state = const AsyncValue<List<Assignment>>.loading();
    state = await AsyncValue.guard(() async {
      final String assigneeId = ref.read(currentUserProvider)?.id ?? 'usr-volunteer';
      return ref.read(volunteerRepositoryProvider).fetchAssignments(assigneeId);
    });
  }

  /// Accept, start navigation, mark on scene, or resolve a task.
  Future<void> advance(String assignmentId, AssignmentStatus status) async {
    final List<Assignment>? current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue<List<Assignment>>.data(
        current
            .map((Assignment a) =>
                a.id == assignmentId ? a.copyWith(status: status) : a)
            .toList(growable: false),
      );
    }
    try {
      await ref.read(volunteerRepositoryProvider).updateStatus(assignmentId, status);
      await refresh();
    } catch (_) {
      // Optimistic state stands; the outbox replays the mutation.
    }
  }
}

/// Dispatch a volunteer to an incident (authority/coordinator action).
final Provider<DispatchController> dispatchControllerProvider =
    Provider<DispatchController>((Ref ref) => DispatchController(ref));

class DispatchController {
  DispatchController(this._ref);

  final Ref _ref;

  Future<Assignment> assign({
    required String incidentId,
    required VolunteerProfile volunteer,
  }) async {
    final Incident? incident = _ref.read(incidentByIdProvider(incidentId));
    final Assignment assignment =
        await _ref.read(volunteerRepositoryProvider).assign(
              incidentId: incidentId,
              incidentTitle: incident?.title,
              severity: incident?.severity ?? UrgencyLevel.high,
              volunteer: volunteer,
              incidentPoint: incident?.point ?? kOpsCenter,
            );
    await _ref.read(myAssignmentsProvider.notifier).refresh();
    return assignment;
  }
}

/// Route preview for a volunteer → incident hop.
class RouteQuery {
  const RouteQuery({required this.origin, required this.destination});

  final GeoPoint origin;
  final GeoPoint destination;

  @override
  bool operator ==(Object other) =>
      other is RouteQuery &&
      other.origin == origin &&
      other.destination == destination;

  @override
  int get hashCode => Object.hash(origin, destination);
}

final FutureProviderFamily<RoutePlan, RouteQuery> routePlanProvider =
    FutureProvider.family<RoutePlan, RouteQuery>(
  (Ref ref, RouteQuery query) => ref.watch(volunteerRepositoryProvider).planRoute(
        origin: query.origin,
        destination: query.destination,
      ),
);

/// My availability, persisted locally and pushed to the server when online.
final NotifierProvider<MyAvailabilityController, VolunteerAvailability>
    myAvailabilityProvider =
    NotifierProvider<MyAvailabilityController, VolunteerAvailability>(
  MyAvailabilityController.new,
);

class MyAvailabilityController extends Notifier<VolunteerAvailability> {
  @override
  VolunteerAvailability build() {
    final String? stored =
        ref.watch(localStoreProvider).getString('volunteer.availability');
    for (final VolunteerAvailability value in VolunteerAvailability.values) {
      if (value.key == stored) return value;
    }
    return VolunteerAvailability.available;
  }

  Future<void> setAvailability(VolunteerAvailability availability) async {
    state = availability;
    unawaited(ref.read(volunteerRepositoryProvider).setAvailability(availability));
  }
}
