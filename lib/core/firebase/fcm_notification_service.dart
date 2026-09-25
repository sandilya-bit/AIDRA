import 'dart:async';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../config/app_config.dart';
import '../network/api_client.dart';

/// Service responsible for FCM device-token registration, push notification
/// permissions, and background/foreground notification event handling.
class FcmNotificationService {
  FcmNotificationService({required ApiClient apiClient})
      : _apiClient = apiClient;

  final ApiClient _apiClient;
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _messageSub;

  /// Initializes push notification handlers and token registration.
  Future<void> initialize() async {
    if (!AppConfig.useFirebase) return;

    try {
      if (Firebase.apps.isEmpty) return;

      final FirebaseMessaging messaging = FirebaseMessaging.instance;

      // Request notification permissions
      final NotificationSettings settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        final String? token = await messaging.getToken();
        if (token != null) {
          await registerToken(token);
        }

        // Listen for token updates
        _tokenRefreshSub = messaging.onTokenRefresh.listen((String newToken) {
          registerToken(newToken);
        });

        // Listen for foreground notifications
        _messageSub = FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          _handleForegroundMessage(message);
        });
      }
    } catch (_) {
      // Non-fatal if FCM setup fails or credentials absent
    }
  }

  /// Sends the device token to the AIDRA backend for targeted dispatch.
  Future<void> registerToken(String fcmToken) async {
    final String platform = Platform.isAndroid
        ? 'android'
        : Platform.isIOS
            ? 'ios'
            : 'web';

    try {
      await _apiClient.post(
        '/devices/register',
        data: <String, dynamic>{
          'fcm_token': fcmToken,
          'platform': platform,
        },
      );
    } catch (_) {
      // If remote backend is unreachable, token registration will be retried
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    // Message received in foreground — app UI can show a snackbar/toast
    // or notify local notification store
  }

  void dispose() {
    _tokenRefreshSub?.cancel();
    _messageSub?.cancel();
  }
}
