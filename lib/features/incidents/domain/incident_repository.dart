import '../../../core/constants/app_enums.dart';
import '../../../core/models/incident.dart';

/// Operational incident data — shared by the dashboard, live map, volunteer
/// matching and hospital screens.
abstract class IncidentRepository {
  /// Incidents within the caller's area, newest first.
  Future<List<Incident>> fetchIncidents({
    int limit = 50,
    UrgencyLevel? urgency,
    bool activeOnly = false,
  });

  Future<Incident?> fetchIncident(String id);

  /// Cluster/event banner data (PRD Volume II §4.2).
  Future<List<DisasterEvent>> fetchEvents();

  /// Command Center KPI cards.
  Future<IncidentKpis> fetchKpis();

  /// Authority action: move an incident through its lifecycle.
  Future<Incident> updateStatus(
    String incidentId,
    IncidentStatus status, {
    String? note,
  });
}
