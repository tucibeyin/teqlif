import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../l10n/app_localizations.dart';
import '../config/api.dart';
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

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    // If the caller ends before we answer, pop automatically
    CallService.instance.state.addListener(_onStateChange);
  }

  void _onStateChange() {
    final status = CallService.instance.state.value.status;
    if (status == CallStatus.ended ||
        status == CallStatus.idle ||
        status == CallStatus.missed) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    CallService.instance.state.removeListener(_onStateChange);
    super.dispose();
  }

  Future<void> _accept() async {
    await CallService.instance.acceptCall();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const CallScreen()),
    );
  }

  Future<void> _decline() async {
    await CallService.instance.rejectCall();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final username = widget.callData['caller_username'] as String? ?? '';
    final avatarRaw = widget.callData['caller_avatar'] as String? ?? '';
    final avatarUrl = avatarRaw.isNotEmpty ? imgUrl(avatarRaw) : null;

    return PopScope(
      canPop: false,
      child: Scaffold(
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
                                placeholder: (_, _) => _InitialAvatar(username: username),
                                errorWidget: (_, _, _) => _InitialAvatar(username: username),
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
                        // Decline — ahize aşağı (kırmızı)
                        _CallActionButton(
                          color: const Color(0xFFEF4444),
                          icon: FontAwesomeIcons.phone,
                          rotation: 5 * 3.14159 / 4, // 225° — aşağı
                          label: l.callDecline,
                          onTap: _decline,
                        ),

                        // Accept — ahize yukarı (yeşil)
                        _CallActionButton(
                          color: const Color(0xFF22C55E),
                          icon: FontAwesomeIcons.phone,
                          rotation: 0,
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
      ),
    );
  }
}

class _CallActionButton extends StatelessWidget {
  final Color color;
  final IconData icon;
  final double rotation;
  final String label;
  final VoidCallback onTap;

  const _CallActionButton({
    required this.color,
    required this.icon,
    required this.rotation,
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
            child: Center(
              child: Transform.rotate(
                angle: rotation,
                child: FaIcon(icon, color: Colors.white, size: 28),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
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
