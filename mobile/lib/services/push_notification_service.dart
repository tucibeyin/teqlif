import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'auth_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[FCM] Arka plan mesajı: ${message.messageId}');
}

class PushNotificationService {
  static final _messaging = FirebaseMessaging.instance;
  static bool _earlyDone = false;
  static bool _fullDone = false;

  /// Gelen FCM mesaj verisini broadcast eden stream.
  /// UI katmanları bunu dinleyerek anında güncellenir.
  static final StreamController<Map<String, dynamic>> notificationStream =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Badge güncellenmesi gerektiğinde sinyal gönderir.
  /// Mesaj okunduğunda veya liste yenilendiğinde emit edilir.
  static final StreamController<void> badgeRefreshNeeded =
      StreamController<void>.broadcast();

  /// main() içinde çağrılmalı — Firebase hazır olduktan hemen sonra.
  /// Background handler + foreground presentation options + mesaj dinleyicileri.
  /// Token almaz; kullanıcı girişi gerekmez.
  static Future<void> initEarly() async {
    if (_earlyDone) return;
    _earlyDone = true;

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    FirebaseMessaging.onMessage.listen((msg) {
      notificationStream.add(msg.data);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      notificationStream.add(msg.data);
    });

    final initial = await _messaging.getInitialMessage();
    if (initial != null) {
      Future.delayed(const Duration(milliseconds: 500), () {
        notificationStream.add(initial.data);
      });
    }
  }

  /// Kullanıcı giriş yaptıktan sonra çağrılmalı.
  /// İzin ister, FCM token alır ve backend'e kaydeder.
  static Future<void> initialize() async {
    await initEarly();
    if (_fullDone) return;
    _fullDone = true;

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
      final token = await _messaging.getToken();
      if (token != null) {
        await _sendTokenToBackend(token);
      }
    } catch (e) {
      debugPrint('[FCM] Token alınamadı: $e');
    }
  }

  static Future<void> _sendTokenToBackend(String token) async {
    try {
      await AuthService.saveFcmToken(token);
      debugPrint('[FCM] Token backend\'e kaydedildi');
    } catch (e) {
      debugPrint('[FCM] Token backend\'e gönderilemedi: $e');
    }
  }
}
