/// Typed call signaling system — replaces raw `Map<String, dynamic>` passing.
///
/// All signaling sources (WS, FCM, CallKit) produce [CallSignal] instances.
/// CallService.processEvent() is the single entry point.
sealed class CallSignal {
  const CallSignal();

  /// Parse a raw WS/FCM payload map into a typed [CallSignal].
  factory CallSignal.fromMap(Map<String, dynamic> data) {
    final type = (data['type'] as String?) ?? '';
    final callId = _int(data['call_id']);

    return switch (type) {
      'call_incoming' || 'incoming_call' => IncomingCallSignal(
          callId: callId,
          callerId: _int(data['caller_id']),
          callerUsername: (data['caller_username'] as String?) ?? '',
          callerAvatar: data['caller_avatar'] as String?,
          locale: data['locale'] as String?,
        ),
      'call_accepted' => CallAcceptedSignal(callId: callId),
      'call_rejected' => CallRejectedSignal(callId: callId),
      'call_ended'   => CallEndedSignal(callId: callId),
      'call_missed'  => CallMissedSignal(callId: callId),
      'connected'    => const WsConnectedSignal(),
      // CallKit / push-service synthetic events
      'incoming_call_notification_tap'  => IncomingCallTapSignal(data: data),
      'incoming_call_auto_accept'       => IncomingCallAutoAcceptSignal(data: data),
      _                                 => UnknownCallSignal(type: type, raw: data),
    };
  }

  static int _int(dynamic v) {
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }
}

// ── Concrete signal types ─────────────────────────────────────────────────────

class IncomingCallSignal extends CallSignal {
  final int callId;
  final int callerId;
  final String callerUsername;
  final String? callerAvatar;
  final String? locale;

  const IncomingCallSignal({
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

class CallAcceptedSignal extends CallSignal {
  final int callId;
  const CallAcceptedSignal({required this.callId});
}

class CallRejectedSignal extends CallSignal {
  final int callId;
  const CallRejectedSignal({required this.callId});
}

class CallEndedSignal extends CallSignal {
  final int callId;
  const CallEndedSignal({required this.callId});
}

class CallMissedSignal extends CallSignal {
  final int callId;
  const CallMissedSignal({required this.callId});
}

class WsConnectedSignal extends CallSignal {
  const WsConnectedSignal();
}

class IncomingCallTapSignal extends CallSignal {
  final Map<String, dynamic> data;
  const IncomingCallTapSignal({required this.data});
}

class IncomingCallAutoAcceptSignal extends CallSignal {
  final Map<String, dynamic> data;
  const IncomingCallAutoAcceptSignal({required this.data});
}

class UnknownCallSignal extends CallSignal {
  final String type;
  final Map<String, dynamic> raw;
  const UnknownCallSignal({required this.type, required this.raw});
}
