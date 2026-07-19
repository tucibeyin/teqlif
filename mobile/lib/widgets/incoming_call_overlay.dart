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

void _uiLog(String component, String event, String detail) {
  debugPrint('[UI_CALL][$component][${DateTime.now().toIso8601String()}] $event | $detail');
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
      case 'connected':
        // WS (re)connected — check if we're in a call we don't know about.
        // Covers: crash-restart, network handoff, WS session kick by real device.
        // Guard: only run when idle so we don't clobber an already-active call state.
        final recoveryStatus = CallService.instance.state.value.status;
        _cpLog('UI', 'WS connected event | currentStatus=${recoveryStatus.name} → checkActiveCall if idle');
        if (recoveryStatus == CallStatus.idle) {
          CallService.instance.checkActiveCall();
        }
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

      // ── Grup Arama ────────────────────────────────────────────────────────
      case 'call_group_invite':
        _cpLog('UI', 'call_group_invite WS → onGroupInviteReceived | callId=${data['call_id']}');
        CallService.instance.onGroupInviteReceived(data);
        // setState to show incoming group invite UI
        if (mounted) setState(() {});
        break;
      case 'call_participant_joined':
        _cpLog('UI', 'call_participant_joined | userId=${data['user_id']} username=${data['username']}');
        CallService.instance.onParticipantJoined(data);
        if (mounted) setState(() {});
        break;
      case 'call_participant_left':
        _cpLog('UI', 'call_participant_left | userId=${data['user_id']}');
        CallService.instance.onParticipantLeft(data);
        if (mounted) setState(() {});
        break;
      case 'call_participant_removed':
        _cpLog('UI', 'call_participant_removed | userId=${data['user_id']} selfRemoved=${data['self_removed']}');
        CallService.instance.onParticipantRemoved(data);
        if (mounted) setState(() {});
        break;
      case 'call_participant_rejected':
        _cpLog('UI', 'call_participant_rejected | userId=${data['user_id']}');
        CallService.instance.onParticipantRejected(data);
        break;
      case 'call_participant_timeout':
        _cpLog('UI', 'call_participant_timeout | userId=${data['user_id']}');
        CallService.instance.onParticipantTimeout(data);
        break;
      case 'call_participant_invited':
        _cpLog('UI', 'call_participant_invited | inviteeId=${data['invitee_id']}');
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
      _uiLog('INCOMING_BAR', 'SHOW', 'callId=$callId caller=$caller');
    } else if (_prevStatus == CallStatus.ringing && status != CallStatus.ringing) {
      _cpLog('UI', 'BAR HIDE: IncomingCallBar disappeared | reason=${status.name} callId=$callId');
      _uiLog('INCOMING_BAR', 'HIDE', 'callId=$callId reason=${status.name}');
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
    final acceptedAt = CallService.instance.acceptedAt;
    final lagStr = acceptedAt != null ? '${nowUtc.difference(acceptedAt.toUtc()).inMilliseconds}ms' : 'N/A';
    _cpLog('TIMER', 'overlay._openCallScreen → /call_screen | acceptedAt=${acceptedAt?.toIso8601String() ?? "NULL"} nowUtc=${nowUtc.toIso8601String()} openLagMs=$lagStr status=${CallService.instance.state.value.status.name}');
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
    _uiLog('INCOMING_BAR', 'ACCEPT_TAP', 'callId=$callId caller=$caller');
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

        // Active call floating indicator — shown when call is connected but CallScreen is not visible
        if (CallService.instance.state.value.status == CallStatus.connected &&
            !CallService.instance.isCallScreenVisible.value)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: _ActiveCallBar(
                  username: CallService.instance.state.value.otherUsername ?? '',
                  onTap: _openCallScreen,
                ),
              ),
            ),
          ),

        // Ringing UI — hidden when IncomingCallScreen/CallScreen is open (full-screen handles it)
        if (CallService.instance.state.value.status == CallStatus.ringing &&
            !CallService.instance.isCallScreenVisible.value)
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
                          final rCallId = CallService.instance.state.value.callId;
                          final rCaller = CallService.instance.state.value.otherUsername;
                          _cpLog('UI', 'IncomingCallBar → user REJECT tap | callId=$rCallId caller=$rCaller');
                          _uiLog('INCOMING_BAR', 'REJECT_TAP', 'callId=$rCallId caller=$rCaller');
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

        // Group invite banner
        if (CallService.instance.state.value.pendingGroupInvite != null)
          Positioned(
            bottom: 80,
            left: 16,
            right: 16,
            child: _GroupInviteBanner(
              invite: CallService.instance.state.value.pendingGroupInvite!,
              onAccept: () async {
                _cpLog('UI', 'GroupInviteBanner ACCEPT tap');
                await CallService.instance.acceptGroupInvite();
                _openCallScreen();
              },
              onDecline: () {
                _cpLog('UI', 'GroupInviteBanner DECLINE tap');
                CallService.instance.rejectGroupInvite();
                setState(() {});
              },
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

// ── Active Call Floating Indicator ───────────────────────────────────────────
// Shows a green pill at the top when a call is connected but CallScreen is minimized.
// Tapping it returns the user to the active CallScreen.
class _ActiveCallBar extends StatefulWidget {
  final String username;
  final VoidCallback onTap;

  const _ActiveCallBar({required this.username, required this.onTap});

  @override
  State<_ActiveCallBar> createState() => _ActiveCallBarState();
}

class _ActiveCallBarState extends State<_ActiveCallBar> {
  @override
  void initState() {
    super.initState();
    CallService.instance.elapsed.addListener(_onElapsed);
    _uiLog('ACTIVE_BAR', 'SHOW', 'callId=${CallService.instance.state.value.callId} user=${widget.username}');
  }

  void _onElapsed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _uiLog('ACTIVE_BAR', 'HIDE', 'callId=${CallService.instance.state.value.callId} user=${widget.username}');
    CallService.instance.elapsed.removeListener(_onElapsed);
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = CallService.instance.elapsed.value;
    _cpLog('UI', 'ActiveCallBar BUILD | user=${widget.username} elapsed=${_fmt(elapsed)}');

    return GestureDetector(
      onTap: () {
        _cpLog('UI', 'ActiveCallBar TAP → openCallScreen | user=${widget.username}');
        _uiLog('ACTIVE_BAR', 'TAP', 'callId=${CallService.instance.state.value.callId} user=${widget.username}');
        widget.onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF22C55E),
          borderRadius: BorderRadius.circular(100),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.call, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(
              widget.username,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 4,
              height: 4,
              decoration: const BoxDecoration(
                color: Colors.white54,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _fmt(elapsed),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ],
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


// ── Group Invite Banner ───────────────────────────────────────────────────────

class _GroupInviteBanner extends StatelessWidget {
  final dynamic invite; // GroupInvite
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _GroupInviteBanner({
    required this.invite,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final inviterUsername = invite.inviterUsername as String;
    final inviterAvatar = invite.inviterAvatar as String?;
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(20),
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: Colors.grey.shade800,
              backgroundImage: (inviterAvatar != null && inviterAvatar.isNotEmpty)
                  ? CachedNetworkImageProvider(imgUrl(inviterAvatar))
                  : null,
              child: (inviterAvatar == null || inviterAvatar.isEmpty)
                  ? Text(inviterUsername.isNotEmpty ? inviterUsername[0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Aktif Aramaya Davet', style: TextStyle(color: Colors.white70, fontSize: 11)),
                  Text('@$inviterUsername sizi aramaya çağırıyor',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onDecline,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                child: const Icon(Icons.close, color: Colors.white, size: 18),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onAccept,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(color: Color(0xFF22C55E), shape: BoxShape.circle),
                child: const Icon(Icons.call, color: Colors.white, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
