import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/localization_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:teqlif/core/network/api_client.dart';
import '../config/app_colors.dart';
import '../services/call_service.dart' show callServiceProvider, CallStatus;
import '../services/push_notification_service.dart';
import '../services/ws_service.dart';
import '../screens/incoming_call_screen.dart';
import '../screens/call_screen.dart';
import '../call/routing/call_screen_router.dart';

void _cpLog(String phase, String msg) {
  debugPrint('[CALL_PROCESS][${DateTime.now().toIso8601String()}][$phase] $msg');
}

void _uiLog(String component, String event, String detail) {
  debugPrint('[UI_CALL][$component][${DateTime.now().toIso8601String()}] $event | $detail');
}

class IncomingCallOverlay extends ConsumerStatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState>? navigatorKey;
  const IncomingCallOverlay({super.key, required this.child, this.navigatorKey});

  @override
  ConsumerState<IncomingCallOverlay> createState() => _IncomingCallOverlayState();
}

class _IncomingCallOverlayState extends ConsumerState<IncomingCallOverlay> {
  StreamSubscription<Map<String, dynamic>>? _notifSub;
  StreamSubscription<Map<String, dynamic>>? _wsSub;
  bool _isBarDismissed = false;
  CallStatus _prevStatus = CallStatus.idle;

  @override
  void initState() {
    super.initState();
    _cpLog('UI', 'IncomingCallOverlay initState | currentStatus=${ref.read(callServiceProvider).state.value.status.name}');
    _notifSub = PushNotificationService.notificationStream.stream.listen(
      _onData,
    );
    _wsSub = ref.read(wsServiceProvider).messageStream.stream.listen(_onData);
    ref.read(callServiceProvider).state.addListener(_onCallState);
    ref.read(callServiceProvider).isCallScreenVisible.addListener(_onCallState);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(callServiceProvider).state.value.status == CallStatus.ringing) {
        _cpLog('UI', 'IncomingCallOverlay cold-start: status=ringing → IncomingCallBar visible | caller=${ref.read(callServiceProvider).state.value.otherUsername}');
      }
    });
  }

  void _onData(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    if (type == null) return;
    if (!type.startsWith('call') && !type.startsWith('incoming')) return;
    _cpLog('UI', 'overlay._onData received | type=$type currentStatus=${ref.read(callServiceProvider).state.value.status}');
    switch (type) {
      case 'incoming_call':
      case 'call_incoming':
        if (ref.read(callServiceProvider).state.value.status != CallStatus.ringing) {
          _cpLog('UI', 'IncomingCallBar will show | caller=${data['caller_username']}');
          _isBarDismissed = false;
          ref.read(callServiceProvider).onIncomingCall(data);
        } else {
          _cpLog('UI', 'incoming_call SKIPPED | already ringing');
        }
        break;
      case 'incoming_call_notification_tap':
        _cpLog('UI', 'notification_tap → openIncomingScreen | status=${ref.read(callServiceProvider).state.value.status}');
        if (ref.read(callServiceProvider).state.value.status == CallStatus.ringing) {
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
        final recoveryStatus = ref.read(callServiceProvider).state.value.status;
        _cpLog('UI', 'WS connected event | currentStatus=${recoveryStatus.name} → checkActiveCall if idle');
        if (recoveryStatus == CallStatus.idle) {
          ref.read(callServiceProvider).checkActiveCall();
        }
        break;
      case 'call_accepted':
        _cpLog('UI', 'call_accepted WS → onCallAccepted + openCallScreen | acceptedAt=${data['accepted_at']} nowUtc=${DateTime.now().toUtc().toIso8601String()}');
        _cpLog('TIMER', 'overlay: call_accepted WS received | acceptedAt=${data['accepted_at']} nowUtc=${DateTime.now().toUtc().toIso8601String()}');
        ref.read(callServiceProvider).onCallAccepted(data);
        _openCallScreen();
        break;
      case 'call_rejected':
        _cpLog('UI', 'call_rejected WS → onCallRejected');
        ref.read(callServiceProvider).onCallRejected();
        break;
      case 'call_ended':
        _cpLog('UI', 'call_ended WS → onCallEnded');
        ref.read(callServiceProvider).onCallEnded();
        break;
      case 'call_missed':
        final missedCallId = data['call_id'] is int
            ? data['call_id'] as int
            : int.tryParse(data['call_id']?.toString() ?? '');
        _cpLog('UI', 'call_missed WS → onCallMissed | callId=$missedCallId');
        ref.read(callServiceProvider).onCallMissed(callId: missedCallId);
        break;
      case 'call_ringing':
        _cpLog('UI', 'call_ringing WS → onCallRinging | callId=${data['call_id']}');
        ref.read(callServiceProvider).onCallRinging();
        break;
      case 'call_unreachable':
        _cpLog('UI', 'call_unreachable WS → onCallUnreachable | callId=${data['call_id']}');
        ref.read(callServiceProvider).onCallUnreachable();
        break;

      // ── Grup Arama ────────────────────────────────────────────────────────
      case 'call_group_invite':
        _cpLog('UI', 'call_group_invite WS → onGroupInviteReceived | callId=${data['call_id']}');
        ref.read(callServiceProvider).onGroupInviteReceived(data);
        // setState to show incoming group invite UI
        if (mounted) setState(() {});
        break;
      case 'call_participant_joined':
        _cpLog('UI', 'call_participant_joined | userId=${data['user_id']} username=${data['username']}');
        ref.read(callServiceProvider).onParticipantJoined(data);
        if (mounted) setState(() {});
        break;
      case 'call_participant_left':
        _cpLog('UI', 'call_participant_left | userId=${data['user_id']}');
        ref.read(callServiceProvider).onParticipantLeft(data);
        if (mounted) setState(() {});
        break;
      case 'call_participant_removed':
        _cpLog('UI', 'call_participant_removed | userId=${data['user_id']} selfRemoved=${data['self_removed']}');
        ref.read(callServiceProvider).onParticipantRemoved(data);
        if (mounted) setState(() {});
        break;
      case 'call_participant_rejected':
        _cpLog('UI', 'call_participant_rejected | userId=${data['user_id']}');
        ref.read(callServiceProvider).onParticipantRejected(data);
        break;
      case 'call_participant_timeout':
        _cpLog('UI', 'call_participant_timeout | userId=${data['user_id']}');
        ref.read(callServiceProvider).onParticipantTimeout(data);
        break;
      case 'call_participant_invited':
        _cpLog('UI', 'call_participant_invited | inviteeId=${data['invitee_id']}');
        break;

      default:
        break;
    }
  }

  void _onCallState() {
    final status = ref.read(callServiceProvider).state.value.status;
    final caller = ref.read(callServiceProvider).state.value.otherUsername ?? '?';
    final callId = ref.read(callServiceProvider).state.value.callId;
    _cpLog('UI', 'overlay._onCallState | ${_prevStatus.name} → ${status.name} isCallScreenVisible=${ref.read(callServiceProvider).isCallScreenVisible.value} callId=$callId');

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

    // Route the call state through the central router (VoIP.md §7.2).
    // Overlay is always foreground; background=false. _openCallScreen() has its
    // own dedup guard (isCallScreenVisible) for defense-in-depth.
    final cs = ref.read(callServiceProvider).state.value;
    final decision = CallScreenRouter.resolveScreen(
      status: status,
      endReason: cs.endReason,
      role: ref.read(callServiceProvider).currentRole,
      swipeLiveActive: ref.read(callServiceProvider).preventCallScreenAutoOpen.value,
      isBackground: false,
      isCallScreenVisible: ref.read(callServiceProvider).isCallScreenVisible.value,
    );
    if (decision == CallScreenDecision.callScreen) {
      _openCallScreen();
    }

    setState(() {});
  }

  void _openIncomingScreen() {
    if (!mounted) return;
    _cpLog('UI', 'IncomingCallBar → user TAP bar body → IncomingCallScreen | callId=${ref.read(callServiceProvider).state.value.callId} caller=${ref.read(callServiceProvider).state.value.otherUsername}');
    final nav = widget.navigatorKey?.currentState ?? Navigator.of(context, rootNavigator: true);
    nav.push(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/incoming_call_screen'),
        fullscreenDialog: true,
        builder: (_) => IncomingCallScreen(
          callData: {
            'caller_username':
                ref.read(callServiceProvider).state.value.otherUsername ?? '',
            'caller_avatar': ref.read(callServiceProvider).state.value.otherAvatar ?? '',
            'call_id': ref.read(callServiceProvider).state.value.callId,
          },
        ),
      ),
    );
  }

  void _openCallScreen() {
    if (!mounted) return;
    if (ref.read(callServiceProvider).isCallScreenVisible.value) {
      _cpLog('UI', 'overlay._openCallScreen SKIPPED | already visible');
      return;
    }
    if (ref.read(callServiceProvider).preventCallScreenAutoOpen.value) {
      _cpLog('UI', 'overlay._openCallScreen SKIPPED | preventAutoOpen=true');
      return;
    }
    final nowUtc = DateTime.now().toUtc();
    final acceptedAt = ref.read(callServiceProvider).acceptedAt;
    final lagStr = acceptedAt != null ? '${nowUtc.difference(acceptedAt.toUtc()).inMilliseconds}ms' : 'N/A';
    _cpLog('TIMER', 'overlay._openCallScreen → /call_screen | acceptedAt=${acceptedAt?.toIso8601String() ?? "NULL"} nowUtc=${nowUtc.toIso8601String()} openLagMs=$lagStr status=${ref.read(callServiceProvider).state.value.status.name}');
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
    final callId = ref.read(callServiceProvider).state.value.callId;
    final caller = ref.read(callServiceProvider).state.value.otherUsername;
    final preConnectReady = ref.read(callServiceProvider).state.value.calleeToken != null;
    _cpLog('UI', 'IncomingCallBar → user ACCEPT tap | callId=$callId caller=$caller nowUtc=${nowUtc.toIso8601String()}');
    _cpLog('TIMER', 'IncomingCallBar: ACCEPT tapped | callId=$callId caller=$caller nowUtc=${nowUtc.toIso8601String()} preConnectTokenReady=$preConnectReady');
    _uiLog('INCOMING_BAR', 'ACCEPT_TAP', 'callId=$callId caller=$caller');
    await ref.read(callServiceProvider).acceptCall();
    if (!mounted) return;
    final status = ref.read(callServiceProvider).state.value.status;
    if (status == CallStatus.connecting) {
      // Mic granted → open CallScreen.
      _openCallScreen();
    } else if (status == CallStatus.ringing &&
        ref.read(callServiceProvider).state.value.permPermanentlyDenied) {
      // permanentlyDenied → open IncomingCallScreen so the modal can be shown there.
      _cpLog('UI', 'IncomingCallBar: permanentlyDenied → openIncomingScreen for modal');
      _openIncomingScreen();
    }
    // denied → ended: _onCallState will rebuild, bar disappears automatically.
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    _wsSub?.cancel();
    ref.read(callServiceProvider).state.removeListener(_onCallState);
    ref.read(callServiceProvider).isCallScreenVisible.removeListener(_onCallState);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,

        // Ringing UI — hidden when IncomingCallScreen/CallScreen is open (full-screen handles it)
        if (ref.read(callServiceProvider).state.value.status == CallStatus.ringing &&
            !ref.read(callServiceProvider).isCallScreenVisible.value)
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
                        callerUsername: ref.read(callServiceProvider).state.value.otherUsername ?? '',
                        callId: ref.read(callServiceProvider).state.value.callId,
                        onRestore: () {
                          _cpLog('UI', 'MinimizedCallBar → user TAP → restored to IncomingCallBar | callId=${ref.read(callServiceProvider).state.value.callId}');
                          setState(() => _isBarDismissed = false);
                        },
                      )
                    : _IncomingCallBar(
                        username: ref.read(callServiceProvider).state.value.otherUsername ?? '',
                        avatarUrl: ref.read(callServiceProvider).state.value.otherAvatar,
                        onTap: _openIncomingScreen,
                        onAccept: _openCallScreenAndAccept,
                        onReject: () {
                          final rCallId = ref.read(callServiceProvider).state.value.callId;
                          final rCaller = ref.read(callServiceProvider).state.value.otherUsername;
                          _cpLog('UI', 'IncomingCallBar → user REJECT tap | callId=$rCallId caller=$rCaller');
                          _uiLog('INCOMING_BAR', 'REJECT_TAP', 'callId=$rCallId caller=$rCaller');
                          setState(() => _isBarDismissed = true);
                          ref.read(callServiceProvider).rejectCall();
                        },
                        onDismiss: () {
                          _cpLog('UI', 'IncomingCallBar → user SWIPE-UP dismiss → MinimizedCallBar | callId=${ref.read(callServiceProvider).state.value.callId}');
                          setState(() => _isBarDismissed = true);
                        },
                      ),
              ),
            ),
          ),

        // Group invite banner
        if (ref.read(callServiceProvider).state.value.pendingGroupInvite != null)
          Positioned(
            bottom: 80,
            left: 16,
            right: 16,
            child: _GroupInviteBanner(
              invite: ref.read(callServiceProvider).state.value.pendingGroupInvite!,
              onAccept: () async {
                _cpLog('UI', 'GroupInviteBanner ACCEPT tap');
                await ref.read(callServiceProvider).acceptGroupInvite();
                _openCallScreen();
              },
              onDecline: () {
                _cpLog('UI', 'GroupInviteBanner DECLINE tap');
                ref.read(callServiceProvider).rejectGroupInvite();
                setState(() {});
              },
            ),
          ),
      ],
    );
  }
}

class _MinimizedCallBar extends ConsumerWidget {
  final VoidCallback onRestore;
  final String callerUsername;
  final int? callId;

  const _MinimizedCallBar({
    required this.onRestore,
    required this.callerUsername,
    this.callId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(localizationProvider);
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
                  loc.t("callIncomingTitle"),
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

class _IncomingCallBar extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(localizationProvider);
    final title = loc.t("callIncomingBody", {"username": username});
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
                          ? CachedNetworkImageProvider(ref.read(apiClientProvider).imgUrl(avatarUrl))
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
                            loc.t("callVoiceCall"),
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
                        label: loc.t("callDecline"),
                        onTap: onReject,
                        logLabel: 'REJECT',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _BarButton(
                        icon: Icons.call,
                        color: const Color(0xFF22C55E),
                        label: loc.t("callAccept"),
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
class _ActiveCallBar extends ConsumerStatefulWidget {
  final String username;
  final VoidCallback onTap;

  const _ActiveCallBar({required this.username, required this.onTap});

  @override
  ConsumerState<_ActiveCallBar> createState() => _ActiveCallBarState();
}

class _ActiveCallBarState extends ConsumerState<_ActiveCallBar> {
  @override
  void initState() {
    super.initState();
    ref.read(callServiceProvider).elapsed.addListener(_onElapsed);
    _uiLog('ACTIVE_BAR', 'SHOW', 'callId=${ref.read(callServiceProvider).state.value.callId} user=${widget.username}');
  }

  void _onElapsed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _uiLog('ACTIVE_BAR', 'HIDE', 'callId=${ref.read(callServiceProvider).state.value.callId} user=${widget.username}');
    ref.read(callServiceProvider).elapsed.removeListener(_onElapsed);
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = ref.read(callServiceProvider).elapsed.value;
    _cpLog('UI', 'ActiveCallBar BUILD | user=${widget.username} elapsed=${_fmt(elapsed)}');

    return GestureDetector(
      onTap: () {
        _cpLog('UI', 'ActiveCallBar TAP → openCallScreen | user=${widget.username}');
        _uiLog('ACTIVE_BAR', 'TAP', 'callId=${ref.read(callServiceProvider).state.value.callId} user=${widget.username}');
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

class _BarButton extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
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

class _GroupInviteBanner extends ConsumerWidget {
  final dynamic invite; // GroupInvite
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _GroupInviteBanner({
    required this.invite,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(localizationProvider);
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
                  ? CachedNetworkImageProvider(ref.read(apiClientProvider).imgUrl(inviterAvatar))
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
                  Text(loc.t('callGroupInviteTitle'), style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  Text(loc.t('callGroupInviteFrom', {'inviter': '@$inviterUsername'}),
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
