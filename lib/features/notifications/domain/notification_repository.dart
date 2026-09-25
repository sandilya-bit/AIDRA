import '../../../core/models/app_notification.dart';

/// Notification boundary (FR-801–803, PRD Volume II §7).
abstract class NotificationRepository {
  Future<List<AppNotification>> fetchNotifications({int limit = 50});

  Future<AppNotification> markRead(String id);

  Future<void> markAllRead();

  /// Area broadcasts the user is eligible to see (polygon matched).
  Future<List<Broadcast>> fetchBroadcasts();
}
