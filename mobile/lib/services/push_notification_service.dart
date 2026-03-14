import 'dart:io';
import 'dart:developer' as dev;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'auth_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  dev.log('[FCM] Arka plan mesajı: ${message.messageId} | title=${message.notification?.title}', name: 'FCM');
}

class PushNotificationService {
  static final _messaging = FirebaseMessaging.instance;

  static Future<void> initialize() async {
    dev.log('[FCM] initialize() başladı', name: 'FCM');
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    dev.log('[FCM] İzin durumu: ${settings.authorizationStatus}', name: 'FCM');

    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      await _registerToken();
      _messaging.onTokenRefresh.listen((token) {
        dev.log('[FCM] Token yenilendi: ${token.substring(0, 12)}…', name: 'FCM');
        _sendTokenToBackend(token);
      });
    } else {
      dev.log('[FCM] İzin verilmedi — push çalışmayacak', name: 'FCM');
    }

    // Foreground mesaj geldiğinde logla
    FirebaseMessaging.onMessage.listen((msg) {
      dev.log(
        '[FCM] Foreground mesaj geldi | title=${msg.notification?.title} | body=${msg.notification?.body}',
        name: 'FCM',
      );
    });

    // Uygulama arka plandayken bildirime tıklanınca logla
    FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      dev.log('[FCM] Bildirime tıklandı (arka plan): ${msg.notification?.title}', name: 'FCM');
    });

    // Uygulama kapalıyken bildirime tıklanınca logla
    final initial = await _messaging.getInitialMessage();
    if (initial != null) {
      dev.log('[FCM] Uygulama bildirimle açıldı: ${initial.notification?.title}', name: 'FCM');
    }
  }

  static Future<void> _registerToken() async {
    try {
      if (Platform.isIOS) {
        dev.log('[FCM] iOS: APNS token bekleniyor…', name: 'FCM');
        String? apns;
        for (var i = 0; i < 10 && apns == null; i++) {
          apns = await _messaging.getAPNSToken();
          if (apns == null) {
            dev.log('[FCM] iOS: APNS token yok (${i + 1}/10)…', name: 'FCM');
            await Future.delayed(const Duration(seconds: 1));
          }
        }
        if (apns == null) {
          dev.log('[FCM] iOS: APNS token hiç gelmedi — FCM token alınamıyor', name: 'FCM');
          return;
        }
        dev.log('[FCM] iOS: APNS token alındı', name: 'FCM');
      }
      final token = await _messaging.getToken();
      if (token != null) {
        dev.log('[FCM] FCM token alındı: ${token.substring(0, 12)}…', name: 'FCM');
        await _sendTokenToBackend(token);
      } else {
        dev.log('[FCM] FCM token null — backend\'e gönderilemedi', name: 'FCM');
      }
    } catch (e) {
      dev.log('[FCM] _registerToken hata: $e', name: 'FCM');
    }
  }

  static Future<void> _sendTokenToBackend(String token) async {
    try {
      dev.log('[FCM] Token backend\'e gönderiliyor…', name: 'FCM');
      await AuthService.saveFcmToken(token);
      dev.log('[FCM] Token backend\'e kaydedildi', name: 'FCM');
    } catch (e) {
      dev.log('[FCM] Token backend\'e gönderilemedi: $e', name: 'FCM');
    }
  }
}
