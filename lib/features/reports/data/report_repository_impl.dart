import 'dart:async';
import 'package:uuid/uuid.dart';

import '../../../core/config/app_config.dart';
import '../../../core/constants/app_enums.dart';
import '../../../core/data/demo_data.dart';
import '../../../core/error/failure.dart';
import '../../../core/models/emergency_report.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/connectivity_service.dart';
import '../../../core/storage/local_store.dart';
import '../../../core/storage/outbox_store.dart';
import '../../../core/firebase/firestore_report_service.dart';
import '../../../core/firebase/storage_upload_service.dart';
import '../domain/report_repository.dart';

/// Report repository — the reference implementation of AIDRA's offline-first
/// write path:
///
/// 1. Persist locally **first** (never lose an SOS to a network hiccup).
/// 2. Try the network when it is available.
/// 3. On failure, enqueue an idempotent mutation in the outbox and let the
///    sync service replay it. Nothing is ever silently dropped.
class ReportRepositoryImpl implements ReportRepository {
  ReportRepositoryImpl({
    required ApiClient apiClient,
    required LocalStore store,
    required OutboxStore outbox,
    required ConnectivityService connectivity,
    required void Function() onQueued,
    Uuid? uuid,
    FirestoreReportService? firestoreService,
    StorageUploadService? storageService,
  })  : _api = apiClient,
        _store = store,
        _outbox = outbox,
        _connectivity = connectivity,
        _onQueued = onQueued,
        _uuid = uuid ?? const Uuid(),
        _firestoreService = firestoreService,
        _storageService = storageService;

  static const String outboxType = 'report.create';

  final ApiClient _api;
  final LocalStore _store;
  final OutboxStore _outbox;
  final ConnectivityService _connectivity;
  final void Function() _onQueued;
  final Uuid _uuid;
  final FirestoreReportService? _firestoreService;
  final StorageUploadService? _storageService;

  @override
  List<EmergencyReport> cachedReports() {
    final List<Map<String, dynamic>> cached =
        _store.getJsonList(LocalStore.keyCachedReports);
    if (cached.isEmpty) return DemoData.reports();
    return cached.map(EmergencyReport.fromJson).toList(growable: false);
  }

  @override
  Future<List<EmergencyReport>> fetchReports({bool all = false}) async {
    if (AppConfig.useRemoteBackend) {
      try {
        final List<dynamic> items = await _api.getList(
          '/reports',
          query: <String, dynamic>{if (all) 'scope': 'all', 'limit': 100},
        );
        final List<EmergencyReport> reports = items
            .whereType<Map<dynamic, dynamic>>()
            .map((Map<dynamic, dynamic> e) =>
                EmergencyReport.fromJson(e.cast<String, dynamic>()))
            .toList(growable: false);
        await _cache(reports);
        return reports;
      } on Failure catch (_) {
        return cachedReports();
      }
    }
    return cachedReports();
  }

  @override
  Future<EmergencyReport> fetchReport(String id) async {
    if (AppConfig.useRemoteBackend) {
      try {
        final Map<String, dynamic> json = await _api.getJson('/reports/$id');
        final dynamic data = json['report'] ?? json;
        if (data is Map<String, dynamic>) return EmergencyReport.fromJson(data);
      } on Failure catch (_) {
        return _localById(id);
      }
    }
    return _localById(id);
  }

  @override
  Future<EmergencyReport> submit(EmergencyReport report) async {
    // 1. Persist locally first — the report exists from this moment on.
    final EmergencyReport queued = report.copyWith(
      status: ReportStatus.queued,
      isOfflineCreated: true,
    );
    await _upsertLocal(queued);

    // Dual-write to Firestore for real-time dashboards (fire-and-forget).
    unawaited(_firestoreService?.save(queued));

    // 2. Try to reach the server.
    final bool online = await _connectivity.checkOnline();
    if (AppConfig.useRemoteBackend && online) {
      try {
        final Map<String, dynamic> response = await _api.postJson(
          '/reports',
          report.toJson(),
          idempotencyKey: _uuid.v4(),
        );
        final dynamic data = response['report'] ?? response;
        if (data is Map<String, dynamic>) {
          final EmergencyReport synced = EmergencyReport.fromJson(data).copyWith(
            status: ReportStatus.submitted,
            syncedAt: DateTime.now(),
          );
          await _upsertLocal(synced);
          
          unawaited(_firestoreService?.save(synced));

          // Upload media attachments to Firebase Storage in the background.
          if (_storageService != null && synced.attachments.isNotEmpty) {
            unawaited(
              _storageService!.uploadAttachments(synced.id, synced.attachments),
            );
          }

          return synced;
        }
      } on Failure catch (_) {
        // Fall through to queueing.
      }
    }

    // 3. Queue for replay.
    final String mutationId = _uuid.v4();
    await _outbox.enqueue(
      OutboxEntry(
        id: mutationId,
        type: outboxType,
        payload: <String, dynamic>{
          'report': queued.toJson(),
          'client_created_at': queued.createdAt.toIso8601String(),
        },
        createdAt: DateTime.now(),
      ),
    );
    _onQueued();

    return queued.copyWith(errorMessage: null);
  }

  @override
  Future<void> replayQueued(Map<String, dynamic> payload) async {
    final Map<String, dynamic> reportJson =
        (payload['report'] as Map<dynamic, dynamic>?)?.cast<String, dynamic>() ??
            <String, dynamic>{};
    final EmergencyReport queued = EmergencyReport.fromJson(reportJson);

    final Map<String, dynamic> response = await _api.postJson(
      '/reports',
      queued.toJson(),
      idempotencyKey: queued.id,
    );
    final dynamic data = response['report'] ?? response;
    if (data is Map<String, dynamic>) {
      await _upsertLocal(
        EmergencyReport.fromJson(data).copyWith(
          status: ReportStatus.submitted,
          syncedAt: DateTime.now(),
        ),
      );
    }
  }

  // ------------------------------------------------------------------ helpers

  Future<void> _upsertLocal(EmergencyReport report) async {
    final List<EmergencyReport> reports = cachedReports().toList()
      ..removeWhere((EmergencyReport r) => r.id == report.id)
      ..insert(0, report);
    final List<EmergencyReport> trimmed = reports.length > AppConfig.maxCachedReports
        ? reports.sublist(0, AppConfig.maxCachedReports)
        : reports;
    await _cache(trimmed);
  }

  Future<void> _cache(List<EmergencyReport> reports) => _store.setJsonList(
        LocalStore.keyCachedReports,
        reports.map((EmergencyReport r) => r.toJson()).toList(growable: false),
      );

  EmergencyReport _localById(String id) {
    final List<EmergencyReport> reports = cachedReports();
    if (reports.isEmpty) {
      throw const CacheFailure('Report not found on this device');
    }
    return reports.firstWhere(
      (EmergencyReport r) => r.id == id,
      orElse: () => reports.first,
    );
  }
}
