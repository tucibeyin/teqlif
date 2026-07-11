import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'auth_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // iOS terminated state: this handler runs in a separate isolate.
  // Firebase is already initialized by FlutterFire before this is called.
  debugPrint('[FCM][BG] Arka plan mesajı alındı | id=${message.messageId} | type=${message.data['type']}');
}

class PushNotificationService {
  static final _messaging = FirebaseMessaging.instance;
  static bool _earlyDone = false;
  static bool _fullDone = false;

  /// Gelen FCM mesaj verisini broadcast eden stream.
  static final StreamController<Map<String, dynamic>> notificationStream =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Badge güncellenmesi gerektiğinde sinyal gönderir.
  static final StreamController<void> badgeRefreshNeeded =
      StreamController<void>.broadcast();

  /// Cold-start: uygulama kapalıyken tıklanan bildirimin verisi.
  static Map<String, dynamic>? _pendingNavData;

  static Map<String, dynamic>? consumePendingNavigation() {
    final data = _pendingNavData;
    _pendingNavData = null;
    return data;
  }

  /// main() içinde çağrılmalı — background handler + foreground options.
  static Future<void> initEarly() async {
    if (_earlyDone) return;
    _earlyDone = true;
    debugPrint('[FCM] initEarly başladı');

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    FirebaseMessaging.onMessage.listen((msg) {
      debugPrint('[FCM] Foreground mesaj | type=${msg.data['type']} | title=${msg.notification?.title}');
      notificationStream.add(msg.data.isEmpty ? {} : msg.data);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      debugPrint('[FCM] Background tap | type=${msg.data['type']}');
      notificationStream.add(msg.data);
    });

    final initial = await _messaging.getInitialMessage();
    if (initial != null) {
      debugPrint('[FCM] Cold-start tap | type=${initial.data['type']}');
      if (initial.data.isNotEmpty) {
        _pendingNavData = initial.data;
        Future.microtask(() => notificationStream.add(initial.data));
      }
    } else {
      debugPrint('[FCM] Cold-start: bildirim tıklaması yok');
    }

    debugPrint('[FCM] initEarly tamamlandı');
  }

  /// Kullanıcı giriş yaptıktan sonra çağrılmalı.
  /// İzin ister, FCM token alır ve backend'e kaydeder.
  static Future<void> initialize() async {
    debugPrint('[FCM] initialize çağrıldı | earlyDone=$_earlyDone | fullDone=$_fullDone');
    await initEarly();
    if (_fullDone) {
      debugPrint('[FCM] initialize: zaten tamamlanmış, çıkılıyor');
      return;
    }
    _fullDone = true;

    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    debugPrint('[FCM] İzin durumu: ${settings.authorizationStatus}');

    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      await _registerToken();
      _messaging.onTokenRefresh.listen((newToken) {
        debugPrint('[FCM] Token yenilendi, backend güncelleniyor');
        _sendTokenToBackend(newToken);
      });
    } else {
      debugPrint('[FCM] Push izni verilmedi: ${settings.authorizationStatus}');
    }
  }

  /// Token yenileme için — kullanıcı değiştiğinde veya uygulama güncellendiğinde
  /// initialize() zaten çalıştıysa bile token'ı zorla yeniden kaydet.
  static Future<void> refreshToken() async {
    debugPrint('[FCM] refreshToken çağrıldı');
    await _registerToken();
  }

  static Future<void> _registerToken() async {
    try {
      // APNS token (iOS için) — FCM token'dan önce alınmalı
      if (!kIsWeb) {
        try {
          final apnsToken = await _messaging.getAPNSToken();
          debugPrint('[FCM] APNS token: ${apnsToken != null ? "${apnsToken.substring(0, 12)}…" : "NULL"}');
          if (apnsToken == null) {
            debugPrint('[FCM] UYARI: APNS token null — iOS push çalışmayabilir!');
          }
        } catch (e) {
          debugPrint('[FCM] APNS token alınamadı: $e');
        }
      }

      final token = await _messaging.getToken();
      debugPrint('[FCM] FCM token: ${token != null ? "${token.substring(0, 20)}…" : "NULL"}');
      if (token != null) {
        await _sendTokenToBackend(token);
      } else {
        debugPrint('[FCM] HATA: FCM token null — push bildirimleri çalışmayacak!');
      }
    } catch (e) {
      debugPrint('[FCM] Token alınamadı: $e');
    }
  }

  static Future<void> _sendTokenToBackend(String token) async {
    try {
      debugPrint('[FCM] Token backend\'e gönderiliyor: ${token.substring(0, 20)}…');
      await AuthService.saveFcmToken(token);
      debugPrint('[FCM] Token backend\'e kaydedildi ✓');
    } catch (e) {
      debugPrint('[FCM] Token backend\'e gönderilemedi: $e');
    }
  }
}
