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
  } else if (message.data['type'] == 'call_accepted') {
    // Silent data push: caller's app was suspended/killed while waiting for answer.
    // Background isolate cannot access CallService (UI services not initialized).
    // Recovery happens when caller brings the app to foreground:
    //   app resume → WsService reconnects → "connected" event → checkActiveCall()
    // This log entry helps confirm the push was delivered to the background isolate.
    debugPrint(
      '[FCM][BG][RECOVERY] call_accepted received in background | '
      'call_id=${message.data['call_id']} — recovery via checkActiveCall() on foreground',
    );
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
      final type = msg.data['type'] as String? ?? 'unknown';
      debugPrint('[FCM] Foreground | type=$type');
      final data = Map<String, dynamic>.from(msg.data);
      data['is_foreground_receive'] = true;
      if (type == 'incoming_call') {
        debugPrint('[FCM] Foreground incoming_call — stream\'e ekleniyor');
      } else if (type == 'call_accepted') {
        // call_accepted FCM: caller was in foreground but WS may have been down.
        // notificationStream → IncomingCallOverlay._onData handles 'call_accepted'
        // the same way the WS event does → CallService.onCallAccepted() → openCallScreen.
        _cpLog('PUSH', 'call_accepted FCM foreground | call_id=${data['call_id']} → notificationStream');
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
      _cpLog('PUSH', 'CallKit onEvent | event=${event.eventName} platform=${Platform.isIOS ? "iOS" : "Android"} nowUtc=${DateTime.now().toUtc().toIso8601String()}');


      if (event is CallEventActionCallIncoming) {
        // ── WhatsApp-kalitesi callee pre-connect ────────────────────────────────
        // iOS VoIP push: CallKit UI gösterildiğinde bu event ateşlenir.
        // onIncomingCall → ringing state → _fetchAndStoreCalleeToken → _joinRoom(ringing)
        // Kullanıcı Kabul'e bastığında LK bağlantısı hazır olur — sadece mic aktivasyonu gerekir.
        // Bu event handle edilmediğinde pre-connect hiç çalışmıyordu (2-4s gecikme).
        final data = Map<String, dynamic>.from(event.callKitParams.extra ?? {});
        final callId = data['call_id']?.toString() ?? 'NULL';
        final caller = data['caller_username']?.toString() ?? 'NULL';
        _cpLog('PUSH', 'CallEventActionCallIncoming | callId=$callId caller=$caller nowUtc=${DateTime.now().toUtc().toIso8601String()} → onIncomingCall (pre-connect trigger)');
        await CallService.instance.onIncomingCall({
          ...data,
          'type': 'incoming_call',
          '_source': 'CallEventActionCallIncoming',
        });
        _cpLog('PUSH', 'CallEventActionCallIncoming done | callId=$callId status=${CallService.instance.state.value.status.name}');
        // Android: FCM background handler always calls showCallkitIncoming which shows a
        // persistent notification (Accept/Decline buttons). When the app is in foreground
        // the IncomingCallBar is the correct UI — dismiss the native notification so the
        // user doesn't see both. On iOS this path is handled by the AppDelegate instant-dismiss.
        if (Platform.isAndroid) {
          final isAppForeground = WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
          if (isAppForeground) {
            try {
              final callUuid = formatToUuid(callId);
              await FlutterCallkitIncoming.endCall(callUuid);
              _cpLog('PUSH', 'CallEventActionCallIncoming → Android notification dismissed (app foreground, IncomingCallBar active) | callId=$callId');
            } catch (e) {
              _cpLog('PUSH', 'CallEventActionCallIncoming → Android dismiss ERROR | $e');
            }
          }
        }
      } else if (event is CallEventActionCallAccept) {
        final data = Map<String, dynamic>.from(event.callKitParams.extra ?? {});
        final callId = data['call_id']?.toString() ?? 'NULL';
        final roomReady = CallService.instance.state.value.calleeToken != null;
        _cpLog('PUSH', 'CallEventActionCallAccept | callId=$callId preConnectTokenReady=$roomReady currentStatus=${CallService.instance.state.value.status.name} nowUtc=${DateTime.now().toUtc().toIso8601String()}');
        // Not: CallEventActionCallIncoming zaten onIncomingCall'u çağırdı (status=ringing).
        // Burada ikinci çağrı hasActiveCall nedeniyle engellenir — sorun yok.
        await CallService.instance.onIncomingCall({
          ...data,
          'type': 'incoming_call',
          '_source': 'CallEventActionCallAccept',
        });
        CallService.instance.acceptCall();
        notificationStream.add({...data, 'type': 'incoming_call_auto_accept'});
        _cpLog('PUSH', 'CallEventActionCallAccept: acceptCall triggered | callId=$callId');
      } else if (event is CallEventActionCallDecline) {
        final data = Map<String, dynamic>.from(event.callKitParams.extra ?? {});
        final callId = data['call_id']?.toString() ?? '';
        final callIdInt = int.tryParse(callId);
        final cs = CallService.instance;
        final currentStatus = cs.state.value.status;
        _cpLog('PUSH', 'CallEventActionCallDecline | callId=$callId status=$currentStatus activeIncomingId=${cs.activeIncomingCallId} nowUtc=${DateTime.now().toUtc().toIso8601String()}');

        // Guard 1: iOS foreground VoIP push → AppDelegate sends CXEndCallAction to suppress
        // full-screen CallKit UI. Call is handled by WS/IncomingCallBar — don't reject.
        if (currentStatus == CallStatus.ringing) {
          _cpLog('PUSH', 'CallEventActionCallDecline SKIPPED | status=ringing (iOS foreground auto-dismiss)');
          return;
        }

        // Guard 2: Call already accepted — stale dismiss after accept must not re-reject.
        if (currentStatus == CallStatus.connecting ||
            currentStatus == CallStatus.connected ||
            currentStatus == CallStatus.reconnecting) {
          _cpLog('PUSH', 'CallEventActionCallDecline SKIPPED | status=$currentStatus (call already accepted — use endCall)');
          return;
        }

        // Guard 3: onIncomingCall in-flight for this callId (backendStatus HTTP pending).
        // Android foreground: WS triggers onIncomingCall, sets activeIncomingCallId, awaits HTTP.
        // FCM arrives in parallel → CallEventActionCallIncoming → dedup returns immediately →
        // Android foreground dismiss fires FlutterCallkitIncoming.endCall → this event fires
        // BEFORE onIncomingCall finishes (status still idle). Without this guard, _rejectCallById
        // fires against a call that hasn't been shown or rejected by the user.
        if (callIdInt != null && callIdInt == cs.activeIncomingCallId) {
          _cpLog('PUSH', 'CallEventActionCallDecline SKIPPED | onIncomingCall in-flight callId=$callId (Android foreground race)');
          return;
        }

        if (callId.isNotEmpty) _rejectCallById(callId);
      } else if (event is CallEventActionCallEnded || event is CallEventActionCallTimeout) {
        CallKitParams? params;
        final isTimeout = event is CallEventActionCallTimeout;
        if (event is CallEventActionCallEnded) params = event.callKitParams;

        final data = Map<String, dynamic>.from(params?.extra ?? {});
        final callIdStr = data['call_id']?.toString() ?? '';
        final currentStatus = CallService.instance.state.value.status;
        _cpLog('PUSH', '${isTimeout ? "CallEventActionCallTimeout" : "CallEventActionCallEnded"} | callId=$callIdStr activeCallId=${CallService.instance.state.value.callId} status=$currentStatus nowUtc=${DateTime.now().toUtc().toIso8601String()}');

        // Skip if ringing: this fires from the foreground CallKit auto-dismissal
        // (VoIP push arrives while app is active → we end CX call in native to prevent
        // UI takeover). The actual call is handled by WS/IncomingCallBar — don't end it.
        if (currentStatus == CallStatus.ringing) {
          _cpLog('PUSH', 'CallEventActionCallEnded SKIPPED | status=ringing (foreground CallKit suppress) | callId=$callIdStr');
          return;
        }

        // LOCK1 guard: CallKit fires ACTION_CALL_TIMEOUT ~30s after the notification was
        // shown, even if the user already accepted via IncomingCallBar (not the native CK UI).
        // If the call is already connected/reconnecting the timeout is stale — skip it.
        if (isTimeout &&
            (currentStatus == CallStatus.connected ||
                currentStatus == CallStatus.reconnecting)) {
          _cpLog('PUSH', 'CallEventActionCallTimeout SKIPPED | call already $currentStatus | callId=$callIdStr');
          return;
        }

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
      } else if (event is CallEventActionCallToggleAudioSession) {
        // Fired by iOS during didActivate/didDeactivateAudioSession. Audio session is managed
        // by call_service directly; no action needed here.
      } else {
        _cpLog('PUSH', 'CallKit onEvent UNHANDLED | event=${event.eventName}');
      }
    }, onError: (Object error) {
      // flutter_callkit_incoming throws FormatException for ACTION_CALL_TOGGLE_AUDIO_SESSION
      // when isActive is null (iOS caller flow with no active incoming call id). Without this
      // handler the exception surfaces in [PlatformDispatcher] HATA log on every audio session
      // activate/deactivate. Suppress silently — it's a plugin bug, not a call logic error.
      _cpLog('PUSH', 'CallKit onEvent stream error (suppressed) | $error');
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
    // Final defense: never send /reject if call has moved past ringing (already accepted).
    final status = CallService.instance.state.value.status;
    if (status == CallStatus.connecting ||
        status == CallStatus.connected ||
        status == CallStatus.reconnecting) {
      _cpLog('PUSH', '_rejectCallById SKIPPED | status=$status (call accepted) callId=$callId');
      return;
    }
    _cpLog('PUSH', '_rejectCallById | callId=$callId status=$status');
    try {
      final token = await StorageService.getToken();
      if (token != null) {
        final r = await http.post(
          Uri.parse('$kBaseUrl/calls/$callId/reject'),
          headers: {'Authorization': 'Bearer $token'},
        );
        _cpLog('PUSH', '_rejectCallById response | callId=$callId statusCode=${r.statusCode}');
      } else {
        _cpLog('PUSH', '_rejectCallById SKIPPED | no auth token callId=$callId');
      }
    } catch (e) {
      _cpLog('PUSH', '_rejectCallById ERROR | callId=$callId $e');
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

      // 429 Rate Limited için exponential backoff: 10s, 30s, vazgeç.
      const delays = [10, 30];
      for (int attempt = 1; attempt <= delays.length + 1; attempt++) {
        try {
          await AuthService.saveDeviceTokens(fcmToken: token, voipToken: voipToken);
          _cpLog('TOKEN', 'backend registration SUCCESS | attempt=$attempt voip=${voipToken != null ? "present" : "absent"}');
          return;
        } catch (e) {
          final isRateLimited = e.toString().contains('429') || e.toString().contains('RATE_LIMITED') || e.toString().contains('rate_limited');
          if (isRateLimited && attempt <= delays.length) {
            final waitSecs = delays[attempt - 1];
            _cpLog('TOKEN', 'backend registration 429 RATE_LIMITED | attempt=$attempt → retrying in ${waitSecs}s');
            await Future.delayed(Duration(seconds: waitSecs));
          } else {
            _cpLog('TOKEN', '_sendTokenToBackend FAILED | attempt=$attempt error=$e');
            return;
          }
        }
      }
    } catch (e) {
      _cpLog('TOKEN', '_sendTokenToBackend OUTER FAILED | $e');
    }
  }
}
