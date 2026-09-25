import '../../../core/models/hospital.dart';

/// Hospital coordination boundary (FR-401/402, US-401–403).
abstract class HospitalRepository {
  Future<List<Hospital>> fetchHospitals();

  Future<Hospital> fetchHospital(String id);

  Future<List<CasualtyPreAlert>> fetchPreAlerts({String? hospitalId});

  /// Publish a capacity update (beds / ICU / oxygen / blood).
  Future<Hospital> updateCapacity({
    required String hospitalId,
    int? bedsAvailable,
    int? icuAvailable,
    int? oxygenUnits,
    int? ventilatorsAvailable,
    Map<String, int>? bloodInventory,
    bool? isAccepting,
  });

  Future<CasualtyPreAlert> acknowledgePreAlert(String preAlertId);

  /// Ask the routing engine for the best receiving hospital for a casualty load.
  Future<List<Hospital>> suggestReceiving({
    required int patientCount,
    required bool needsIcu,
  });
}
