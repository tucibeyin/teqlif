import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../l10n/app_localizations.dart';
import '../config/api.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/call_service.dart';
import 'call_screen.dart';

class IncomingCallScreen extends StatefulWidget {
  final Map<String, dynamic> callData;
  const IncomingCallScreen({super.key, required this.callData});

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulse = Tween<double>(
      begin: 0.92,
      end: 1.08,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    // If the caller ends before we answer, pop automatically
    CallService.instance.state.addListener(_onStateChange);
    
    // Start loud ringtone and haptic only when full screen is open
    CallService.instance.startRingtoneAndVibration();
  }

  Future<void> _onStateChange() async {
    final status = CallService.instance.state.value.status;

    if (_hasNavigated || !mounted) return;

    if (status == CallStatus.ended ||
        status == CallStatus.idle ||
        status == CallStatus.missed) {
      _hasNavigated = true;
      Navigator.of(context).pop();
    } else if (status == CallStatus.connecting) {
      _hasNavigated = true;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          settings: const RouteSettings(name: '/call_screen'),
          builder: (_) => const CallScreen(),
          fullscreenDialog: true,
        ),
      );
    } else if (status == CallStatus.permissionDenied) {
      if (mounted) {
        final isPermanent =
            CallService.instance.state.value.permPermanentlyDenied;
        CallService.instance.reset();
        Navigator.of(context).pop();
        if (isPermanent) {
          // iOS kalıcı reddi: Settings'e yönlendir
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(AppLocalizations.of(ctx)!.callPermissionDenied),
              content: Text(AppLocalizations.of(ctx)!.voicePermissionDenied),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(AppLocalizations.of(ctx)!.btnCancel),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await openAppSettings();
                  },
                  child: Text(AppLocalizations.of(ctx)!.navSettings),
                ),
              ],
            ),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    CallService.instance.stopRingtoneAndVibration();
    CallService.instance.state.removeListener(_onStateChange);
    super.dispose();
  }

  Future<void> _accept() async {
    await CallService.instance.acceptCall();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/call_screen'),
        builder: (_) => const CallScreen(),
        fullscreenDialog: true,
      ),
    );
  }

  Future<void> _decline() async {
    await CallService.instance.rejectCall();
    // _onStateChange listener will automatically pop the screen when state becomes idle
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final username = widget.callData['caller_username'] as String? ?? '';
    final avatarRaw = widget.callData['caller_avatar'] as String? ?? '';
    final avatarUrl = avatarRaw.isNotEmpty ? imgUrl(avatarRaw) : null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Blurred dark background
          Container(color: const Color(0xFF0A1628)),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(color: Colors.black.withValues(alpha: 0.55)),
          ),

          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 64),

                // Title
                Text(
                  l.callIncomingTitle,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 32),

                // Avatar with pulse
                ScaleTransition(
                  scale: _pulse,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.15),
                          blurRadius: 32,
                          spreadRadius: 8,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: avatarUrl != null
                          ? CachedNetworkImage(
                              imageUrl: avatarUrl,
                              fit: BoxFit.cover,
                              placeholder: (_, _) =>
                                  _InitialAvatar(username: username),
                              errorWidget: (_, _, _) =>
                                  _InitialAvatar(username: username),
                            )
                          : _InitialAvatar(username: username),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Username
                Text(
                  '@$username',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l.callVoiceCall,
                  style: const TextStyle(color: Colors.white60, fontSize: 15),
                ),

                const Spacer(),

                // Accept / Decline buttons
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 64),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Decline
                      _CallActionButton(
                        color: const Color(0xFFEF4444),
                        icon: Icons.call_end,
                        label: l.callDecline,
                        onTap: _decline,
                      ),

                      // Accept
                      _CallActionButton(
                        color: const Color(0xFF22C55E),
                        icon: Icons.call,
                        label: l.callAccept,
                        onTap: _accept,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 56),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CallActionButton extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _CallActionButton({
    required this.color,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.45),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Center(child: Icon(icon, color: Colors.white, size: 32)),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
      ],
    );
  }
}

class _InitialAvatar extends StatelessWidget {
  final String username;
  const _InitialAvatar({required this.username});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1E3A5F),
      alignment: Alignment.center,
      child: Text(
        username.isNotEmpty ? username[0].toUpperCase() : '?',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 48,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
