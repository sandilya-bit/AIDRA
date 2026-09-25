import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_enums.dart';
import '../../../core/di/providers.dart';
import '../../../core/models/app_user.dart';
import '../../../core/models/emergency_report.dart';
import '../../../core/models/geo_point.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/report_repository_impl.dart';
import '../domain/report_repository.dart';

final Provider<ReportRepository> reportRepositoryProvider =
    Provider<ReportRepository>((Ref ref) {
  final ReportRepositoryImpl repository = ReportRepositoryImpl(
    apiClient: ref.watch(apiClientProvider),
    store: ref.watch(localStoreProvider),
    outbox: ref.watch(outboxStoreProvider),
    connectivity: ref.watch(connectivityServiceProvider),
    firestoreService: ref.watch(firestoreReportServiceProvider),
    storageService: ref.watch(storageUploadServiceProvider),
    onQueued: () {
      // Nudge the sync controller so the offline banner reflects the new queue
      // depth immediately and a flush is attempted if we are online.
      ref.read(syncControllerProvider.notifier).onMutationQueued();
    },
  );

  // Register the replay handler exactly once for this provider instance.
  ref.watch(syncServiceProvider).register(
        ReportRepositoryImpl.outboxType,
        (entry) => repository.replayQueued(entry.payload),
      );

  return repository;
});

/// All reports the user can see (authorities/watch roles see everything).
final AsyncNotifierProvider<ReportsController, List<EmergencyReport>> reportsProvider =
    AsyncNotifierProvider<ReportsController, List<EmergencyReport>>(
  ReportsController.new,
);

class ReportsController extends AsyncNotifier<List<EmergencyReport>> {
  @override
  Future<List<EmergencyReport>> build() async {
    final AppUser? user = ref.watch(currentUserProvider);
    final bool seesAll = user?.role == UserRole.authority ||
        user?.role == UserRole.ngo ||
        user?.role == UserRole.superAdmin;
    ref.listen<AuthState>(authControllerProvider, (AuthState? previous, AuthState next) {
      if (next.user?.id != previous?.user?.id) {
        unawaited(refresh(silent: true));
      }
    });
    return ref.read(reportRepositoryProvider).fetchReports(all: seesAll);
  }

  Future<void> refresh({bool silent = false}) async {
    if (!silent) state = const AsyncValue<List<EmergencyReport>>.loading();
    try {
      final List<EmergencyReport> reports =
          await ref.read(reportRepositoryProvider).fetchReports();
      state = AsyncValue<List<EmergencyReport>>.data(reports);
    } catch (error, stackTrace) {
      state = AsyncValue<List<EmergencyReport>>.error(error, stackTrace);
    }
  }

  /// Submit a report and prepend it to the feed. Returns the persisted report
  /// (which may be flagged as queued for offline sync).
  Future<EmergencyReport> submit({
    required String description,
    required ReportInputType inputType,
    required UrgencyLevel urgency,
    required GeoPoint point,
    String? addressText,
    String? hazardType,
    int? peopleAtRisk,
    String? transcript,
    List<MediaAttachment> attachments = const <MediaAttachment>[],
  }) async {
    final AppUser? user = ref.read(currentUserProvider);
    final EmergencyReport draft = EmergencyReport(
      id: const Uuid().v4(),
      code: _nextCode(),
      reporterId: user?.id ?? 'anonymous',
      reporterName: user?.fullName,
      inputType: inputType,
      description: description,
      descriptionLanguage: user?.language ?? 'en',
      transcript: transcript,
      point: point,
      addressText: addressText,
      hazardType: hazardType,
      peopleAtRisk: peopleAtRisk,
      urgencyUser: urgency,
      status: ReportStatus.submitting,
      attachments: attachments,
      createdAt: DateTime.now(),
    );

    final EmergencyReport saved =
        await ref.read(reportRepositoryProvider).submit(draft);

    final List<EmergencyReport> current = state.valueOrNull ?? <EmergencyReport>[];
    state = AsyncValue<List<EmergencyReport>>.data(
      <EmergencyReport>[saved, ...current.where((EmergencyReport r) => r.id != saved.id)],
    );
    return saved;
  }

  String _nextCode() {
    final int sequence = (state.valueOrNull?.length ?? 0) + 124;
    final String year = DateTime.now().year.toString();
    return 'AID-$year-${sequence.toString().padLeft(6, '0')}';
  }
}

/// The signed-in user's own reports (victim dashboard + My Reports screen).
final Provider<List<EmergencyReport>> myReportsProvider =
    Provider<List<EmergencyReport>>((Ref ref) {
  final List<EmergencyReport> all =
      ref.watch(reportsProvider).valueOrNull ?? const <EmergencyReport>[];
  final AppUser? user = ref.watch(currentUserProvider);
  if (user == null) return all;
  final List<EmergencyReport> mine =
      all.where((EmergencyReport r) => r.reporterId == user.id).toList(growable: false);
  // Demo datasets are authored for the victim persona; never show an empty
  // screen just because ids differ.
  return mine.isEmpty && all.isNotEmpty ? all : mine;
});

/// Count of reports queued for sync (drives the offline chip on Reports).
final Provider<int> pendingReportCountProvider = Provider<int>((Ref ref) {
  final List<EmergencyReport> reports =
      ref.watch(reportsProvider).valueOrNull ?? const <EmergencyReport>[];
  return reports.where((EmergencyReport r) => r.isPendingSync).length;
});
