import '../error/failure.dart';
import '../network/connectivity_service.dart';
import '../storage/outbox_store.dart';

/// Handler that replays one queued mutation against the server.
typedef OutboxHandler = Future<void> Function(OutboxEntry entry);

class SyncResult {
  const SyncResult({
    required this.synced,
    required this.failed,
    required this.remaining,
  });

  final int synced;
  final int failed;
  final int remaining;

  bool get isClean => failed == 0 && remaining == 0;
}

/// Flushes the offline outbox in FIFO order.
///
/// Ordering matters: a report must exist before its follow-up status update is
/// replayed, so the queue is never reordered. Failures increment an attempt
/// counter and stop the flush (head-of-line blocking is the safe behaviour for
/// life-safety data — we would rather retry than skip).
class SyncService {
  SyncService({
    required OutboxStore outbox,
    required ConnectivityService connectivity,
  })  : _outbox = outbox,
        _connectivity = connectivity;

  final OutboxStore _outbox;
  final ConnectivityService _connectivity;
  final Map<String, OutboxHandler> _handlers = <String, OutboxHandler>{};

  void register(String type, OutboxHandler handler) => _handlers[type] = handler;

  bool get isRegistered => _handlers.isNotEmpty;

  int get pendingCount => _outbox.pendingCount;

  Future<SyncResult> flush({bool force = false}) async {
    if (!force && !await _connectivity.checkOnline()) {
      return SyncResult(synced: 0, failed: 0, remaining: _outbox.pendingCount);
    }

    int synced = 0;
    int failed = 0;

    for (final OutboxEntry entry in _outbox.pending()) {
      final OutboxHandler? handler = _handlers[entry.type];
      if (handler == null) {
        await _outbox.markFailure(entry, 'No handler registered for ${entry.type}');
        failed++;
        continue;
      }
      try {
        await handler(entry);
        await _outbox.remove(entry.id);
        synced++;
      } on Failure catch (failure) {
        await _outbox.markFailure(entry, failure.message);
        failed++;
        if (failure.isRetryable) {
          // Stop: keep FIFO ordering intact and retry on the next connectivity
          // or heartbeat tick.
          break;
        }
      } catch (error) {
        await _outbox.markFailure(entry, error.toString());
        failed++;
        break;
      }
    }

    return SyncResult(
      synced: synced,
      failed: failed,
      remaining: _outbox.pendingCount,
    );
  }
}

/// Immutable sync status surfaced to the UI (offline banner, profile screen).
class SyncState {
  const SyncState({
    this.isOnline = true,
    this.isSyncing = false,
    this.pending = 0,
    this.failed = 0,
    this.lastSyncedAt,
    this.lastError,
  });

  final bool isOnline;
  final bool isSyncing;
  final int pending;
  final int failed;
  final DateTime? lastSyncedAt;
  final String? lastError;

  bool get isBlocked => failed > 0;

  SyncState copyWith({
    bool? isOnline,
    bool? isSyncing,
    int? pending,
    int? failed,
    DateTime? lastSyncedAt,
    String? lastError,
    bool clearError = false,
  }) {
    return SyncState(
      isOnline: isOnline ?? this.isOnline,
      isSyncing: isSyncing ?? this.isSyncing,
      pending: pending ?? this.pending,
      failed: failed ?? this.failed,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }
}
