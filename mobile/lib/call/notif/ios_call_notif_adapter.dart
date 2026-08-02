import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import '../../services/auth_service.dart';
import 'call_notif_adapter.dart';

class IosCallNotifAdapter extends CallNotifAdapter {
  @override
  Future<void> registerTokens({String? fcmToken}) async {
    notifLog('TOKEN | registerTokens iOS');
    try {
      final token = fcmToken ?? await FirebaseMessaging.instance.getToken();
      notifLog('TOKEN | FCM | ${token != null ? "${token.substring(0, 20)}…" : "NULL"}');
      if (token == null) {
        notifLog('TOKEN | FCM NULL → SKIPPED');
        return;
      }

      // VoIP token — retry once if PKPushRegistry hasn't fired yet
      String? voipToken;
      try {
        voipToken = await FlutterCallkitIncoming.getDevicePushTokenVoIP();
        notifLog('TOKEN | VoIP attempt 1 | ${_short(voipToken)}');
        if (voipToken == null || voipToken.isEmpty) {
          notifLog('TOKEN | VoIP NULL → retry 3s');
          await Future.delayed(const Duration(seconds: 3));
          voipToken = await FlutterCallkitIncoming.getDevicePushTokenVoIP();
          notifLog('TOKEN | VoIP attempt 2 | ${_short(voipToken)}');
        }
      } catch (e) {
        notifLog('TOKEN | VoIP FAILED | $e');
      }

      final captured = token;
      final capturedVoip = voipToken;
      await CallNotifAdapter.sendWithRetry(
        context: 'iOS fcmLen=${captured.length} voip=${capturedVoip != null ? "present" : "absent"}',
        send: () => AuthService.saveDeviceTokens(fcmToken: captured, voipToken: capturedVoip),
      );
    } catch (e) {
      notifLog('TOKEN | registerTokens FAILED | $e');
    }
  }

  @override
  Future<void> reportCallEnded({required String? callId}) async {
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
    try {
      await FlutterCallkitIncoming.endAllCalls();
      notifLog('NOTIF | endAllCalls');
    } catch (e) {
      notifLog('NOTIF | endAllCalls ERROR | $e');
    }
  }

  String? _short(String? t) =>
      (t != null && t.length >= 15) ? '${t.substring(0, 15)}…' : t;
}
