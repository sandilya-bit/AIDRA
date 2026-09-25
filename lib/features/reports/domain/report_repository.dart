import '../../../core/models/emergency_report.dart';

/// Emergency reporting boundary (FR-101–107, FR-1002).
abstract class ReportRepository {
  /// Reports visible to the caller (own reports for victims, all for
  /// authorities when `all` is true).
  Future<List<EmergencyReport>> fetchReports({bool all = false});

  Future<EmergencyReport> fetchReport(String id);

  /// Submit a report. When the device is offline (or the backend is
  /// unreachable) the report is persisted locally and queued in the outbox —
  /// the returned object is marked `ReportStatus.queued` so the UI can show the
  /// truth instead of a fake success.
  Future<EmergencyReport> submit(EmergencyReport report);

  /// Replay queued outbox entries (wired into the sync service).
  Future<void> replayQueued(Map<String, dynamic> payload);

  /// Cached reports, newest first — used to render instantly on cold start.
  List<EmergencyReport> cachedReports();
}
