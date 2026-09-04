import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import '../../services/auth_service.dart';
import '../../utils/china_market_detector.dart';
import 'call_notif_adapter.dart';

class IosCallNotifAdapter extends CallNotifAdapter {
  @override
  Future<void> registerTokens({String? fcmToken}) async {
    notifLog('TOKEN | registerTokens iOS');
    final isChina = await ChinaMarketDetector.isChina();
    try {
      final token = fcmToken ?? await FirebaseMessaging.instance.getToken();
      notifLog('TOKEN | FCM | ${token != null ? "${token.substring(0, 20)}…" : "NULL"}');
      if (token == null) {
        notifLog('TOKEN | FCM NULL → SKIPPED');
        return;
      }

      // Çin pazarında VoIP token kaydetme — CallKit Apple guideline 5 gereği devre dışı
      // Single attempt only — no blocking retry.
      // Native AppDelegate registers VoIP token independently via PKPushRegistry/URLSession,
      // so a null here is recovered automatically when PushKit fires later.
      String? voipToken;
      if (!isChina) {
        try {
          voipToken = await FlutterCallkitIncoming.getDevicePushTokenVoIP();
          notifLog('TOKEN | VoIP | ${_short(voipToken)}');
        } catch (e) {
          notifLog('TOKEN | VoIP FAILED | $e');
        }
      } else {
        notifLog('TOKEN | VoIP SKIPPED (China market — CallKit disabled)');
      }

      final captured = token;
      final capturedVoip = voipToken;
      final sandbox = Platform.isIOS ? await _detectApnsSandbox() : null;
      await CallNotifAdapter.sendWithRetry(
        context: 'iOS fcmLen=${captured.length} voip=${capturedVoip != null ? "present" : "absent"} china=$isChina sandbox=$sandbox',
        send: () => AuthService.saveDeviceTokens(
          fcmToken: captured,
          voipToken: capturedVoip,
          apnsSandbox: sandbox,
        ),
      );
    } catch (e) {
      notifLog('TOKEN | registerTokens FAILED | $e');
    }
  }

  @override
  Future<void> reportCallEnded({required String? callId}) async {
    if (await ChinaMarketDetector.isChina()) return;
    if (callId != null) {
      try {
        await FlutterCallkitIncoming.endCall(CallNotifAdapter.formatCallId(callId));
        notifLog('NOTIF | reportCallEnded | callId=$callId');
      } catch (e) {
        notifLog('NOTIF | reportCallEnded ERROR | callId=$callId $e');
      }
    }
  }

  @override
  Future<void> endAllCalls() async {
    if (await ChinaMarketDetector.isChina()) return;
    try {
      await FlutterCallkitIncoming.endAllCalls();
      notifLog('NOTIF | endAllCalls');
    } catch (e) {
      notifLog('NOTIF | endAllCalls ERROR | $e');
    }
  }

  @override
  Future<void> reportCallStarted({
    required int callId,
    required String calleeName,
    String? calleeAvatar,
  }) async {
    if (await ChinaMarketDetector.isChina()) return;
    try {
      final uuid = CallNotifAdapter.formatCallId(callId.toString());
      final params = CallKitParams(
        id: uuid,
        nameCaller: calleeName,
        appName: 'teqlif',
        avatar: calleeAvatar ?? 'https://i.pravatar.cc/100',
        handle: 'teqlif Voice Call',
        type: 0,
        duration: 45000,
        extra: {'call_id': callId},
        ios: IOSParams(
          iconName: 'AppIcon',
          handleType: 'generic',
          supportsVideo: false,
          maximumCallGroups: 1,
          maximumCallsPerCallGroup: 1,
          audioSessionMode: 'voiceChat',
          audioSessionActive: true,
          audioSessionPreferredSampleRate: 44100.0,
          audioSessionPreferredIOBufferDuration: 0.005,
          supportsDTMF: true,
          supportsHolding: true,
          supportsGrouping: false,
          supportsUngrouping: false,
          ringtonePath: 'system_ringtone_default',
        ),
      );
      await FlutterCallkitIncoming.startCall(params);
      notifLog('NOTIF | reportCallStarted | callId=$callId uuid=$uuid');
    } catch (e) {
      notifLog('NOTIF | reportCallStarted ERROR | callId=$callId $e');
    }
  }

  // AppDelegate'teki apnsSandbox() sonucunu okur — aps-environment entitlement'ı.
  // Development cert → true (sandbox), Distribution cert → false (production).
  static Future<bool?> _detectApnsSandbox() async {
    try {
      const channel = MethodChannel('com.teqlif/region');
      return await channel.invokeMethod<bool>('apnsSandbox');
    } catch (_) {
      return null;
    }
  }

  String? _short(String? t) =>
      (t != null && t.length >= 15) ? '${t.substring(0, 15)}…' : t;
}
