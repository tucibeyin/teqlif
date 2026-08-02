import 'package:flutter/foundation.dart';
import '../state/call_status.dart';
import '../state/call_role.dart';
import '../state/end_reason.dart';

void _log(String msg) {
  debugPrint('[CALL_ROUTER][${DateTime.now().toIso8601String()}] $msg');
}

/// In-app screen decision given call state + context.
/// OS-level UI (CallKit native screen, FCM notification) is outside scope —
/// handled by CallHardwareAdapter/CallNotifAdapter. Platform differences don't
/// affect in-app routing; TargetPlatform is intentionally excluded.
///
/// See VoIP.md §7.2 for the authoritative routing table.
enum CallScreenDecision {
  callScreen,     // Full-screen call UI (dialing→waiting→connecting→active→reconnecting)
  incomingScreen, // Full-screen incoming (callee, foreground, no SwipeLive)
  incomingBar,    // Compact incoming bar (callee, SwipeLive active)
  minimizedBar,   // Minimized active-call pill (SwipeLive PiP mode)
  none,           // idle or ended — nothing to open/navigate to
}

class CallScreenRouter {
  const CallScreenRouter._();

  /// Returns the in-app screen decision for the given call context.
  /// Logs the resolution with [CALL_ROUTER] tag.
  static CallScreenDecision resolveScreen({
    required CallStatus status,
    required EndReason? endReason,
    required CallRole? role,
    required bool swipeLiveActive,
    required bool isBackground,
    required bool isCallScreenVisible,
  }) {
    final d = _resolve(
      status,
      endReason,
      role,
      swipeLiveActive,
      isBackground,
      isCallScreenVisible,
    );
    _log(
      'resolveScreen | status=${status.name} role=${role?.name ?? "?"}'
      ' swipeLive=$swipeLiveActive bg=$isBackground screenVisible=$isCallScreenVisible'
      ' → ${d.name}',
    );
    return d;
  }

  static CallScreenDecision _resolve(
    CallStatus status,
    EndReason? endReason,
    CallRole? role,
    bool swipeLiveActive,
    bool isBackground,
    bool isCallScreenVisible,
  ) {
    switch (status) {
      case CallStatus.idle:
        return CallScreenDecision.none;

      case CallStatus.dialing:
      case CallStatus.waiting:
        // Caller-only states — always full-screen
        return CallScreenDecision.callScreen;

      case CallStatus.ringing:
        // Background ringing: OS-level UI (CallKit / FCM) is authoritative, router defers
        if (isBackground) return CallScreenDecision.none;
        if (swipeLiveActive) return CallScreenDecision.incomingBar;
        return CallScreenDecision.incomingScreen;

      case CallStatus.connecting:
      case CallStatus.reconnecting:
        return CallScreenDecision.callScreen;

      case CallStatus.active:
        // SwipeLive PiP: minimized indicator, not full-screen
        return swipeLiveActive
            ? CallScreenDecision.minimizedBar
            : CallScreenDecision.callScreen;

      case CallStatus.ended:
        // Screen already open: stay during 2s cleanup window (VoIP.md §16.3)
        if (isCallScreenVisible) return CallScreenDecision.callScreen;
        // No screen: ended+permissionDenied handled by GlobalCallOverlay (§7.3 Kural 5)
        // ended+other: caller never entered calling state — nothing to show
        return CallScreenDecision.none;
    }
  }
}
