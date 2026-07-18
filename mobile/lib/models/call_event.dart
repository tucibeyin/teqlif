/// Typed call event system — replaces raw Map<String, dynamic> passing.
///
/// All signaling sources (WS, FCM, CallKit) produce CallEvent instances.
/// CallService.processEvent() is the single entry point.
sealed class CallEvent {
  const CallEvent();

  /// Parse a raw WS/FCM payload map into a typed CallEvent.
  factory CallEvent.fromMap(Map<String, dynamic> data) {
    final type = (data['type'] as String?) ?? '';
    final callId = _int(data['call_id']);

    return switch (type) {
      'call_incoming' || 'incoming_call' => IncomingCallEvent(
          callId: callId,
          callerId: _int(data['caller_id']),
          callerUsername: (data['caller_username'] as String?) ?? '',
          callerAvatar: data['caller_avatar'] as String?,
          locale: data['locale'] as String?,
        ),
      'call_accepted' => CallAcceptedEvent(callId: callId),
      'call_rejected' => CallRejectedEvent(callId: callId),
      'call_ended' => CallEndedEvent(callId: callId),
      'call_missed' => CallMissedEvent(callId: callId),
      'connected' => const WsConnectedEvent(),
      // CallKit / push-service synthetic events
      'incoming_call_notification_tap' => IncomingCallTapEvent(data: data),
      'incoming_call_auto_accept' => IncomingCallAutoAcceptEvent(data: data),
      _ => UnknownCallEvent(type: type, raw: data),
    };
  }

  static int _int(dynamic v) {
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }
}

// ── Concrete event types ──────────────────────────────────────────────────────

class IncomingCallEvent extends CallEvent {
  final int callId;
  final int callerId;
  final String callerUsername;
  final String? callerAvatar;
  final String? locale;

  const IncomingCallEvent({
    required this.callId,
    required this.callerId,
    required this.callerUsername,
    this.callerAvatar,
    this.locale,
  });

  Map<String, dynamic> toMap() => {
        'type': 'call_incoming',
        'call_id': callId,
        'caller_id': callerId,
        'caller_username': callerUsername,
        'caller_avatar': callerAvatar,
        'locale': locale,
      };
}

class CallAcceptedEvent extends CallEvent {
  final int callId;
  const CallAcceptedEvent({required this.callId});
}

class CallRejectedEvent extends CallEvent {
  final int callId;
  const CallRejectedEvent({required this.callId});
}

class CallEndedEvent extends CallEvent {
  final int callId;
  const CallEndedEvent({required this.callId});
}

class CallMissedEvent extends CallEvent {
  final int callId;
  const CallMissedEvent({required this.callId});
}

class WsConnectedEvent extends CallEvent {
  const WsConnectedEvent();
}

class IncomingCallTapEvent extends CallEvent {
  final Map<String, dynamic> data;
  const IncomingCallTapEvent({required this.data});
}

class IncomingCallAutoAcceptEvent extends CallEvent {
  final Map<String, dynamic> data;
  const IncomingCallAutoAcceptEvent({required this.data});
}

class UnknownCallEvent extends CallEvent {
  final String type;
  final Map<String, dynamic> raw;
  const UnknownCallEvent({required this.type, required this.raw});
}
