import 'dart:io';
import 'dart:async';
import 'dart:developer' as dev;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'auth_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  dev.log('[FCM] Arka plan mesajı: ${message.messageId} | title=${message.notification?.title}', name: 'FCM');
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
  /// Background handler + foreground presentation options + mesaj dinleyicileri.
  /// Token almaz; kullanıcı girişi gerekmez.
  static Future<void> initEarly() async {
    if (_earlyDone) return;
    _earlyDone = true;

    dev.log('[FCM] initEarly() başladı', name: 'FCM');

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // iOS: uygulama açıkken de banner + badge + ses göster
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Foreground: uygulama açıkken gelen mesaj
    FirebaseMessaging.onMessage.listen((msg) {
      dev.log(
        '[FCM] Foreground mesaj | type=${msg.data["type"]} | title=${msg.notification?.title}',
        name: 'FCM',
      );
      notificationStream.add(msg.data);
    });

    // Arka planda bildirime tıklanınca
    FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      dev.log('[FCM] Bildirime tıklandı (arka plan) | type=${msg.data["type"]} | title=${msg.notification?.title}', name: 'FCM');
      notificationStream.add(msg.data);
    });

    // Uygulama kapalıyken bildirime tıklanınca (terminated)
    final initial = await _messaging.getInitialMessage();
    if (initial != null) {
      dev.log('[FCM] Uygulama bildirimle açıldı | type=${initial.data["type"]} | title=${initial.notification?.title}', name: 'FCM');
      // UI hazır olana kadar kısa bekle
      Future.delayed(const Duration(milliseconds: 500), () {
        notificationStream.add(initial.data);
      });
    }

    dev.log('[FCM] initEarly() tamamlandı', name: 'FCM');
  }

  /// Kullanıcı giriş yaptıktan sonra çağrılmalı.
  /// İzin ister, FCM token alır ve backend'e kaydeder.
  static Future<void> initialize() async {
    await initEarly(); // idempotent
    if (_fullDone) return;
    _fullDone = true;

    dev.log('[FCM] initialize() başladı', name: 'FCM');

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
