import 'dart:async';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../config/api.dart';
import '../config/app_colors.dart';
import '../services/call_service.dart';
import '../services/push_notification_service.dart';
import '../services/ws_service.dart';
import '../screens/incoming_call_screen.dart';
import '../screens/call_screen.dart';

class IncomingCallOverlay extends StatefulWidget {
  final Widget child;
  const IncomingCallOverlay({super.key, required this.child});

  @override
  State<IncomingCallOverlay> createState() => _IncomingCallOverlayState();
}

class _IncomingCallOverlayState extends State<IncomingCallOverlay> {
  StreamSubscription<Map<String, dynamic>>? _notifSub;
  StreamSubscription<Map<String, dynamic>>? _wsSub;
  bool _isBarDismissed = false;

  @override
  void initState() {
    super.initState();
    _notifSub = PushNotificationService.notificationStream.stream.listen(
      _onData,
    );
    _wsSub = WsService.messageStream.stream.listen(_onData);
    CallService.instance.state.addListener(_onCallState);
    CallService.instance.isCallScreenVisible.addListener(_onCallState);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (CallService.instance.state.value.status == CallStatus.ringing) {
        // Cold start, handled by bar automatically
      }
    });
  }

  void _onData(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    switch (type) {
      case 'incoming_call':
      case 'call_incoming':
        if (CallService.instance.state.value.status != CallStatus.ringing) {
          _isBarDismissed = false;
          CallService.instance.onIncomingCall(data);
        }
        break;
      case 'incoming_call_notification_tap':
        if (CallService.instance.state.value.status == CallStatus.ringing) {
          _openIncomingScreen();
        }
        break;
      case 'incoming_call_auto_accept':
        _openCallScreenAndAccept();
        break;
      case 'call_accepted':
        CallService.instance.onCallAccepted(data);
        _openCallScreen();
        break;
      case 'call_rejected':
        CallService.instance.onCallRejected();
        break;
      case 'call_ended':
        CallService.instance.onCallEnded();
        break;
      case 'call_missed':
        CallService.instance.onCallMissed();
        break;
      default:
        break;
    }
  }

  void _onCallState() {
    // Check if the state is ringing to determine if the bar should show.
    // We always call setState to rebuild so the bar can hide when rejected/missed.
    if (CallService.instance.state.value.status != CallStatus.ringing) {
      _isBarDismissed = false;
    }
    setState(() {}); // trigger rebuild for the bar
  }

  void _openIncomingScreen() {
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).push(
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
    if (CallService.instance.isCallScreenVisible.value) return;
    
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
    _openCallScreen();
    await CallService.instance.acceptCall();
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
                        onRestore: () =>
                            setState(() => _isBarDismissed = false),
                      )
                    : _IncomingCallBar(
                        username:
                            CallService.instance.state.value.otherUsername ??
                            '',
                        avatarUrl: CallService.instance.state.value.otherAvatar,
                        onTap: _openIncomingScreen,
                        onAccept: _openCallScreenAndAccept,
                        onReject: () {
                          setState(() => _isBarDismissed = true);
                          CallService.instance.rejectCall();
                        },
                        onDismiss: () {
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

  const _MinimizedCallBar({required this.onRestore});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    return Dismissible(
      key: const Key('minimized_call_bar'),
      direction: DismissDirection.down,
      onDismissed: (_) => onRestore(),
      child: Material(
        type: MaterialType.transparency,
        child: GestureDetector(
          onTap: onRestore,
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

    return Dismissible(
      key: const Key('incoming_call_bar'),
      direction: DismissDirection.up,
      onDismissed: (_) => onDismiss(),
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
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _BarButton(
                        icon: Icons.call,
                        color: const Color(0xFF22C55E),
                        label: l.callAccept,
                        onTap: onAccept,
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

  const _BarButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.5)),
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
