import 'package:flutter/foundation.dart';

void _notifLog(String msg) {
  debugPrint('[CALL_NOTIF][${DateTime.now().toIso8601String()}] $msg');
}

/// Notification and token management adapter — platform-specific.
/// Responsibilities: VoIP/FCM token registration, CallKit call dismissal.
/// Receiving push events (FCM listeners, CallKit onEvent) stays in
/// PushNotificationService which routes events to CallService.
///
/// See VoIP.md §12 for token policy; §16.2.5 for call ended reporting.
abstract class CallNotifAdapter {
  /// Send device tokens to backend.
  /// iOS: fetches both VoIP token and FCM token.
  /// Android: FCM token only (no VoIP token).
  /// Pass [fcmToken] when the token is already known (e.g. onTokenRefresh).
  Future<void> registerTokens({String? fcmToken});

  /// Dismiss the incoming call UI or CallKit notification for [callId].
  /// [callId] null → no specific call to dismiss (endAllCalls handles cleanup).
  Future<void> reportCallEnded({required String? callId});

  /// Dismiss all active CallKit / system calls (used in reset()).
  Future<void> endAllCalls();

  /// Format integer-based call ID to UUID required by CallKit.
  /// Both call_service.dart and push_notification_service.dart use this.
  static String formatCallId(String id) {
    final padded = id.padLeft(32, '0');
    return '${padded.substring(0, 8)}-${padded.substring(8, 12)}-'
        '${padded.substring(12, 16)}-${padded.substring(16, 20)}-'
        '${padded.substring(20, 32)}';
  }

  /// Shared retry helper for backend token registration.
  static Future<void> sendWithRetry({
    required Future<void> Function() send,
    required String context,
  }) async {
    const delays = [10, 30];
    for (int attempt = 1; attempt <= delays.length + 1; attempt++) {
      try {
        await send();
        _notifLog('TOKEN | backend SUCCESS | $context attempt=$attempt');
        return;
      } catch (e) {
        final rateLimited = e.toString().contains('429') ||
            e.toString().contains('RATE_LIMITED') ||
            e.toString().contains('rate_limited');
        if (rateLimited && attempt <= delays.length) {
          final wait = delays[attempt - 1];
          _notifLog('TOKEN | 429 RATE_LIMITED | $context attempt=$attempt → retry ${wait}s');
          await Future.delayed(Duration(seconds: wait));
        } else {
          _notifLog('TOKEN | backend FAILED | $context attempt=$attempt $e');
          return;
        }
      }
    }
  }
}

/// Visible to subclasses for their own log calls.
void notifLog(String msg) => _notifLog(msg);
