import 'package:aidra/core/config/app_config.dart';
import 'package:aidra/core/constants/app_enums.dart';
import 'package:aidra/core/error/failure.dart';
import 'package:aidra/core/models/emergency_report.dart';
import 'package:aidra/core/models/geo_point.dart';
import 'package:aidra/core/network/api_client.dart';
import 'package:aidra/core/network/connectivity_service.dart';
import 'package:aidra/core/storage/local_store.dart';
import 'package:aidra/core/storage/outbox_store.dart';
import 'package:aidra/core/sync/sync_service.dart';
import 'package:aidra/features/reports/data/report_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Always-offline connectivity double: the core scenario AIDRA is built for.
class _OfflineConnectivity extends ConnectivityService {
  @override
  Future<bool> checkOnline() async => false;
}

/// Always-online double, used to prove the replay path.
class _OnlineConnectivity extends ConnectivityService {
  @override
  Future<bool> checkOnline() async => true;
}

EmergencyReport _draft() => EmergencyReport(
      id: 'rep-test-1',
      code: 'AID-2026-000999',
      reporterId: 'usr-victim',
      inputType: ReportInputType.text,
      description: '5 people trapped in building near the river.',
      point: const GeoPoint(17.3850, 78.4867),
      urgencyUser: UrgencyLevel.critical,
      status: ReportStatus.submitting,
      createdAt: DateTime.now(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalStore store;
  late OutboxStore outbox;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = await LocalStore.init();
    outbox = OutboxStore(store);
  });

  group('Offline report submission (FR-105 / FR-1002)', () {
    test('persists the report locally and queues exactly one outbox entry',
        () async {
      final ReportRepositoryImpl repository = ReportRepositoryImpl(
        apiClient: ApiClient(),
        store: store,
        outbox: outbox,
        connectivity: _OfflineConnectivity(),
        onQueued: () {},
      );

      final EmergencyReport saved = await repository.submit(_draft());

      expect(saved.isPendingSync, isTrue);
      expect(saved.status, ReportStatus.queued);
      expect(outbox.pendingCount, 1);
      expect(outbox.pending().first.type, ReportRepositoryImpl.outboxType);

      // The report is readable from the local cache immediately.
      expect(
        repository.cachedReports().any((EmergencyReport r) => r.id == saved.id),
        isTrue,
      );
    });

    test('does not leak a second entry when the same report is re-submitted',
        () async {
      final ReportRepositoryImpl repository = ReportRepositoryImpl(
        apiClient: ApiClient(),
        store: store,
        outbox: outbox,
        connectivity: _OfflineConnectivity(),
        onQueued: () {},
      );

      await repository.submit(_draft());
      await repository.submit(_draft());

      // Two distinct mutations are queued, but the local cache holds one row.
      expect(outbox.pendingCount, 2);
      expect(repository.cachedReports().where((EmergencyReport r) => r.id == 'rep-test-1').length, 1);
    });

    test('notifies the sync controller whenever work is queued', () async {
      int notifications = 0;
      final ReportRepositoryImpl repository = ReportRepositoryImpl(
        apiClient: ApiClient(),
        store: store,
        outbox: outbox,
        connectivity: _OfflineConnectivity(),
        onQueued: () => notifications++,
      );

      await repository.submit(_draft());
      expect(notifications, 1);
    });
  });

  group('Sync service (offline replay)', () {
    test('does nothing while offline', () async {
      await outbox.enqueue(
        OutboxEntry(
          id: 'm1',
          type: 'report.create',
          payload: <String, dynamic>{'report': _draft().toJson()},
          createdAt: DateTime.now(),
        ),
      );

      final SyncService service = SyncService(
        outbox: outbox,
        connectivity: _OfflineConnectivity(),
      );
      service.register('report.create', (OutboxEntry entry) async {});

      final SyncResult result = await service.flush();
      expect(result.synced, 0);
      expect(result.remaining, 1);
    });

    test('replays queued work and clears the outbox when online', () async {
      await outbox.enqueue(
        OutboxEntry(
          id: 'm2',
          type: 'report.create',
          payload: <String, dynamic>{'report': _draft().toJson()},
          createdAt: DateTime.now(),
        ),
      );

      final List<String> replayed = <String>[];
      final SyncService service = SyncService(
        outbox: outbox,
        connectivity: _OnlineConnectivity(),
      );
      service.register('report.create', (OutboxEntry entry) async {
        replayed.add(entry.id);
      });

      final SyncResult result = await service.flush();
      expect(replayed, <String>['m2']);
      expect(result.synced, 1);
      expect(result.remaining, 0);
      expect(result.isClean, isTrue);
    });

    test('stops on a retryable failure to preserve FIFO ordering', () async {
      for (final String id in <String>['a', 'b']) {
        await outbox.enqueue(
          OutboxEntry(
            id: id,
            type: 'report.create',
            payload: <String, dynamic>{},
            createdAt: DateTime.now(),
          ),
        );
      }

      final List<String> attempts = <String>[];
      final SyncService service = SyncService(
        outbox: outbox,
        connectivity: _OnlineConnectivity(),
      );
      service.register('report.create', (OutboxEntry entry) async {
        attempts.add(entry.id);
        throw const NetworkFailure('Still unreachable');
      });

      final SyncResult result = await service.flush();
      expect(attempts, <String>['a']);
      expect(result.synced, 0);
      expect(result.failed, 1);
      expect(result.remaining, 2);
      // The failed entry recorded an attempt for the retry/backoff policy.
      expect(outbox.all().firstWhere((OutboxEntry e) => e.id == 'a').attempts, 1);
    });

    test('gives up after the configured attempt ceiling', () async {
      await outbox.enqueue(
        OutboxEntry(
          id: 'poison',
          type: 'report.create',
          payload: <String, dynamic>{},
          createdAt: DateTime.now(),
          attempts: AppConfig.maxOutboxAttempts,
        ),
      );

      expect(outbox.pending(), isEmpty);
      expect(outbox.failed().single.id, 'poison');
    });
  });

  group('LocalStore cache hygiene', () {
    test('trims cached lists to the configured maximum', () async {
      for (int i = 0; i < 10; i++) {
        await store.appendJsonItem(
          'cache.test',
          <String, dynamic>{'id': '$i'},
          maxItems: 5,
        );
      }
      expect(store.getJsonList('cache.test').length, 5);
      // Newest first.
      expect(store.getJsonList('cache.test').first['id'], '9');
    });

    test('survives corrupt JSON without throwing', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'cache.reports': 'not-json',
      });
      final LocalStore corrupt = await LocalStore.init();
      expect(corrupt.getJsonList('cache.reports'), isEmpty);
    });
  });
}
