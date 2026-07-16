import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import 'storage_service.dart';
import 'call_service.dart';
import '../l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api.dart';

void _cpLog(String phase, String msg) {
  debugPrint('[CALL_PROCESS][${DateTime.now().toIso8601String()}][$phase] $msg');
}

// ─── Action IDs ──────────────────────────────────────────────────────────────

const _kActionAccept  = 'call_accept';
const _kActionDecline = 'call_decline';
const _kChannelCalls  = 'incoming_calls';
const _kCategoryCall  = 'incoming_call_category';

// ─── Plugin singleton ─────────────────────────────────────────────────────────

final FlutterLocalNotificationsPlugin _flnp = FlutterLocalNotificationsPlugin();



// ─── Background FCM handler (separate isolate) ────────────────────────────────

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[FCM][BG] mesaj geldi | type=${message.data['type']} | keys=${message.data.keys.toList()}');

  if (message.data['type'] == 'incoming_call') {
    debugPrint('[FCM][BG] incoming_call işleniyor | call_id=${message.data['call_id']}');
    // Flutter binding'i background isolate için başlat
    WidgetsFlutterBinding.ensureInitialized();
    await _showCallNotification(
      callId:         message.data['call_id']         ?? '',
      callerUsername: message.data['caller_username'] ?? '',
      callerAvatar:   message.data['caller_avatar']   ?? '',
      callerId:       message.data['caller_id']       ?? '',
      roomName:       message.data['room_name']       ?? '',
      livekitUrl:     message.data['livekit_url']     ?? '',
      calleeToken:    message.data['callee_token']    ?? '',
    );
  } else if (message.data['type'] == 'call_ended' || message.data['type'] == 'call_missed' || message.data['type'] == 'call_rejected') {
    debugPrint('[FCM][BG] Call cancelled by caller (${message.data['type']}). Ending CallKit.');
    final callId = message.data['call_id']?.toString() ?? '';
    if (callId.isNotEmpty) {
      final callUuid = formatToUuid(callId);
      await FlutterCallkitIncoming.endCall(callUuid);
    } else {
      await FlutterCallkitIncoming.endAllCalls();
    }
  } else {
    debugPrint('[FCM][BG] arama dışı type, işlem yok');
  }
}

String formatToUuid(String id) {
  // CallKit iOS'te id'nin kesinlikle geçerli bir UUID (8-4-4-4-12) formatında olmasını ister.
  // Veritabanındaki integer/string call_id'yi bu formata uyduruyoruz.
  final padded = id.padLeft(32, '0');
  return '${padded.substring(0, 8)}-${padded.substring(8, 12)}-${padded.substring(12, 16)}-${padded.substring(16, 20)}-${padded.substring(20, 32)}';
}

/// Yerel bildirim göster — background isolate veya foreground'dan çağrılabilir.
Future<void> _showCallNotification({
  required String callId,
  required String callerUsername,
  String callerAvatar = '',
  String callerId     = '',
  String roomName     = '',
  String livekitUrl   = '',
  String calleeToken  = '',
}) async {
  debugPrint('[CallKit] _showCallNotification başlıyor | callId=$callId | caller=$callerUsername');

  // Load language from shared prefs since we have no BuildContext
  String langCode = 'tr';
  try {
    final prefs = await SharedPreferences.getInstance();
    langCode = prefs.getString('app_locale_language_code') ?? 'tr';
  } catch (_) {}
  
  final l = lookupAppLocalizations(Locale(langCode));

  final callUuid = formatToUuid(callId);

  final params = CallKitParams(
    id: callUuid,
    nameCaller: callerUsername,
    appName: 'teqlif',
    avatar: callerAvatar.isNotEmpty ? callerAvatar : 'https://i.pravatar.cc/100',
    handle: l.callVoiceCall,
    type: 0,
    duration: 45000,
    missedCallNotification: NotificationParams(
      showNotification: true,
      isShowCallback: false,
      subtitle: l.callMissed,
    ),
    extra: {
      'call_id': callId,
      'caller_id': callerId,
      'caller_username': callerUsername,
      'caller_avatar': callerAvatar,
      'room_name': roomName,
      'livekit_url': livekitUrl,
      'callee_token': calleeToken,
    },
    android: AndroidParams(
      isCustomNotification: true,
      isShowLogo: false,
      backgroundColor: '#0A1628',
      actionColor: '#4CAF50',
      textAccept: l.callNotifAccept,
      textDecline: l.callNotifDecline,
    ),
    ios: const IOSParams(
      iconName: 'AppIcon',
      handleType: '',
      supportsVideo: false,
      maximumCallGroups: 1,
      maximumCallsPerCallGroup: 1,
      audioSessionMode: 'default',
      audioSessionActive: true,
      audioSessionPreferredSampleRate: 44100.0,
      audioSessionPreferredIOBufferDuration: 0.005,
      supportsDTMF: true,
      supportsHolding: true,
      supportsGrouping: false,
      supportsUngrouping: false,
    ),
  );

  await FlutterCallkitIncoming.showCallkitIncoming(params);
}

// ─── Background notification action handler (separate isolate) ───────────────

@pragma('vm:entry-point')
Future<void> _backgroundNotifResponseHandler(NotificationResponse response) async {
  debugPrint('[FLNP][BG] action=${response.actionId} | payload=${response.payload}');

  final raw = response.payload;
  if (raw == null || raw.isEmpty) return;

  Map<String, dynamic> data;
  try {
    data = jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    // Eski format: sadece callId string
    data = {'call_id': raw};
  }
  final callId = data['call_id']?.toString() ?? '';
  if (callId.isEmpty) return;

  if (response.actionId == _kActionDecline) {
    debugPrint('[FLNP][BG] Reddet aksiyonu — API çağrısı yapılıyor');
    try {
      final token = await StorageService.getToken();
      if (token != null) {
        final r = await http.post(
          Uri.parse('$kBaseUrl/calls/$callId/reject'),
          headers: {'Authorization': 'Bearer $token'},
        );
        debugPrint('[FLNP][BG] reject yanıtı: ${r.statusCode}');
      } else {
        debugPrint('[FLNP][BG] Token bulunamadı — reject yapılamadı');
      }
    } catch (e) {
      debugPrint('[FLNP][BG] reject hatası: $e');
    }
  }
  // Kabul Et aksiyonu veya normal tap: showsUserInterface:true ile app açılır.
  // Foreground handler _onNotifResponse devralır.
}

// ─── PushNotificationService ──────────────────────────────────────────────────

class PushNotificationService {
  static Future<void> showWarningNotification() async {
    final prefs = await SharedPreferences.getInstance();
    final langCode = prefs.getString('language') ?? 'tr';
    final l = lookupAppLocalizations(Locale(langCode));

    const androidDetails = AndroidNotificationDetails(
      'general_alerts',
      'Genel Bildirimler',
      channelDescription: 'Uygulama uyarı ve bilgilendirmeleri',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails(presentAlert: true, presentSound: true);
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);
    await _flnp.show(
      DateTime.now().millisecond,
      l.micPermissionRequiredTitle,
      l.micPermissionRequiredBody,
      details,
    );
  }
  static final _messaging = FirebaseMessaging.instance;
  static bool _earlyDone  = false;
  static bool _fullDone   = false;

  /// Gelen FCM + yerel bildirim verilerini broadcast eden stream.
  static final StreamController<Map<String, dynamic>> notificationStream =
      StreamController<Map<String, dynamic>>.broadcast();

  static final StreamController<void> badgeRefreshNeeded =
      StreamController<void>.broadcast();

  static Map<String, dynamic>? _pendingNavData;

  static Map<String, dynamic>? consumePendingNavigation() {
    final data = _pendingNavData;
    _pendingNavData = null;
    return data;
  }

  /// main() içinde çağrılmalı — background handler + yerel bildirim kurulumu.
  static Future<void> initEarly() async {
    if (_earlyDone) return;
    _earlyDone = true;
    debugPrint('[FCM] initEarly başladı');

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true, badge: true, sound: true,
    );

    // ── flutter_local_notifications kurulumu ─────────────────────────────────
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    final iosInit = DarwinInitializationSettings(
      notificationCategories: [
        DarwinNotificationCategory(
          _kCategoryCall,
          actions: [
            DarwinNotificationAction.plain(
              _kActionDecline, 'Reddet',
              options: {DarwinNotificationActionOption.destructive},
            ),
            DarwinNotificationAction.plain(_kActionAccept, 'Kabul Et'),
          ],
        ),
      ],
    );
    await _flnp.initialize(
      InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse:           _onNotifResponse,
      onDidReceiveBackgroundNotificationResponse: _backgroundNotifResponseHandler,
    );
    debugPrint('[FLNP] Ana izolat: initialize tamamlandı');

    // Android kanalı
    const callChannel = AndroidNotificationChannel(
      _kChannelCalls, 'Gelen Aramalar',
      description: 'Sesli arama bildirimleri',
      importance: Importance.max,
    );
    final androidPlugin = _flnp.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(callChannel);
    debugPrint('[FLNP] Ana izolat: Android kanalı oluşturuldu');
    // ─────────────────────────────────────────────────────────────────────────

    // Foreground FCM
    FirebaseMessaging.onMessage.listen((msg) {
      debugPrint('[FCM] Foreground | type=${msg.data['type']}');
      final data = Map<String, dynamic>.from(msg.data);
      data['is_foreground_receive'] = true; // Ön plan işareti eklendi
      if (data['type'] == 'incoming_call') {
        debugPrint('[FCM] Foreground incoming_call — stream\'e ekleniyor');
      }
      notificationStream.add(data);
    });

    // Background → tap
    FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      debugPrint('[FCM] Background tap | type=${msg.data['type']}');
      final data = Map<String, dynamic>.from(msg.data);
      data['is_foreground_receive'] = false; // Tıklama işareti eklendi
      notificationStream.add(data);
    });

    // Killed state → FCM tap
    final initial = await _messaging.getInitialMessage();
    if (initial != null) {
      debugPrint('[FCM] Cold-start FCM tap | type=${initial.data['type']} | data=${initial.data}');
      if (initial.data.isNotEmpty) {
        _pendingNavData = Map<String, dynamic>.from(initial.data);
        Future.microtask(() => notificationStream.add(_pendingNavData!));
      }
    } else {
      debugPrint('[FCM] Cold-start: FCM tıklaması yok');
    }

    // Killed state → yerel bildirim tap
    final launchDetails = await _flnp.getNotificationAppLaunchDetails();
    debugPrint('[FLNP] launchDetails: didLaunch=${launchDetails?.didNotificationLaunchApp} '
               '| actionId=${launchDetails?.notificationResponse?.actionId} '
               '| payload=${launchDetails?.notificationResponse?.payload}');
    if (launchDetails?.didNotificationLaunchApp == true) {
      final resp = launchDetails!.notificationResponse;
      if (resp != null) {
        debugPrint('[FLNP] Yerel bildirim tıklamasıyla açıldı — _onNotifResponse çağrılıyor');
        Future.microtask(() => _onNotifResponse(resp));
      }
    }

    // CallKit Listener
    FlutterCallkitIncoming.onEvent.listen((CallEvent? event) async {
      if (event == null) return;
      debugPrint('[CallKit] onEvent: ${event.eventName}');
      
      if (event is CallEventActionCallAccept) {
        debugPrint('[CallKit] Kabul Et tıklandı');
        final data = Map<String, dynamic>.from(event.callKitParams.extra ?? {});
        await CallService.instance.onIncomingCall({...data, 'type': 'incoming_call'});
        CallService.instance.acceptCall(); // Accept immediately in background
        notificationStream.add({...data, 'type': 'incoming_call_auto_accept'});
      } else if (event is CallEventActionCallDecline) {
        final data = Map<String, dynamic>.from(event.callKitParams.extra ?? {});
        final callId = data['call_id']?.toString() ?? '';
        if (callId.isNotEmpty) _rejectCallById(callId);
      } else if (event is CallEventActionCallEnded || event is CallEventActionCallTimeout) {
        CallKitParams? params;
        if (event is CallEventActionCallEnded) params = event.callKitParams;
        
        final data = Map<String, dynamic>.from(params?.extra ?? {});
        final callIdStr = data['call_id']?.toString() ?? '';

        if (CallService.instance.state.value.callId != null) {
          CallService.instance.endCall();
        } else if (callIdStr.isNotEmpty) {
          _endCallById(callIdStr);
          CallService.instance.reset();
        } else {
          CallService.instance.reset();
        }
      } else if (event is CallEventActionDidUpdateDevicePushTokenVoip) {
        try {
          final voipToken = await FlutterCallkitIncoming.getDevicePushTokenVoIP();
          final shortVoip = (voipToken != null && voipToken.length >= 15) ? "${voipToken.substring(0, 15)}…" : voipToken;
          _cpLog('TOKEN', 'VoIP token async update (PKPushRegistry) | ${shortVoip ?? "NULL"}');
          if (voipToken != null && voipToken.isNotEmpty) {
            final fcmToken = await FirebaseMessaging.instance.getToken();
            await AuthService.saveDeviceTokens(fcmToken: fcmToken, voipToken: voipToken);
            _cpLog('TOKEN', 'VoIP async update → backend SUCCESS');
          }
        } catch (e) {
          _cpLog('TOKEN', 'VoIP async update FAILED | $e');
        }
      }
    });

    debugPrint('[FCM] initEarly tamamlandı');
  }

  /// Foreground / app-open notification response handler.
  static void _onNotifResponse(NotificationResponse response) {
    debugPrint('[FLNP] _onNotifResponse | actionId=${response.actionId} | payload=${response.payload}');
    final raw = response.payload;
    if (raw == null || raw.isEmpty) return;

    Map<String, dynamic> data;
    try {
      data = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      data = {'call_id': raw};
    }
    final callId = data['call_id']?.toString() ?? '';
    if (callId.isEmpty) {
      debugPrint('[FLNP] Payload\'da call_id yok — işlem yok');
      return;
    }

    debugPrint('[FLNP] call_id=$callId | action=${response.actionId}');

    if (response.actionId == _kActionDecline) {
      debugPrint('[FLNP] Reddet tıklandı — API çağrısı yapılıyor');
      _rejectCallById(callId);
    } else {
      // Kabul Et aksiyonu veya normal tap → CallService state'i kur + stream'e gönder
      debugPrint('[FLNP] Kabul/tap — CallService.onIncomingCall çağrılıyor');
      // State'i direkt kur; IncomingCallOverlay addPostFrameCallback ile alır
      CallService.instance.onIncomingCall({
        ...data,
        'type': 'incoming_call',
      });
      if (response.actionId == _kActionAccept) {
        // Direkt kabul: stream üzerinden IncomingCallOverlay'e sinyal
        debugPrint('[FLNP] Kabul Et aksiyonu — accept akışı başlatılıyor');
        notificationStream.add({...data, 'type': 'incoming_call_auto_accept'});
      }
      // Normal tap: IncomingCallScreen açılsın
    }
  }

  static Future<void> _rejectCallById(String callId) async {
    try {
      final token = await StorageService.getToken();
      if (token != null) {
        final r = await http.post(
          Uri.parse('$kBaseUrl/calls/$callId/reject'),
          headers: {'Authorization': 'Bearer $token'},
        );
        debugPrint('[FLNP] reject yanıtı: ${r.statusCode}');
      }
    } catch (e) {
      debugPrint('[FLNP] reject hatası: $e');
    }
  }

  static Future<void> _endCallById(String callId) async {
    try {
      final token = await StorageService.getToken();
      if (token != null) {
        final r = await http.post(
          Uri.parse('$kBaseUrl/calls/$callId/end'),
          headers: {'Authorization': 'Bearer $token'},
        );
        debugPrint('[FLNP] end yanıtı: ${r.statusCode}');
      }
    } catch (e) {
      debugPrint('[FLNP] end hatası: $e');
    }
  }

  /// Kullanıcı giriş yaptıktan sonra çağrılmalı.
  static Future<void> initialize() async {
    debugPrint('[FCM] initialize çağrıldı | fullDone=$_fullDone');
    await initEarly();
    if (_fullDone) return;
    _fullDone = true;

    final settings = await _messaging.requestPermission(
      alert: true, badge: true, sound: true,
    );
    debugPrint('[FCM] İzin: ${settings.authorizationStatus}');

    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      _messaging.onTokenRefresh.listen((t) {
        _cpLog('TOKEN', 'FCM onTokenRefresh → re-registering backend');
        _sendTokenToBackend(t);
      });
      await _registerToken();
    }
  }

  static Future<void> refreshToken() async {
    _cpLog('TOKEN', 'refreshToken called → _registerToken');
    await _registerToken();
  }

  static Future<void> _registerToken() async {
    _cpLog('TOKEN', '_registerToken start');
    try {
      if (!kIsWeb) {
        try {
          final apns = await _messaging.getAPNSToken();
          _cpLog('TOKEN', 'APNS token | ${apns != null ? "${apns.substring(0, 12)}… (${apns.length} chars)" : "NULL"}');
        } catch (e) {
          _cpLog('TOKEN', 'APNS token FAILED | $e');
        }
      }
      final token = await _messaging.getToken();
      _cpLog('TOKEN', 'FCM token | ${token != null ? "${token.substring(0, 20)}… (${token.length} chars)" : "NULL"}');
      if (token != null) {
        await _sendTokenToBackend(token);
      } else {
        _cpLog('TOKEN', 'FCM token NULL — backend registration SKIPPED');
      }
    } catch (e) {
      _cpLog('TOKEN', '_registerToken FAILED | $e');
    }
  }

  static Future<void> _sendTokenToBackend(String token) async {
    _cpLog('TOKEN', '_sendTokenToBackend start | fcmLen=${token.length}');
    try {
      String? voipToken;
      if (Platform.isIOS) {
        try {
          voipToken = await FlutterCallkitIncoming.getDevicePushTokenVoIP();
          final shortVoip = (voipToken != null && voipToken.length >= 15) ? "${voipToken.substring(0, 15)}…" : voipToken;
          _cpLog('TOKEN', 'VoIP token (attempt 1) | ${shortVoip ?? "NULL"}');

          if (voipToken == null || voipToken.isEmpty) {
            _cpLog('TOKEN', 'VoIP token NULL — retrying after 3s (PKPushRegistry may not have fired yet)');
            await Future.delayed(const Duration(seconds: 3));
            voipToken = await FlutterCallkitIncoming.getDevicePushTokenVoIP();
            final shortRetry = (voipToken != null && voipToken.length >= 15) ? "${voipToken.substring(0, 15)}…" : voipToken;
            _cpLog('TOKEN', 'VoIP token (attempt 2) | ${shortRetry ?? "STILL NULL"}');
          }
        } catch (e) {
          _cpLog('TOKEN', 'VoIP token FAILED | $e');
        }
      }

      await AuthService.saveDeviceTokens(fcmToken: token, voipToken: voipToken);
      _cpLog('TOKEN', 'backend registration SUCCESS | voip=${voipToken != null ? "present" : "absent"}');
    } catch (e) {
      _cpLog('TOKEN', '_sendTokenToBackend FAILED | $e');
    }
  }
}
