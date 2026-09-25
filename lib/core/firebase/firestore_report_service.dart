import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../config/app_config.dart';
import '../models/emergency_report.dart';

/// Dual-writes emergency reports to Cloud Firestore so real-time dashboards
/// and authority screens receive updates without polling the REST backend
/// (FR-102, US-101).
///
/// The write is always fire-and-forget from the caller's perspective — this
/// service must never block or throw into the offline-first [ReportRepository].
class FirestoreReportService {
  FirestoreReportService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  static const String _collection = 'emergency_reports';

  final FirebaseFirestore _db;

  /// Writes [report] to Firestore. Returns silently on any error so the caller
  /// is never interrupted (fire-and-forget pattern).
  Future<void> save(EmergencyReport report) async {
    if (!AppConfig.useFirebase) return;
    try {
      await _db
          .collection(_collection)
          .doc(report.id)
          .set(_toFirestoreDoc(report), SetOptions(merge: true));
    } catch (_) {
      // Intentionally swallowed — Firestore availability is best-effort;
      // PostgreSQL via the REST backend is the source of truth.
    }
  }

  /// Updates the [status] field of an existing Firestore document.
  Future<void> updateStatus(String reportId, String status) async {
    if (!AppConfig.useFirebase) return;
    try {
      await _db
          .collection(_collection)
          .doc(reportId)
          .update(<String, dynamic>{
        'status': status,
        'updated_at': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  /// Real-time stream for the authority dashboard (FR-703).
  /// Returns an empty stream when Firebase is not enabled.
  Stream<List<EmergencyReport>> streamReports({int limit = 50}) {
    if (!AppConfig.useFirebase) return const Stream<List<EmergencyReport>>.empty();
    return _db
        .collection(_collection)
        .orderBy('created_at', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (QuerySnapshot<Map<String, dynamic>> snapshot) => snapshot.docs
              .map(
                (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
                    EmergencyReport.fromJson(doc.data()),
              )
              .toList(growable: false),
        );
  }

  Map<String, dynamic> _toFirestoreDoc(EmergencyReport report) =>
      <String, dynamic>{
        'id': report.id,
        'report_code': report.code,
        'reporter_id': report.reporterId,
        'reporter_name': report.reporterName,
        'input_type': report.inputType.key,
        'description': report.description,
        'description_lang': report.descriptionLanguage,
        'latitude': report.point.latitude,
        'longitude': report.point.longitude,
        if (report.addressText != null) 'address_text': report.addressText,
        if (report.hazardType != null) 'hazard_type': report.hazardType,
        'people_at_risk': report.peopleAtRisk ?? 0,
        'urgency_user': report.urgencyUser.key,
        'status': report.status.key,
        'is_offline_created': report.isOfflineCreated,
        'created_at': Timestamp.fromDate(report.createdAt),
      };
}
