import '../../../core/constants/app_enums.dart';
import '../../../core/models/geo_point.dart';
import '../../../core/models/volunteer.dart';

/// Volunteer matching, dispatch and safe-route boundary
/// (FR-301–304, FR-601–603, PRD Volume II §5.B–5.C).
abstract class VolunteerRepository {
  /// Ranked candidates for an incident (or the caller's position when no
  /// incident is selected).
  Future<List<VolunteerProfile>> findMatches({
    required GeoPoint center,
    double radiusKm = 5,
    String? requiredSkill,
    int limit = 10,
  });

  Future<Assignment> assign({
    required String incidentId,
    required String? incidentTitle,
    required UrgencyLevel severity,
    required VolunteerProfile volunteer,
    GeoPoint? incidentPoint,
  });

  Future<List<Assignment>> fetchAssignments(String assigneeId);

  Future<Assignment> updateStatus(String assignmentId, AssignmentStatus status);

  /// Safe-route recommendation with hazard avoidance.
  Future<RoutePlan> planRoute({
    required GeoPoint origin,
    required GeoPoint destination,
    bool avoidHazards = true,
  });

  Future<void> setAvailability(VolunteerAvailability availability);
}
