import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'auth_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // FCM handles background notifications automatically.
}

class PushNotificationService {
  static final _messaging = FirebaseMessaging.instance;

  static Future<void> initialize() async {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      await _registerToken();
      _messaging.onTokenRefresh.listen(_sendTokenToBackend);
    }
  }

  static Future<void> _registerToken() async {
    try {
      // iOS requires APNS token before FCM token — wait up to 10s
      if (Platform.isIOS) {
        String? apns;
        for (var i = 0; i < 10 && apns == null; i++) {
          apns = await _messaging.getAPNSToken();
          if (apns == null) await Future.delayed(const Duration(seconds: 1));
        }
        if (apns == null) return; // APNS never arrived, skip
      }
      final token = await _messaging.getToken();
      if (token != null) await _sendTokenToBackend(token);
    } catch (_) {}
  }

  static Future<void> _sendTokenToBackend(String token) async {
    try {
      await AuthService.saveFcmToken(token);
    } catch (_) {}
  }
}
