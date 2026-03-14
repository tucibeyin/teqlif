import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'auth_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[FCM] Arka plan mesajı: ${message.messageId} | title=${message.notification?.title}');
}

class PushNotificationService {
  static final _messaging = FirebaseMessaging.instance;
  static bool _earlyDone = false;
  static bool _fullDone = false;

  /// Gelen FCM mesaj verisini broadcast eden stream.
  /// UI katmanları bunu dinleyerek anında güncellenir.
  static final StreamController<Map<String, dynamic>> notificationStream =
      StreamController<Map<String, dynamic>>.broadcast();

  /// main() içinde çağrılmalı — Firebase hazır olduktan hemen sonra.
  static Future<void> initEarly() async {
    if (_earlyDone) return;
    _earlyDone = true;

    debugPrint('[FCM] initEarly() başladı');

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    try {
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      debugPrint('[FCM] Foreground presentation options ayarlandı');
    } catch (e) {
      debugPrint('[FCM] setForegroundNotificationPresentationOptions HATA: $e');
    }

    // Foreground: uygulama açıkken gelen mesaj
    FirebaseMessaging.onMessage.listen((msg) {
      debugPrint('[FCM] Foreground mesaj | type=${msg.data["type"]} | title=${msg.notification?.title}');
      notificationStream.add(msg.data);
    });

    // Arka planda bildirime tıklanınca
    FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      debugPrint('[FCM] Bildirime tıklandı (arka plan) | type=${msg.data["type"]} | title=${msg.notification?.title}');
      notificationStream.add(msg.data);
    });

    // Uygulama kapalıyken bildirime tıklanınca (terminated)
    try {
      final initial = await _messaging.getInitialMessage();
      if (initial != null) {
        debugPrint('[FCM] Uygulama bildirimle açıldı | type=${initial.data["type"]} | title=${initial.notification?.title}');
        Future.delayed(const Duration(milliseconds: 500), () {
          notificationStream.add(initial.data);
        });
      } else {
        debugPrint('[FCM] getInitialMessage: null (normal açılış)');
      }
    } catch (e) {
      debugPrint('[FCM] getInitialMessage HATA: $e');
    }

    debugPrint('[FCM] initEarly() tamamlandı');
  }

  /// Kullanıcı giriş yaptıktan sonra çağrılmalı.
  static Future<void> initialize() async {
    debugPrint('[FCM] initialize() çağrıldı');
    await initEarly(); // idempotent
    if (_fullDone) return;
    _fullDone = true;

    debugPrint('[FCM] initialize() başladı — izin isteniyor');

    NotificationSettings settings;
    try {
      settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (e) {
      debugPrint('[FCM] requestPermission HATA: $e');
      return;
    }

    debugPrint('[FCM] İzin durumu: ${settings.authorizationStatus}');

    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      debugPrint('[FCM] İzin verildi — token alınıyor');
      await _registerToken();
      _messaging.onTokenRefresh.listen((token) {
        debugPrint('[FCM] Token yenilendi: ${token.substring(0, 12)}…');
        _sendTokenToBackend(token);
      });
    } else {
      debugPrint('[FCM] İzin VERİLMEDİ (${settings.authorizationStatus}) — push çalışmayacak');
    }
  }

  static Future<void> _registerToken() async {
    debugPrint('[FCM] _registerToken() başladı');
    try {
      if (Platform.isIOS) {
        debugPrint('[FCM] iOS: APNS token bekleniyor…');
        String? apns;
        for (var i = 0; i < 10 && apns == null; i++) {
          apns = await _messaging.getAPNSToken();
          debugPrint('[FCM] iOS: APNS token deneme ${i + 1}/10 = ${apns != null ? apns.substring(0, 8) + "…" : "null"}');
          if (apns == null) {
            await Future.delayed(const Duration(seconds: 1));
          }
        }
        if (apns == null) {
          debugPrint('[FCM] iOS: APNS token 10 denemede hiç gelmedi — FCM token alınamıyor');
          debugPrint('[FCM] iOS: Bu genellikle APNs sandbox sertifikası eksikliğinden kaynaklanır');
          return;
        }
        debugPrint('[FCM] iOS: APNS token alındı: ${apns.substring(0, 8)}…');
      }

      debugPrint('[FCM] FCM token alınıyor…');
      final token = await _messaging.getToken();
      if (token != null) {
        debugPrint('[FCM] FCM token alındı: ${token.substring(0, 16)}…');
        await _sendTokenToBackend(token);
      } else {
        debugPrint('[FCM] FCM token null — backend\'e gönderilemedi');
      }
    } catch (e, stack) {
      debugPrint('[FCM] _registerToken HATA: $e');
      debugPrint('[FCM] Stack: $stack');
    }
  }

  static Future<void> _sendTokenToBackend(String token) async {
    debugPrint('[FCM] Token backend\'e gönderiliyor: ${token.substring(0, 16)}…');
    try {
      await AuthService.saveFcmToken(token);
      debugPrint('[FCM] Token backend\'e başarıyla kaydedildi');
    } catch (e) {
      debugPrint('[FCM] Token backend\'e gönderilemedi: $e');
    }
  }
}
