import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import '../../services/auth_service.dart';
import 'call_notif_adapter.dart';

class AndroidCallNotifAdapter extends CallNotifAdapter {
  @override
  Future<void> registerTokens({String? fcmToken}) async {
    notifLog('TOKEN | registerTokens Android');
    try {
      final token = fcmToken ?? await FirebaseMessaging.instance.getToken();
      notifLog('TOKEN | FCM | ${token != null ? "${token.substring(0, 20)}…" : "NULL"}');
      if (token == null) {
        notifLog('TOKEN | FCM NULL → SKIPPED');
        return;
      }
      final captured = token;
      await CallNotifAdapter.sendWithRetry(
        context: 'Android fcmLen=${captured.length}',
        // Android: voipToken always null — no VoIP push channel on Android
        send: () => AuthService.saveDeviceTokens(fcmToken: captured, voipToken: null),
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

  @override
  Future<void> reportCallStarted({
    required int callId,
    required String calleeName,
    String? calleeAvatar,
  }) async {
    // Android has no outgoing CallKit equivalent — no-op.
  }
}
