import 'dart:async';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../config/api.dart';
import '../config/app_colors.dart';
import '../services/call_service.dart';
import '../services/push_notification_service.dart';
import '../services/ws_service.dart';
import '../screens/incoming_call_screen.dart';
import '../screens/call_screen.dart';

void _cpLog(String phase, String msg) {
  debugPrint('[CALL_PROCESS][${DateTime.now().toIso8601String()}][$phase] $msg');
}

class IncomingCallOverlay extends StatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState>? navigatorKey;
  const IncomingCallOverlay({super.key, required this.child, this.navigatorKey});

  @override
  State<IncomingCallOverlay> createState() => _IncomingCallOverlayState();
}

class _IncomingCallOverlayState extends State<IncomingCallOverlay> {
  StreamSubscription<Map<String, dynamic>>? _notifSub;
  StreamSubscription<Map<String, dynamic>>? _wsSub;
  bool _isBarDismissed = false;
  CallStatus _prevStatus = CallStatus.idle;

  @override
  void initState() {
    super.initState();
    _cpLog('UI', 'IncomingCallOverlay initState | currentStatus=${CallService.instance.state.value.status.name}');
    _notifSub = PushNotificationService.notificationStream.stream.listen(
      _onData,
    );
    _wsSub = WsService.messageStream.stream.listen(_onData);
    CallService.instance.state.addListener(_onCallState);
    CallService.instance.isCallScreenVisible.addListener(_onCallState);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (CallService.instance.state.value.status == CallStatus.ringing) {
        _cpLog('UI', 'IncomingCallOverlay cold-start: status=ringing → IncomingCallBar visible | caller=${CallService.instance.state.value.otherUsername}');
      }
    });
  }

  void _onData(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    if (type == null) return;
    if (!type.startsWith('call') && !type.startsWith('incoming')) return;
    _cpLog('UI', 'overlay._onData received | type=$type currentStatus=${CallService.instance.state.value.status}');
    switch (type) {
      case 'incoming_call':
      case 'call_incoming':
        if (CallService.instance.state.value.status != CallStatus.ringing) {
          _cpLog('UI', 'IncomingCallBar will show | caller=${data['caller_username']}');
          _isBarDismissed = false;
          CallService.instance.onIncomingCall(data);
        } else {
          _cpLog('UI', 'incoming_call SKIPPED | already ringing');
        }
        break;
      case 'incoming_call_notification_tap':
        _cpLog('UI', 'notification_tap → openIncomingScreen | status=${CallService.instance.state.value.status}');
        if (CallService.instance.state.value.status == CallStatus.ringing) {
          _openIncomingScreen();
        }
        break;
      case 'incoming_call_auto_accept':
        _cpLog('UI', 'auto_accept → openCallScreen (CallKit accepted)');
        _openCallScreen();
        break;
      case 'call_accepted':
        _cpLog('UI', 'call_accepted WS → onCallAccepted + openCallScreen | acceptedAt=${data['accepted_at']} nowUtc=${DateTime.now().toUtc().toIso8601String()}');
        _cpLog('TIMER', 'overlay: call_accepted WS received | acceptedAt=${data['accepted_at']} nowUtc=${DateTime.now().toUtc().toIso8601String()}');
        CallService.instance.onCallAccepted(data);
        _openCallScreen();
        break;
      case 'call_rejected':
        _cpLog('UI', 'call_rejected WS → onCallRejected');
        CallService.instance.onCallRejected();
        break;
      case 'call_ended':
        _cpLog('UI', 'call_ended WS → onCallEnded');
        CallService.instance.onCallEnded();
        break;
      case 'call_missed':
        final missedCallId = data['call_id'] is int
            ? data['call_id'] as int
            : int.tryParse(data['call_id']?.toString() ?? '');
        _cpLog('UI', 'call_missed WS → onCallMissed | callId=$missedCallId');
        CallService.instance.onCallMissed(callId: missedCallId);
        break;
      default:
        break;
    }
  }

  void _onCallState() {
    final status = CallService.instance.state.value.status;
    final caller = CallService.instance.state.value.otherUsername ?? '?';
    final callId = CallService.instance.state.value.callId;
    _cpLog('UI', 'overlay._onCallState | ${_prevStatus.name} → ${status.name} isCallScreenVisible=${CallService.instance.isCallScreenVisible.value} callId=$callId');

    // Bar görünürlük geçişlerini logla
    if (_prevStatus != CallStatus.ringing && status == CallStatus.ringing) {
      _cpLog('UI', 'BAR SHOW: IncomingCallBar appeared | caller=$caller callId=$callId');
    } else if (_prevStatus == CallStatus.ringing && status != CallStatus.ringing) {
      _cpLog('UI', 'BAR HIDE: IncomingCallBar disappeared | reason=${status.name} callId=$callId');
    }
    _prevStatus = status;

    if (status != CallStatus.ringing) {
      _isBarDismissed = false;
    }
    // Giden arama: startCall() → calling durumuna geçince CallScreen'i overlay açar.
    // Bu sayede public_profile_screen / messages_screen'in doğrudan push'u kaldırılabildi.
    if (status == CallStatus.calling || status == CallStatus.connecting || status == CallStatus.connected) {
      if (!CallService.instance.isCallScreenVisible.value) {
        _cpLog('UI', 'overlay._onCallState: status=${status.name} → _openCallScreen()');
        _openCallScreen();
      }
    }
    setState(() {});
  }

  void _openIncomingScreen() {
    if (!mounted) return;
    _cpLog('UI', 'IncomingCallBar → user TAP bar body → IncomingCallScreen | callId=${CallService.instance.state.value.callId} caller=${CallService.instance.state.value.otherUsername}');
    final nav = widget.navigatorKey?.currentState ?? Navigator.of(context, rootNavigator: true);
    nav.push(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/incoming_call_screen'),
        fullscreenDialog: true,
        builder: (_) => IncomingCallScreen(
          callData: {
            'caller_username':
                CallService.instance.state.value.otherUsername ?? '',
            'caller_avatar': CallService.instance.state.value.otherAvatar ?? '',
            'call_id': CallService.instance.state.value.callId,
          },
        ),
      ),
    );
  }

  void _openCallScreen() {
    if (!mounted) return;
    if (CallService.instance.isCallScreenVisible.value) {
      _cpLog('UI', 'overlay._openCallScreen SKIPPED | already visible');
      return;
    }
    if (CallService.instance.preventCallScreenAutoOpen.value) {
      _cpLog('UI', 'overlay._openCallScreen SKIPPED | preventAutoOpen=true');
      return;
    }
    final nowUtc = DateTime.now().toUtc();
    final acceptedAt = CallService.instance.state.value.acceptedAt;
    final lagMs = acceptedAt != null ? nowUtc.difference(acceptedAt.toUtc()).inMilliseconds : -1;
    _cpLog('TIMER', 'overlay._openCallScreen → /call_screen | acceptedAt=${acceptedAt?.toIso8601String() ?? "NULL"} nowUtc=${nowUtc.toIso8601String()} openLagMs=$lagMs status=${CallService.instance.state.value.status.name}');
    _cpLog('UI', 'overlay._openCallScreen → pushing /call_screen');
    final nav = widget.navigatorKey?.currentState ?? Navigator.of(context, rootNavigator: true);
    nav.push(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/call_screen'),
        builder: (_) => const CallScreen(),
        fullscreenDialog: true,
      ),
    );
  }

  Future<void> _openCallScreenAndAccept() async {
    if (!mounted) return;
    final nowUtc = DateTime.now().toUtc();
    final callId = CallService.instance.state.value.callId;
    final caller = CallService.instance.state.value.otherUsername;
    final preConnectReady = CallService.instance.state.value.calleeToken != null;
    _cpLog('UI', 'IncomingCallBar → user ACCEPT tap | callId=$callId caller=$caller nowUtc=${nowUtc.toIso8601String()}');
    _cpLog('TIMER', 'IncomingCallBar: ACCEPT tapped | callId=$callId caller=$caller nowUtc=${nowUtc.toIso8601String()} preConnectTokenReady=$preConnectReady');
    CallService.instance.acceptCall();
    _openCallScreen();
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    _wsSub?.cancel();
    CallService.instance.state.removeListener(_onCallState);
    CallService.instance.isCallScreenVisible.removeListener(_onCallState);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,

        // Ringing UI
        if (CallService.instance.state.value.status == CallStatus.ringing)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                child: _isBarDismissed
                    ? _MinimizedCallBar(
                        callerUsername: CallService.instance.state.value.otherUsername ?? '',
                        callId: CallService.instance.state.value.callId,
                        onRestore: () {
                          _cpLog('UI', 'MinimizedCallBar → user TAP → restored to IncomingCallBar | callId=${CallService.instance.state.value.callId}');
                          setState(() => _isBarDismissed = false);
                        },
                      )
                    : _IncomingCallBar(
                        username: CallService.instance.state.value.otherUsername ?? '',
                        avatarUrl: CallService.instance.state.value.otherAvatar,
                        onTap: _openIncomingScreen,
                        onAccept: _openCallScreenAndAccept,
                        onReject: () {
                          _cpLog('UI', 'IncomingCallBar → user REJECT tap | callId=${CallService.instance.state.value.callId} caller=${CallService.instance.state.value.otherUsername}');
                          setState(() => _isBarDismissed = true);
                          CallService.instance.rejectCall();
                        },
                        onDismiss: () {
                          _cpLog('UI', 'IncomingCallBar → user SWIPE-UP dismiss → MinimizedCallBar | callId=${CallService.instance.state.value.callId}');
                          setState(() => _isBarDismissed = true);
                        },
                      ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MinimizedCallBar extends StatelessWidget {
  final VoidCallback onRestore;
  final String callerUsername;
  final int? callId;

  const _MinimizedCallBar({
    required this.onRestore,
    required this.callerUsername,
    this.callId,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    _cpLog('UI', 'MinimizedCallBar BUILD | caller=$callerUsername callId=$callId');

    return Dismissible(
      key: const Key('minimized_call_bar'),
      direction: DismissDirection.down,
      onDismissed: (_) {
        _cpLog('UI', 'MinimizedCallBar → user SWIPE-DOWN → restored to IncomingCallBar | callId=$callId caller=$callerUsername');
        onRestore();
      },
      child: Material(
        type: MaterialType.transparency,
        child: Center(
          child: GestureDetector(
            onTap: () {
              onRestore();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E),
                borderRadius: BorderRadius.circular(100),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                const Icon(Icons.call, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(
                  l.callIncomingTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.keyboard_arrow_down,
                  color: Colors.white,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}

class _IncomingCallBar extends StatelessWidget {
  final String username;
  final String? avatarUrl;
  final VoidCallback onTap;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onDismiss;

  const _IncomingCallBar({
    required this.username,
    this.avatarUrl,
    required this.onTap,
    required this.onAccept,
    required this.onReject,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final title = l.callIncomingBody(username);
    _cpLog('UI', 'IncomingCallBar BUILD | caller=$username avatarUrl=${avatarUrl != null ? "EXISTS" : "NULL"}');

    return Dismissible(
      key: const Key('incoming_call_bar'),
      direction: DismissDirection.up,
      onDismissed: (_) {
        _cpLog('UI', 'IncomingCallBar → user SWIPE-UP → dismissed (onDismiss via Dismissible) | caller=$username');
        onDismiss();
      },
      child: Material(
        type: MaterialType.transparency,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface(context),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
              border: Border.all(color: AppColors.border(context)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top part: Avatar and Info
                Row(
                  children: [
                    // Avatar
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: AppColors.surfaceVariant(context),
                      backgroundImage:
                          avatarUrl != null && avatarUrl!.isNotEmpty
                          ? CachedNetworkImageProvider(imgUrl(avatarUrl))
                          : null,
                      child: avatarUrl == null || avatarUrl!.isEmpty
                          ? Text(
                              username.isNotEmpty
                                  ? username[0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                color: AppColors.textPrimary(context),
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),

                    // Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              color: AppColors.textPrimary(context),
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            l.callVoiceCall,
                            style: TextStyle(
                              color: AppColors.textSecondary(context),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Bottom part: Actions
                Row(
                  children: [
                    Expanded(
                      child: _BarButton(
                        icon: Icons.call_end,
                        color: const Color(0xFFEF4444),
                        label: l.callDecline,
                        onTap: onReject,
                        logLabel: 'REJECT',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _BarButton(
                        icon: Icons.call,
                        color: const Color(0xFF22C55E),
                        label: l.callAccept,
                        onTap: onAccept,
                        logLabel: 'ACCEPT',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  final String logLabel;

  const _BarButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
    required this.logLabel,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        _cpLog('UI', '_BarButton TAP | action=$logLabel label=$label');
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
