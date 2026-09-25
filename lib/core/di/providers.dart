import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../network/api_client.dart';
import '../network/connectivity_service.dart';
import '../storage/local_store.dart';
import '../storage/outbox_store.dart';
import '../sync/sync_service.dart';
import '../firebase/firestore_report_service.dart';
import '../firebase/storage_upload_service.dart';

/// Overridden in `main()` with the initialised instance — see `bootstrap()`.
final Provider<LocalStore> localStoreProvider = Provider<LocalStore>(
  (Ref ref) => throw UnimplementedError('localStoreProvider must be overridden'),
);

final Provider<ApiClient> apiClientProvider = Provider<ApiClient>(
  (Ref ref) => ApiClient(),
);

final Provider<ConnectivityService> connectivityServiceProvider =
    Provider<ConnectivityService>((Ref ref) => ConnectivityService());

final Provider<OutboxStore> outboxStoreProvider = Provider<OutboxStore>(
  (Ref ref) => OutboxStore(ref.watch(localStoreProvider)),
);

final Provider<SyncService> syncServiceProvider = Provider<SyncService>(
  (Ref ref) => SyncService(
    outbox: ref.watch(outboxStoreProvider),
    connectivity: ref.watch(connectivityServiceProvider),
  ),
);

/// Live connectivity as a stream (drives the offline banner).
final StreamProvider<bool> connectivityStreamProvider = StreamProvider<bool>(
  (Ref ref) => ref.watch(connectivityServiceProvider).onStatusChanged,
);

final Provider<bool> isOnlineProvider = Provider<bool>((Ref ref) {
  final AsyncValue<bool> status = ref.watch(connectivityStreamProvider);
  return status.valueOrNull ?? true;
});

/// Owns outbox draining + exposes sync status to the UI.
final NotifierProvider<SyncController, SyncState> syncControllerProvider =
    NotifierProvider<SyncController, SyncState>(SyncController.new);

class SyncController extends Notifier<SyncState> {
  Timer? _heartbeat;

  @override
  SyncState build() {
    final ConnectivityService connectivity = ref.read(connectivityServiceProvider);

    final StreamSubscription<bool> subscription =
        connectivity.onStatusChanged.listen((bool online) {
      state = state.copyWith(isOnline: online, clearError: true);
      if (online) {
        unawaited(flush());
      }
    });

    // Retry heartbeat: keeps queued life-safety data moving without user action.
    _heartbeat = Timer.periodic(AppConfig.syncInterval, (_) {
      if (state.isOnline && state.pending > 0) {
        unawaited(flush());
      } else {
        refreshCounters();
      }
    });

    ref.onDispose(() {
      subscription.cancel();
      _heartbeat?.cancel();
    });

    unawaited(_initialise(connectivity));
    return const SyncState();
  }

  Future<void> _initialise(ConnectivityService connectivity) async {
    final bool online = await connectivity.checkOnline();
    state = state.copyWith(isOnline: online);
    refreshCounters();
    if (online) {
      await flush();
    }
  }

  OutboxStore get _outbox => ref.read(outboxStoreProvider);

  void refreshCounters() {
    state = state.copyWith(
      pending: _outbox.pendingCount,
      failed: _outbox.failed().length,
    );
  }

  /// Flush queued mutations. `force` ignores the connectivity gate (used by the
  /// "Sync now" button on the profile screen).
  Future<SyncResult?> flush({bool force = false}) async {
    if (state.isSyncing) return null;
    state = state.copyWith(isSyncing: true, clearError: true);
    try {
      final SyncResult result =
          await ref.read(syncServiceProvider).flush(force: force);
      final LocalStore store = ref.read(localStoreProvider);
      if (result.synced > 0) {
        await store.setString(
          LocalStore.keyLastSync,
          DateTime.now().toIso8601String(),
        );
      }
      state = state.copyWith(
        isSyncing: false,
        pending: result.remaining,
        failed: _outbox.failed().length,
        lastSyncedAt: result.synced > 0 ? DateTime.now() : state.lastSyncedAt,
      );
      return result;
    } catch (error) {
      state = state.copyWith(isSyncing: false, lastError: error.toString());
      return null;
    }
  }

  /// Called by repositories right after a mutation is queued so the banner
  /// updates without waiting for the heartbeat.
  void onMutationQueued() {
    refreshCounters();
    if (state.isOnline) {
      unawaited(flush());
    }
  }
}

/// Firebase Firestore dual-write service (STEP 5).
final Provider<FirestoreReportService> firestoreReportServiceProvider =
    Provider<FirestoreReportService>(
  (Ref ref) => FirestoreReportService(),
);

/// Firebase Storage upload service (STEP 5).
final Provider<StorageUploadService> storageUploadServiceProvider =
    Provider<StorageUploadService>(
  (Ref ref) => StorageUploadService(),
);
