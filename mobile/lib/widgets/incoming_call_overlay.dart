import 'dart:async';
import 'package:flutter/material.dart';
import '../services/call_service.dart';
import '../services/push_notification_service.dart';
import '../screens/incoming_call_screen.dart';
import '../screens/call_screen.dart';

/// Mount this widget once (in MainScreen) to listen for incoming call events
/// from both the WS channel and FCM foreground messages.
class IncomingCallOverlay extends StatefulWidget {
  final Widget child;
  const IncomingCallOverlay({super.key, required this.child});

  @override
  State<IncomingCallOverlay> createState() => _IncomingCallOverlayState();
}

class _IncomingCallOverlayState extends State<IncomingCallOverlay> {
  StreamSubscription<Map<String, dynamic>>? _notifSub;

  @override
  void initState() {
    super.initState();
    _notifSub = PushNotificationService.notificationStream.stream.listen(_onData);

    // Also react to CallService state changes triggered by WS inside ws_service
    CallService.instance.state.addListener(_onCallState);
  }

  void _onData(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    if (type == 'incoming_call' || type == 'call_incoming') {
      CallService.instance.onIncomingCall(data);
      // _onCallState listener will open the screen when status becomes ringing
    } else if (type == 'incoming_call_notification_tap') {
      // User tapped local notification — show screen if still ringing
      if (CallService.instance.state.value.status == CallStatus.ringing) {
        _openIncomingScreen();
      }
    } else if (type == 'call_accepted') {
      CallService.instance.onCallAccepted(data);
      _openCallScreen();
    } else if (type == 'call_rejected') {
      CallService.instance.onCallRejected();
    } else if (type == 'call_ended') {
      CallService.instance.onCallEnded();
    } else if (type == 'call_missed') {
      CallService.instance.onCallMissed();
    }
  }

  void _onCallState() {
    final status = CallService.instance.state.value.status;
    if (status == CallStatus.ringing) {
      _openIncomingScreen();
    } else if (status == CallStatus.connecting &&
        _isCallerSide()) {
      _openCallScreen();
    }
  }

  bool _isCallerSide() {
    // If we started the call (status was calling before connecting), we are caller.
    // We track this by whether the CallScreen is already open — simple heuristic:
    // the call_screen opens itself via onCallAccepted, so nothing extra needed here.
    return false;
  }

  void _openIncomingScreen() {
    final data = {
      'caller_username': CallService.instance.state.value.otherUsername ?? '',
      'caller_avatar': CallService.instance.state.value.otherAvatar ?? '',
      'call_id': CallService.instance.state.value.callId,
    };
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => IncomingCallScreen(callData: data),
      ),
    );
  }

  void _openCallScreen() {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => const CallScreen()),
    );
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    CallService.instance.state.removeListener(_onCallState);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
