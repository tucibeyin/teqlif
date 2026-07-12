import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:proximity_sensor/proximity_sensor.dart';
import '../l10n/app_localizations.dart';
import '../config/api.dart';
import '../services/call_service.dart';

class CallScreen extends StatefulWidget {
  const CallScreen({super.key});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  bool _isNear = false;
  bool _hasPopped = false;
  late StreamSubscription<int> _proximitySubscription;

  @override
  void initState() {
    super.initState();
    CallService.instance.state.addListener(_onStateChange);
    _proximitySubscription = ProximitySensor.events.listen((int event) {
      if (mounted) {
        setState(() {
          _isNear = (event > 0);
        });
      }
    });
  }

  void _onStateChange() {
    if (!CallService.instance.hasActiveCall && mounted && !_hasPopped) {
      _hasPopped = true;
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _proximitySubscription.cancel();
    CallService.instance.state.removeListener(_onStateChange);
    super.dispose();
  }

  String _formatElapsed(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return ValueListenableBuilder<CallState>(
      valueListenable: CallService.instance.state,
      builder: (context, cs, _) {
        final avatarUrl = (cs.otherAvatar ?? '').isNotEmpty
            ? imgUrl(cs.otherAvatar)
            : null;
        final username = cs.otherUsername ?? '';

        return Scaffold(
          backgroundColor: Colors.black,
            body: Stack(
              fit: StackFit.expand,
              children: [
                // Background
                if (avatarUrl != null)
                  CachedNetworkImage(
                    imageUrl: avatarUrl,
                    fit: BoxFit.cover,
                  )
                else
                  Container(color: const Color(0xFF0A1628)),
                
                BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                  child: Container(color: Colors.black.withValues(alpha: 0.6)),
                ),

                SafeArea(
                  child: Column(
                    children: [
                      const SizedBox(height: 64),

                      // Avatar
                      Container(
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
                          child: avatarUrl != null && avatarUrl.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: avatarUrl,
                                  fit: BoxFit.cover,
                                  placeholder: (_, _) => _Initials(username: username),
                                  errorWidget: (_, _, _) => _Initials(username: username),
                                )
                              : _Initials(username: username),
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
                      const SizedBox(height: 10),

                      // Status / timer
                      Text(
                        _statusText(cs.status, l, cs.elapsed),
                        style: const TextStyle(color: Colors.white70, fontSize: 16),
                      ),

                      const Spacer(),

                      // Bottom Controls Panel
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B).withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(32),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (cs.status == CallStatus.connected) ...[
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  _ControlButton(
                                    icon: cs.isMuted
                                        ? FontAwesomeIcons.microphoneSlash
                                        : FontAwesomeIcons.microphone,
                                    label: cs.isMuted ? l.callUnmute : l.callMute,
                                    color: cs.isMuted
                                        ? Colors.white24
                                        : Colors.white.withValues(alpha: 0.12),
                                    onTap: () => CallService.instance.toggleMute(),
                                  ),
                                  _ControlButton(
                                    icon: FontAwesomeIcons.video,
                                    label: l.callVideo,
                                    color: Colors.white.withValues(alpha: 0.05),
                                    onTap: () {}, // Disabled for now
                                  ),
                                  _ControlButton(
                                    icon: FontAwesomeIcons.volumeHigh,
                                    label: l.callSpeaker,
                                    color: cs.isSpeaker
                                        ? const Color(0xFF22C55E).withValues(alpha: 0.25)
                                        : Colors.white.withValues(alpha: 0.12),
                                    onTap: () => CallService.instance.setSpeaker(!cs.isSpeaker),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),
                            ],

                            // End call button row
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                if (cs.status == CallStatus.connected)
                                  _ControlButton(
                                    icon: FontAwesomeIcons.message,
                                    label: l.callChat,
                                    color: Colors.white.withValues(alpha: 0.12),
                                    onTap: () => Navigator.pop(context), // Go back to chat
                                  )
                                else
                                  const SizedBox(width: 60), // Placeholder to keep center alignment

                                // End call button
                                if (cs.status == CallStatus.calling ||
                                    cs.status == CallStatus.connecting ||
                                    cs.status == CallStatus.connected)
                                  GestureDetector(
                                    onTap: () => CallService.instance.endCall(),
                                    child: Container(
                                      width: 72,
                                      height: 72,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEF4444),
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFFEF4444).withValues(alpha: 0.45),
                                            blurRadius: 16,
                                          ),
                                        ],
                                      ),
                                      child: Center(
                                        child: Icon(
                                          Icons.call_end,
                                          color: Colors.white,
                                          size: 32,
                                        ),
                                      ),
                                    ),
                                  ),

                                if (cs.status == CallStatus.connected)
                                  _ControlButton(
                                    icon: FontAwesomeIcons.userPlus,
                                    label: l.callAddPerson,
                                    color: Colors.white.withValues(alpha: 0.12),
                                    onTap: () {}, // Disabled
                                  )
                                else
                                  const SizedBox(width: 60), // Placeholder
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Proximity black overlay
                if (_isNear)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black,
                    ),
                  ),
              ],
            ),
          );
        },
      );
  }

  String _statusText(CallStatus s, AppLocalizations l, Duration elapsed) {
    return switch (s) {
      CallStatus.calling => l.callCalling,
      CallStatus.connecting => l.callConnecting,
      CallStatus.connected => _formatElapsed(elapsed),
      CallStatus.ended => l.callEnded,
      CallStatus.rejected => l.callRejected,
      CallStatus.missed => l.callMissed,
      CallStatus.noAnswer => l.callNoAnswer,
      _ => l.callConnecting,
    };
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Center(child: FaIcon(icon, color: Colors.white, size: 22)),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      ),
    );
  }
}

class _Initials extends StatelessWidget {
  final String username;
  const _Initials({required this.username});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1E3A5F),
      alignment: Alignment.center,
      child: Text(
        username.isNotEmpty ? username[0].toUpperCase() : '?',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 44,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
