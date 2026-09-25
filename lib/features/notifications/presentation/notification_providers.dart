import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/models/app_notification.dart';
import '../data/notification_repository_impl.dart';
import '../domain/notification_repository.dart';

final Provider<NotificationRepository> notificationRepositoryProvider =
    Provider<NotificationRepository>(
  (Ref ref) => NotificationRepositoryImpl(
    apiClient: ref.watch(apiClientProvider),
    store: ref.watch(localStoreProvider),
  ),
);

final AsyncNotifierProvider<NotificationsController, List<AppNotification>>
    notificationsProvider =
    AsyncNotifierProvider<NotificationsController, List<AppNotification>>(
  NotificationsController.new,
);

class NotificationsController extends AsyncNotifier<List<AppNotification>> {
  @override
  Future<List<AppNotification>> build() =>
      ref.watch(notificationRepositoryProvider).fetchNotifications();

  Future<void> refresh() async {
    state = await AsyncValue.guard(
      () => ref.read(notificationRepositoryProvider).fetchNotifications(),
    );
  }

  Future<void> markRead(String id) async {
    await ref.read(notificationRepositoryProvider).markRead(id);
    await refresh();
  }

  Future<void> markAllRead() async {
    await ref.read(notificationRepositoryProvider).markAllRead();
    await refresh();
  }
}

/// Badge count for the dashboard bell.
final Provider<int> unreadNotificationCountProvider = Provider<int>((Ref ref) {
  final List<AppNotification> notifications =
      ref.watch(notificationsProvider).valueOrNull ?? const <AppNotification>[];
  return notifications.where((AppNotification n) => !n.isRead).length;
});

/// P0/P1 notifications that demand immediate attention.
final Provider<List<AppNotification>> urgentNotificationsProvider =
    Provider<List<AppNotification>>((Ref ref) {
  final List<AppNotification> notifications =
      ref.watch(notificationsProvider).valueOrNull ?? const <AppNotification>[];
  return notifications
      .where((AppNotification n) =>
          !n.isRead && n.priority.bypassesQuietHours)
      .toList(growable: false);
});

/// Notifications grouped by event family, for the sectioned inbox.
final Provider<Map<String, List<AppNotification>>> groupedNotificationsProvider =
    Provider<Map<String, List<AppNotification>>>((Ref ref) {
  final List<AppNotification> notifications =
      ref.watch(notificationsProvider).valueOrNull ?? const <AppNotification>[];
  final Map<String, List<AppNotification>> grouped =
      <String, List<AppNotification>>{};
  for (final AppNotification notification in notifications) {
    final String family = notification.eventType.split('.').first;
    grouped.putIfAbsent(family, () => <AppNotification>[]).add(notification);
  }
  return grouped;
});

final FutureProvider<List<Broadcast>> broadcastsProvider =
    FutureProvider<List<Broadcast>>(
  (Ref ref) => ref.watch(notificationRepositoryProvider).fetchBroadcasts(),
);

/// Notification preferences (channels + quiet hours), persisted locally.
class NotificationPreferences {
  const NotificationPreferences({
    this.push = true,
    this.sms = true,
    this.email = true,
    this.quietHoursEnabled = false,
    this.criticalBypass = true,
  });

  final bool push;
  final bool sms;
  final bool email;
  final bool quietHoursEnabled;
  final bool criticalBypass;

  NotificationPreferences copyWith({
    bool? push,
    bool? sms,
    bool? email,
    bool? quietHoursEnabled,
    bool? criticalBypass,
  }) {
    return NotificationPreferences(
      push: push ?? this.push,
      sms: sms ?? this.sms,
      email: email ?? this.email,
      quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
      criticalBypass: criticalBypass ?? this.criticalBypass,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'push': push,
        'sms': sms,
        'email': email,
        'quiet_hours_enabled': quietHoursEnabled,
        'critical_bypass': criticalBypass,
      };
}

final NotifierProvider<NotificationPreferencesController, NotificationPreferences>
    notificationPreferencesProvider =
    NotifierProvider<NotificationPreferencesController, NotificationPreferences>(
  NotificationPreferencesController.new,
);

class NotificationPreferencesController extends Notifier<NotificationPreferences> {
  static const String storageKey = 'settings.notification_prefs';

  @override
  NotificationPreferences build() {
    final Map<String, dynamic>? stored =
        ref.watch(localStoreProvider).getJson(storageKey);
    if (stored == null) return const NotificationPreferences();
    return NotificationPreferences(
      push: stored['push'] as bool? ?? true,
      sms: stored['sms'] as bool? ?? true,
      email: stored['email'] as bool? ?? true,
      quietHoursEnabled: stored['quiet_hours_enabled'] as bool? ?? false,
      criticalBypass: stored['critical_bypass'] as bool? ?? true,
    );
  }

  Future<void> update(NotificationPreferences preferences) async {
    state = preferences;
    await ref.read(localStoreProvider).setJson(storageKey, preferences.toJson());
  }
}
