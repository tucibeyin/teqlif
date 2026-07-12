import 'dart:async';
import 'package:flutter/material.dart';
import '../services/call_service.dart';
import '../services/push_notification_service.dart';
import '../services/ws_service.dart';
import '../screens/incoming_call_screen.dart';
import '../screens/call_screen.dart';

/// Mount this widget once (in MainScreen) to listen for incoming call events
/// from both the WS channel and FCM foreground / local notification taps.
class IncomingCallOverlay extends StatefulWidget {
  final Widget child;
  const IncomingCallOverlay({super.key, required this.child});

  @override
  State<IncomingCallOverlay> createState() => _IncomingCallOverlayState();
}

class _IncomingCallOverlayState extends State<IncomingCallOverlay> {
  StreamSubscription<Map<String, dynamic>>? _notifSub;
  StreamSubscription<Map<String, dynamic>>? _wsSub;

  @override
  void initState() {
    super.initState();
    _notifSub = PushNotificationService.notificationStream.stream.listen(_onData);
    _wsSub    = WsService.messageStream.stream.listen(_onData);
    CallService.instance.state.addListener(_onCallState);
    debugPrint('[Overlay] initState — mevcut status=${CallService.instance.state.value.status}');

    // Cold-start: CallService zaten ringing olabilir (push_notification_service veya
    // main_screen._handleNotifNavigation tarafından kuruldu)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final status = CallService.instance.state.value.status;
      debugPrint('[Overlay] postFrameCallback — status=$status');
      if (status == CallStatus.ringing) {
        debugPrint('[Overlay] Zaten ringing — IncomingCallScreen açılıyor');
        _openIncomingScreen();
      }
    });
  }

  void _onData(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    debugPrint('[Overlay] _onData type=$type');

    switch (type) {
      case 'incoming_call':
      case 'call_incoming':
        // FCM + WS'ten çift gelebilir; zaten ringing ise yok say
        if (CallService.instance.state.value.status != CallStatus.ringing) {
          CallService.instance.onIncomingCall(data);
        }

      case 'incoming_call_notification_tap':
        // Yerel bildirime tıklandı ama AcceptAction değil
        // CallService zaten _onNotifResponse'da kuruldu; sadece ekranı aç
        debugPrint('[Overlay] notification_tap — status=${CallService.instance.state.value.status}');
        if (CallService.instance.state.value.status == CallStatus.ringing) {
          _openIncomingScreen();
        }

      case 'incoming_call_auto_accept':
        // Bildirimden "Kabul Et" butonuna basıldı — direkt CallScreen'e geç
        debugPrint('[Overlay] auto_accept — CallScreen açılıyor');
        _openCallScreenAndAccept();

      case 'call_accepted':
        // Karşı taraf kabul etti (caller side)
        CallService.instance.onCallAccepted(data);
        _openCallScreen();

      case 'call_rejected':
        CallService.instance.onCallRejected();

      case 'call_ended':
        CallService.instance.onCallEnded();

      case 'call_missed':
        CallService.instance.onCallMissed();

      default:
        break;
    }
  }

  void _onCallState() {
    final status = CallService.instance.state.value.status;
    debugPrint('[Overlay] _onCallState — status=$status');
    if (status == CallStatus.ringing) {
      _openIncomingScreen();
    }
  }

  void _openIncomingScreen() {
    if (!mounted) return;
    debugPrint('[Overlay] _openIncomingScreen');
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/incoming_call_screen'),
        fullscreenDialog: true,
        builder: (_) => IncomingCallScreen(callData: {
          'caller_username': CallService.instance.state.value.otherUsername ?? '',
          'caller_avatar':   CallService.instance.state.value.otherAvatar   ?? '',
          'call_id':         CallService.instance.state.value.callId,
        }),
      ),
    );
  }

  void _openCallScreen() {
    if (!mounted) return;
    debugPrint('[Overlay] _openCallScreen');
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/call_screen'),
        builder: (_) => const CallScreen(),
        fullscreenDialog: true,
      ),
    );
  }

  Future<void> _openCallScreenAndAccept() async {
    if (!mounted) return;
    debugPrint('[Overlay] _openCallScreenAndAccept — önce acceptCall');
    await CallService.instance.acceptCall();
    if (mounted) _openCallScreen();
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    _wsSub?.cancel();
    CallService.instance.state.removeListener(_onCallState);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
