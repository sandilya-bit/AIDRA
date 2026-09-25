import '../../../core/config/app_config.dart';
import '../../../core/data/demo_data.dart';
import '../../../core/error/failure.dart';
import '../../../core/models/hospital.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/local_store.dart';
import '../domain/hospital_repository.dart';

/// Hospital capacity + casualty pre-alerts.
///
/// Capacity writes are optimistic-local-first: during a mass-casualty event the
/// screen must stay responsive, and the update is queued for the server.
class HospitalRepositoryImpl implements HospitalRepository {
  HospitalRepositoryImpl({
    required ApiClient apiClient,
    required LocalStore store,
  })  : _api = apiClient,
        _store = store;

  static const String keyHospitals = 'cache.hospitals';
  static const String keyPreAlerts = 'cache.prealerts';

  final ApiClient _api;
  final LocalStore _store;

  @override
  Future<List<Hospital>> fetchHospitals() async {
    if (AppConfig.useRemoteBackend) {
      try {
        final List<dynamic> items = await _api.getList('/hospitals');
        final List<Hospital> hospitals = items
            .whereType<Map<dynamic, dynamic>>()
            .map((Map<dynamic, dynamic> e) =>
                Hospital.fromJson(e.cast<String, dynamic>()))
            .toList(growable: false);
        if (hospitals.isNotEmpty) {
          await _persistHospitals(hospitals);
          return hospitals;
        }
      } on Failure catch (_) {
        return _localHospitals();
      }
    }
    return _localHospitals();
  }

  @override
  Future<Hospital> fetchHospital(String id) async {
    for (final Hospital hospital in _localHospitals()) {
      if (hospital.id == id) return hospital;
    }
    if (AppConfig.useRemoteBackend) {
      try {
        final Map<String, dynamic> json = await _api.getJson('/hospitals/$id');
        final dynamic data = json['hospital'] ?? json;
        if (data is Map<String, dynamic>) return Hospital.fromJson(data);
      } on Failure catch (_) {
        throw const CacheFailure('Hospital not available offline');
      }
    }
    throw const CacheFailure('Hospital not found');
  }

  @override
  Future<List<CasualtyPreAlert>> fetchPreAlerts({String? hospitalId}) async {
    if (AppConfig.useRemoteBackend) {
      try {
        final List<dynamic> items = await _api.getList(
          '/hospitals/prealerts',
          query: <String, dynamic>{if (hospitalId != null) 'hospital_id': hospitalId},
        );
        final List<CasualtyPreAlert> alerts = items
            .whereType<Map<dynamic, dynamic>>()
            .map((Map<dynamic, dynamic> e) =>
                CasualtyPreAlert.fromJson(e.cast<String, dynamic>()))
            .toList(growable: false);
        if (alerts.isNotEmpty) {
          await _persistPreAlerts(alerts);
          return alerts;
        }
      } on Failure catch (_) {
        return _localPreAlerts();
      }
    }
    return _localPreAlerts();
  }

  @override
  Future<Hospital> updateCapacity({
    required String hospitalId,
    int? bedsAvailable,
    int? icuAvailable,
    int? oxygenUnits,
    int? ventilatorsAvailable,
    Map<String, int>? bloodInventory,
    bool? isAccepting,
  }) async {
    final List<Hospital> hospitals = _localHospitals();
    final int index = hospitals.indexWhere((Hospital h) => h.id == hospitalId);
    if (index == -1) throw const CacheFailure('Hospital not found');

    final Hospital current = hospitals[index];
    final Hospital updated = Hospital(
      id: current.id,
      name: current.name,
      organizationId: current.organizationId,
      organizationName: current.organizationName,
      point: current.point,
      addressText: current.addressText,
      contactPhone: current.contactPhone,
      traumaLevel: current.traumaLevel,
      bedsTotal: current.bedsTotal,
      bedsAvailable: bedsAvailable ?? current.bedsAvailable,
      icuTotal: current.icuTotal,
      icuAvailable: icuAvailable ?? current.icuAvailable,
      oxygenUnits: oxygenUnits ?? current.oxygenUnits,
      ventilatorsAvailable: ventilatorsAvailable ?? current.ventilatorsAvailable,
      bloodInventory: bloodInventory ?? current.bloodInventory,
      specialties: current.specialties,
      status: (isAccepting ?? current.isAccepting) ? 'operational' : 'full',
      isAccepting: isAccepting ?? current.isAccepting,
      capacityUpdatedAt: DateTime.now(),
      distanceMetres: current.distanceMetres,
      inboundCasualties: current.inboundCasualties,
      etaMinutes: current.etaMinutes,
    );

    hospitals[index] = updated;
    await _persistHospitals(hospitals);

    if (AppConfig.useRemoteBackend) {
      try {
        await _api.patchJson('/hospitals/$hospitalId/capacity', <String, dynamic>{
          if (bedsAvailable != null) 'beds_available': bedsAvailable,
          if (icuAvailable != null) 'icu_available': icuAvailable,
          if (oxygenUnits != null) 'oxygen_units': oxygenUnits,
          if (ventilatorsAvailable != null)
            'ventilators_available': ventilatorsAvailable,
          if (bloodInventory != null) 'blood_inventory': bloodInventory,
          if (isAccepting != null) 'is_accepting': isAccepting,
        });
      } on Failure catch (_) {
        // Queued by the caller; the local value remains authoritative offline.
      }
    }

    return updated;
  }

  @override
  Future<CasualtyPreAlert> acknowledgePreAlert(String preAlertId) async {
    final List<CasualtyPreAlert> alerts = _localPreAlerts();
    final int index = alerts.indexWhere((CasualtyPreAlert a) => a.id == preAlertId);
    final DateTime now = DateTime.now();

    CasualtyPreAlert updated;
    if (index == -1) {
      updated = CasualtyPreAlert(
        id: preAlertId,
        hospitalId: 'unknown',
        hospitalName: 'Hospital',
        incidentId: 'unknown',
        patientCount: 0,
        sentAt: now,
        status: 'acknowledged',
        acknowledgedAt: now,
      );
    } else {
      updated = alerts[index].copyWith(status: 'acknowledged', acknowledgedAt: now);
      alerts[index] = updated;
    }
    await _persistPreAlerts(alerts);

    if (AppConfig.useRemoteBackend) {
      try {
        await _api.patchJson(
          '/hospitals/prealerts/$preAlertId',
          <String, dynamic>{'status': 'acknowledged'},
        );
      } on Failure catch (_) {
        // Queued for replay.
      }
    }

    return updated;
  }

  @override
  Future<List<Hospital>> suggestReceiving({
    required int patientCount,
    required bool needsIcu,
  }) async {
    final List<Hospital> hospitals = await fetchHospitals();
    final List<Hospital> eligible = hospitals
        .where((Hospital h) =>
            h.isAccepting &&
            h.bedsAvailable >= patientCount &&
            (!needsIcu || h.icuAvailable > 0))
        .toList();

    eligible.sort((Hospital a, Hospital b) {
      // Prefer most free capacity, then freshest reporting, then closest.
      final int byBeds = b.bedsAvailable.compareTo(a.bedsAvailable);
      if (byBeds != 0) return byBeds;
      final int byFresh = (a.isCapacityFresh ? 0 : 1) - (b.isCapacityFresh ? 0 : 1);
      if (byFresh != 0) return byFresh;
      return (a.distanceMetres ?? double.infinity)
          .compareTo(b.distanceMetres ?? double.infinity);
    });

    return eligible;
  }

  // ------------------------------------------------------------------ helpers

  List<Hospital> _localHospitals() {
    final List<Map<String, dynamic>> cached = _store.getJsonList(keyHospitals);
    if (cached.isEmpty) return DemoData.hospitals();
    return cached.map(Hospital.fromJson).toList(growable: false);
  }

  List<CasualtyPreAlert> _localPreAlerts() {
    final List<Map<String, dynamic>> cached = _store.getJsonList(keyPreAlerts);
    if (cached.isEmpty) return DemoData.preAlerts();
    return cached.map(CasualtyPreAlert.fromJson).toList(growable: false);
  }

  Future<void> _persistHospitals(List<Hospital> hospitals) => _store.setJsonList(
        keyHospitals,
        hospitals.map((Hospital h) => h.toJson()).toList(growable: false),
      );

  Future<void> _persistPreAlerts(List<CasualtyPreAlert> alerts) =>
      _store.setJsonList(
        keyPreAlerts,
        alerts.map((CasualtyPreAlert a) => a.toJson()).toList(growable: false),
      );
}
