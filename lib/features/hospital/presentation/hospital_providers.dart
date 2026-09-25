import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/models/hospital.dart';
import '../data/hospital_repository_impl.dart';
import '../domain/hospital_repository.dart';

final Provider<HospitalRepository> hospitalRepositoryProvider =
    Provider<HospitalRepository>(
  (Ref ref) => HospitalRepositoryImpl(
    apiClient: ref.watch(apiClientProvider),
    store: ref.watch(localStoreProvider),
  ),
);

final AsyncNotifierProvider<HospitalsController, List<Hospital>> hospitalsProvider =
    AsyncNotifierProvider<HospitalsController, List<Hospital>>(
  HospitalsController.new,
);

class HospitalsController extends AsyncNotifier<List<Hospital>> {
  @override
  Future<List<Hospital>> build() => ref.watch(hospitalRepositoryProvider).fetchHospitals();

  Future<void> refresh() async {
    state = const AsyncValue<List<Hospital>>.loading();
    state = await AsyncValue.guard(
      () => ref.read(hospitalRepositoryProvider).fetchHospitals(),
    );
  }

  /// Optimistic capacity update (hospital coordinator action).
  Future<void> updateCapacity({
    required String hospitalId,
    int? bedsAvailable,
    int? icuAvailable,
    int? oxygenUnits,
    int? ventilatorsAvailable,
    bool? isAccepting,
  }) async {
    try {
      final Hospital updated =
          await ref.read(hospitalRepositoryProvider).updateCapacity(
                hospitalId: hospitalId,
                bedsAvailable: bedsAvailable,
                icuAvailable: icuAvailable,
                oxygenUnits: oxygenUnits,
                ventilatorsAvailable: ventilatorsAvailable,
                isAccepting: isAccepting,
              );
      final List<Hospital>? current = state.valueOrNull;
      if (current != null) {
        state = AsyncValue<List<Hospital>>.data(
          current
              .map((Hospital h) => h.id == updated.id ? updated : h)
              .toList(growable: false),
        );
      }
    } catch (error, stackTrace) {
      state = AsyncValue<List<Hospital>>.error(error, stackTrace);
    }
  }
}

final AsyncNotifierProvider<PreAlertsController, List<CasualtyPreAlert>>
    preAlertsProvider =
    AsyncNotifierProvider<PreAlertsController, List<CasualtyPreAlert>>(
  PreAlertsController.new,
);

class PreAlertsController extends AsyncNotifier<List<CasualtyPreAlert>> {
  @override
  Future<List<CasualtyPreAlert>> build() =>
      ref.watch(hospitalRepositoryProvider).fetchPreAlerts();

  Future<void> acknowledge(String preAlertId) async {
    final CasualtyPreAlert updated =
        await ref.read(hospitalRepositoryProvider).acknowledgePreAlert(preAlertId);
    final List<CasualtyPreAlert>? current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue<List<CasualtyPreAlert>>.data(
        current
            .map((CasualtyPreAlert a) => a.id == updated.id ? updated : a)
            .toList(growable: false),
      );
    }
  }
}

/// Hospitals able to take a given casualty load, ranked (FR-403 / §5.D).
final FutureProviderFamily<List<Hospital>, ReceivingQuery> receivingHospitalsProvider =
    FutureProvider.family<List<Hospital>, ReceivingQuery>(
  (Ref ref, ReceivingQuery query) async {
    // Recompute whenever capacity changes.
    ref.watch(hospitalsProvider);
    return ref.watch(hospitalRepositoryProvider).suggestReceiving(
          patientCount: query.patientCount,
          needsIcu: query.needsIcu,
        );
  },
);

class ReceivingQuery {
  const ReceivingQuery({required this.patientCount, this.needsIcu = false});

  final int patientCount;
  final bool needsIcu;

  @override
  bool operator ==(Object other) =>
      other is ReceivingQuery &&
      other.patientCount == patientCount &&
      other.needsIcu == needsIcu;

  @override
  int get hashCode => Object.hash(patientCount, needsIcu);
}
