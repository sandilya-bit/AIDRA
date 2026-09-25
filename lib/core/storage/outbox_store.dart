import '../config/app_config.dart';
import 'local_store.dart';

/// A single queued mutation (mirrors `sync_outbox` in the DB design §9.3).
class OutboxEntry {
  const OutboxEntry({
    required this.id,
    required this.type,
    required this.payload,
    required this.createdAt,
    this.attempts = 0,
    this.lastError,
  });

  final String id;
  final String type;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int attempts;
  final String? lastError;

  bool get isExhausted => attempts >= AppConfig.maxOutboxAttempts;

  OutboxEntry copyWith({int? attempts, String? lastError}) => OutboxEntry(
        id: id,
        type: type,
        payload: payload,
        createdAt: createdAt,
        attempts: attempts ?? this.attempts,
        lastError: lastError ?? this.lastError,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'type': type,
        'payload': payload,
        'created_at': createdAt.toIso8601String(),
        'attempts': attempts,
        if (lastError != null) 'last_error': lastError,
      };

  static OutboxEntry fromJson(Map<String, dynamic> json) => OutboxEntry(
        id: json['id']?.toString() ?? '',
        type: json['type']?.toString() ?? 'unknown',
        payload: (json['payload'] as Map<dynamic, dynamic>?)
                ?.cast<String, dynamic>() ??
            const <String, dynamic>{},
        createdAt:
            DateTime.tryParse(json['created_at']?.toString() ?? '') ??
                DateTime.now(),
        attempts: (json['attempts'] as num?)?.toInt() ?? 0,
        lastError: json['last_error']?.toString(),
      );
}

/// Durable FIFO queue of mutations waiting to reach the server.
class OutboxStore {
  OutboxStore(this._store);

  final LocalStore _store;

  List<OutboxEntry> all() => _store
      .getJsonList(LocalStore.keyOutbox)
      .map(OutboxEntry.fromJson)
      .toList(growable: false);

  List<OutboxEntry> pending() =>
      all().where((OutboxEntry e) => !e.isExhausted).toList(growable: false);

  List<OutboxEntry> failed() =>
      all().where((OutboxEntry e) => e.isExhausted).toList(growable: false);

  int get pendingCount => pending().length;

  Future<void> enqueue(OutboxEntry entry) async {
    final List<OutboxEntry> entries = all()
      ..removeWhere((OutboxEntry e) => e.id == entry.id)
      ..add(entry);
    await _persist(entries);
  }

  Future<void> markFailure(OutboxEntry entry, String error) async {
    final List<OutboxEntry> entries = all();
    final int index = entries.indexWhere((OutboxEntry e) => e.id == entry.id);
    if (index == -1) return;
    entries[index] = entries[index].copyWith(
      attempts: entries[index].attempts + 1,
      lastError: error,
    );
    await _persist(entries);
  }

  Future<void> remove(String id) async {
    final List<OutboxEntry> entries = all()
      ..removeWhere((OutboxEntry e) => e.id == id);
    await _persist(entries);
  }

  Future<void> clear() => _store.setJsonList(LocalStore.keyOutbox, <Map<String, dynamic>>[]);

  Future<void> _persist(List<OutboxEntry> entries) => _store.setJsonList(
        LocalStore.keyOutbox,
        entries.map((OutboxEntry e) => e.toJson()).toList(growable: false),
      );
}
