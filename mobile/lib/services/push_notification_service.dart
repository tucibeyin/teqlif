import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import 'storage_service.dart';
import '../config/api.dart';

// ─── Action IDs ──────────────────────────────────────────────────────────────

const _kActionAccept = 'call_accept';
const _kActionDecline = 'call_decline';
const _kChannelCalls = 'incoming_calls';
const _kCategoryCall = 'incoming_call_category';

// ─── Plugin singleton ─────────────────────────────────────────────────────────

final FlutterLocalNotificationsPlugin _flnp = FlutterLocalNotificationsPlugin();

// ─── Background FCM handler (separate isolate) ────────────────────────────────

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[FCM][BG] type=${message.data['type']}');

  if (message.data['type'] == 'incoming_call') {
    await _showCallNotification(
      callId: message.data['call_id'] ?? '',
      callerUsername: message.data['caller_username'] ?? '',
    );
  }
}

/// Show a local call notification with Accept/Decline action buttons.
Future<void> _showCallNotification({
  required String callId,
  required String callerUsername,
}) async {
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosInit = DarwinInitializationSettings();
  await _flnp.initialize(const InitializationSettings(android: androidInit, iOS: iosInit));

  const androidDetails = AndroidNotificationDetails(
    _kChannelCalls,
    'Gelen Aramalar',
    channelDescription: 'Sesli arama bildirimleri',
    importance: Importance.max,
    priority: Priority.max,
    fullScreenIntent: true,
    category: AndroidNotificationCategory.call,
    actions: [
      AndroidNotificationAction(
        _kActionDecline,
        'Reddet',
        showsUserInterface: false,
        cancelNotification: true,
      ),
      AndroidNotificationAction(
        _kActionAccept,
        'Kabul Et',
        showsUserInterface: true,
        cancelNotification: true,
      ),
    ],
  );

  const iosDetails = DarwinNotificationDetails(
    categoryIdentifier: _kCategoryCall,
  );

  await _flnp.show(
    callId.hashCode,
    callerUsername,
    'Sesli arama geliyor...',
    const NotificationDetails(android: androidDetails, iOS: iosDetails),
    payload: callId,
  );
}

// ─── Background notification action handler (separate isolate) ───────────────

@pragma('vm:entry-point')
Future<void> _backgroundNotifResponseHandler(NotificationResponse response) async {
  final callId = response.payload;
  if (callId == null || callId.isEmpty) return;

  if (response.actionId == _kActionDecline) {
    // Reject call via API directly — no app state available here.
    try {
      final token = await StorageService.getToken();
      if (token != null) {
        await http.post(
          Uri.parse('$kBaseUrl/calls/$callId/reject'),
          headers: {'Authorization': 'Bearer $token'},
        );
      }
    } catch (e) {
      debugPrint('[FCM][BG] Call reject failed: $e');
    }
  }
  // Accept action: app opens via showsUserInterface:true,
  // IncomingCallOverlay handles it through notificationStream.
}

// ─── PushNotificationService ──────────────────────────────────────────────────

class PushNotificationService {
  static final _messaging = FirebaseMessaging.instance;
  static bool _earlyDone = false;
  static bool _fullDone = false;
  static bool _tokenForcedRefreshed = false;

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

    // ── flutter_local_notifications setup ──────────────────────────────────
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    final iosInit = DarwinInitializationSettings(
      notificationCategories: [
        DarwinNotificationCategory(
          _kCategoryCall,
          actions: [
            DarwinNotificationAction.plain(
              _kActionDecline,
              'Reddet',
              options: {DarwinNotificationActionOption.destructive},
            ),
            DarwinNotificationAction.plain(
              _kActionAccept,
              'Kabul Et',
            ),
          ],
        ),
      ],
    );
    await _flnp.initialize(
      InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: _onNotifResponse,
      onDidReceiveBackgroundNotificationResponse: _backgroundNotifResponseHandler,
    );

    // Create Android notification channel for calls
    const callChannel = AndroidNotificationChannel(
      _kChannelCalls,
      'Gelen Aramalar',
      description: 'Sesli arama bildirimleri',
      importance: Importance.max,
    );
    final androidPlugin = _flnp.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(callChannel);
    // ──────────────────────────────────────────────────────────────────────

    FirebaseMessaging.onMessage.listen((msg) {
      debugPrint('[FCM] Foreground mesaj | type=${msg.data['type']}');
      final data = msg.data.isEmpty ? <String, dynamic>{} : Map<String, dynamic>.from(msg.data);
      if (data['type'] == 'incoming_call') {
        // Foreground call: directly route — no local notification needed
        notificationStream.add(data);
      } else {
        notificationStream.add(data);
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      debugPrint('[FCM] Background tap | type=${msg.data['type']}');
      notificationStream.add(Map<String, dynamic>.from(msg.data));
    });

    final initial = await _messaging.getInitialMessage();
    if (initial != null) {
      debugPrint('[FCM] Cold-start tap | type=${initial.data['type']}');
      if (initial.data.isNotEmpty) {
        _pendingNavData = Map<String, dynamic>.from(initial.data);
        Future.microtask(() => notificationStream.add(_pendingNavData!));
      }
    } else {
      debugPrint('[FCM] Cold-start: bildirim tıklaması yok');
    }

    // Check if app was opened by tapping local notification
    final launchDetails = await _flnp.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      final response = launchDetails!.notificationResponse;
      if (response != null) {
        Future.microtask(() => _onNotifResponse(response));
      }
    }

    debugPrint('[FCM] initEarly tamamlandı');
  }

  /// Foreground or app-open notification response handler.
  static void _onNotifResponse(NotificationResponse response) {
    debugPrint('[FLNP] Notif response | actionId=${response.actionId} | payload=${response.payload}');
    final callId = response.payload;
    if (callId == null || callId.isEmpty) return;

    if (response.actionId == _kActionDecline) {
      // Decline in foreground — fire and forget
      _rejectCallById(callId);
    } else {
      // Accept or direct tap: route to IncomingCallScreen via stream
      notificationStream.add({
        'type': 'incoming_call_notification_tap',
        'call_id': callId,
      });
    }
  }

  static Future<void> _rejectCallById(String callId) async {
    try {
      final token = await StorageService.getToken();
      if (token != null) {
        await http.post(
          Uri.parse('$kBaseUrl/calls/$callId/reject'),
          headers: {'Authorization': 'Bearer $token'},
        );
      }
    } catch (e) {
      debugPrint('[FCM] Call reject failed: $e');
    }
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
      _messaging.onTokenRefresh.listen((newToken) {
        debugPrint('[FCM] Token yenilendi, backend güncelleniyor');
        _sendTokenToBackend(newToken);
      });
      await _registerToken();
    } else {
      debugPrint('[FCM] Push izni verilmedi: ${settings.authorizationStatus}');
    }
  }

  /// Token yenileme — kullanıcı değiştiğinde veya uygulama güncellendiğinde.
  static Future<void> refreshToken() async {
    debugPrint('[FCM] refreshToken çağrıldı');
    if (!_tokenForcedRefreshed) {
      _tokenForcedRefreshed = true;
      try {
        await _messaging.deleteToken();
        debugPrint('[FCM] Eski token silindi — taze token alınacak');
      } catch (e) {
        debugPrint('[FCM] Token silinemedi: $e');
      }
    }
    await _registerToken();
  }

  static Future<void> _registerToken() async {
    try {
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
