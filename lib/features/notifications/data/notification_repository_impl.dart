import '../../../core/config/app_config.dart';
import '../../../core/constants/app_enums.dart';
import '../../../core/data/demo_data.dart';
import '../../../core/error/failure.dart';
import '../../../core/models/app_notification.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/local_store.dart';
import '../domain/notification_repository.dart';

/// Notifications + broadcasts.
///
/// Read state is tracked locally so it survives a restart *and* works with no
/// connectivity — a responder marking an alert read in a dead zone must not
/// see it resurface when the app is relaunched.
class NotificationRepositoryImpl implements NotificationRepository {
  NotificationRepositoryImpl({
    required ApiClient apiClient,
    required LocalStore store,
  })  : _api = apiClient,
        _store = store;

  static const String keyReadIds = 'notifications.read_ids';

  final ApiClient _api;
  final LocalStore _store;

  Set<String> get _readIds => _store
      .getJsonList(keyReadIds)
      .map((Map<String, dynamic> e) => e['id']?.toString() ?? '')
      .where((String id) => id.isNotEmpty)
      .toSet();

  @override
  Future<List<AppNotification>> fetchNotifications({int limit = 50}) async {
    List<AppNotification> notifications;

    if (AppConfig.useRemoteBackend) {
      try {
        final List<dynamic> items = await _api.getList(
          '/notifications',
          query: <String, dynamic>{'limit': limit},
        );
        notifications = items
            .whereType<Map<dynamic, dynamic>>()
            .map((Map<dynamic, dynamic> e) =>
                AppNotification.fromJson(e.cast<String, dynamic>()))
            .toList(growable: false);
        if (notifications.isEmpty) {
          notifications = _localNotifications();
        } else {
          await _store.setJsonList(
            LocalStore.keyCachedNotifications,
            notifications.map((AppNotification n) => n.toJson()).toList(growable: false),
          );
        }
      } on Failure catch (_) {
        notifications = _localNotifications();
      }
    } else {
      notifications = _localNotifications();
    }

    final Set<String> read = _readIds;
    final List<AppNotification> withReadState = notifications
        .map((AppNotification n) => n.copyWith(isRead: n.isRead || read.contains(n.id)))
        .toList(growable: false);

    withReadState.sort((AppNotification a, AppNotification b) {
      // P0 first, then newest — the escalation matrix ordering (Vol II §7.1).
      final int byPriority = a.priority.index.compareTo(b.priority.index);
      if (byPriority != 0) return byPriority;
      return b.createdAt.compareTo(a.createdAt);
    });

    return withReadState;
  }

  @override
  Future<AppNotification> markRead(String id) async {
    await _persistRead(id);
    if (AppConfig.useRemoteBackend) {
      try {
        await _api.patchJson('/notifications/$id', <String, dynamic>{'read': true});
      } on Failure catch (_) {
        // Queued for replay.
      }
    }
    final List<AppNotification> all = _localNotifications();
    for (final AppNotification notification in all) {
      if (notification.id == id) return notification.copyWith(isRead: true);
    }
    return AppNotification(
      id: id,
      title: 'AIDRA',
      body: '',
      eventType: 'system',
      priority: NotificationPriority.p2,
      createdAt: DateTime.now(),
      isRead: true,
    );
  }

  @override
  Future<void> markAllRead() async {
    for (final AppNotification notification in _localNotifications()) {
      await _persistRead(notification.id);
    }
    if (AppConfig.useRemoteBackend) {
      try {
        await _api.patchJson('/notifications', <String, dynamic>{'read_all': true});
      } on Failure catch (_) {
        // Queued for replay.
      }
    }
  }

  @override
  Future<List<Broadcast>> fetchBroadcasts() async {
    if (AppConfig.useRemoteBackend) {
      try {
        final List<dynamic> items = await _api.getList('/broadcasts');
        final List<Broadcast> broadcasts = items
            .whereType<Map<dynamic, dynamic>>()
            .map((Map<dynamic, dynamic> e) => Broadcast.fromJson(e.cast<String, dynamic>()))
            .toList(growable: false);
        if (broadcasts.isNotEmpty) return broadcasts;
      } on Failure catch (_) {
        return DemoData.broadcasts();
      }
    }
    return DemoData.broadcasts();
  }

  Future<void> _persistRead(String id) async {
    final Set<String> ids = _readIds..add(id);
    await _store.setJsonList(
      keyReadIds,
      ids.map((String value) => <String, dynamic>{'id': value}).toList(growable: false),
    );
  }

  List<AppNotification> _localNotifications() {
    final List<Map<String, dynamic>> cached =
        _store.getJsonList(LocalStore.keyCachedNotifications);
    if (cached.isEmpty) return DemoData.notifications();
    return cached.map(AppNotification.fromJson).toList(growable: false);
  }
}
