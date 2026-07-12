import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:proximity_sensor/proximity_sensor.dart';
import '../l10n/app_localizations.dart';
import '../config/api.dart';
import '../config/app_colors.dart';
import '../services/call_service.dart';
import 'messages_screen.dart';

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
    CallService.instance.isCallScreenVisible.value = true;
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
      final s = CallService.instance.state.value.status;
      if (s == CallStatus.rejected ||
          s == CallStatus.missed ||
          s == CallStatus.busy ||
          s == CallStatus.noAnswer) {
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted && !_hasPopped) {
            _hasPopped = true;
            Navigator.of(context).pop();
          }
        });
      } else {
        _hasPopped = true;
        Navigator.of(context).pop();
      }
    }
  }

  @override
  void dispose() {
    try {
      _proximitySubscription.cancel().catchError((e) {
        debugPrint('[CallScreen] Proximity cancel error: $e');
      });
    } catch (e) {
      debugPrint('[CallScreen] Proximity cancel sync error: $e');
    }
    CallService.instance.state.removeListener(_onStateChange);
    CallService.instance.isCallScreenVisible.value = false;
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
                CachedNetworkImage(imageUrl: avatarUrl, fit: BoxFit.cover)
              else
                Container(color: AppColors.bg(context)),

              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                child: Container(
                  color: AppColors.isDark(context)
                      ? Colors.black.withValues(alpha: 0.6)
                      : Colors.white.withValues(alpha: 0.6),
                ),
              ),

              SafeArea(
                child: Stack(
                  children: [
                    // Minimize Button
                    Positioned(
                      top: 16,
                      left: 16,
                      child: IconButton(
                        icon: Icon(
                          Icons.keyboard_arrow_down,
                          color: AppColors.textPrimary(context),
                          size: 32,
                        ),
                        onPressed: () {
                          _hasPopped = true;
                          Navigator.of(context).pop();
                        },
                      ),
                    ),

                    Column(
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
                                color: AppColors.isDark(context)
                                    ? Colors.white.withValues(alpha: 0.15)
                                    : Colors.black.withValues(alpha: 0.1),
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
                                    placeholder: (_, _) =>
                                        _Initials(username: username),
                                    errorWidget: (_, _, _) =>
                                        _Initials(username: username),
                                  )
                                : _Initials(username: username),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Username
                        Text(
                          '@$username',
                          style: TextStyle(
                            color: AppColors.textPrimary(context),
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Status / timer
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (cs.isPoorConnection &&
                                cs.status == CallStatus.connected)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Icon(
                                  Icons
                                      .signal_cellular_connected_no_internet_4_bar,
                                  color: Colors.orange,
                                  size: 18,
                                ),
                              ),
                            Text(
                              _statusText(cs.status, l, cs.elapsed),
                              style: TextStyle(
                                color: AppColors.textSecondary(context),
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),

                        const Spacer(),

                        // Bottom Controls Panel
                        Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 32,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 24,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surface(context).withValues(
                              alpha: AppColors.isDark(context) ? 0.25 : 0.8,
                            ),
                            borderRadius: BorderRadius.circular(32),
                            border: Border.all(
                              color: AppColors.border(
                                context,
                              ).withValues(alpha: 0.3),
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (cs.status == CallStatus.connected) ...[
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: [
                                    _ControlButton(
                                      icon: cs.isMuted
                                          ? FontAwesomeIcons.microphoneSlash
                                          : FontAwesomeIcons.microphone,
                                      label: cs.isMuted
                                          ? l.callUnmute
                                          : l.callMute,
                                      color: AppColors.isDark(context)
                                          ? Colors.white.withValues(alpha: 0.2)
                                          : Colors.black.withValues(
                                              alpha: 0.05,
                                            ),
                                      onTap: () =>
                                          CallService.instance.toggleMute(),
                                    ),
                                    _ControlButton(
                                      icon: FontAwesomeIcons.video,
                                      label: l.callVideo,
                                      color: AppColors.isDark(context)
                                          ? Colors.white.withValues(alpha: 0.2)
                                          : Colors.black.withValues(
                                              alpha: 0.05,
                                            ),
                                      onTap: () {}, // Disabled for now
                                    ),
                                    _ControlButton(
                                      icon: FontAwesomeIcons.volumeHigh,
                                      label: l.callSpeaker,
                                      color: cs.isSpeaker
                                          ? const Color(
                                              0xFF22C55E,
                                            ).withValues(alpha: 0.25)
                                          : AppColors.isDark(context)
                                          ? Colors.white.withValues(alpha: 0.2)
                                          : Colors.black.withValues(
                                              alpha: 0.05,
                                            ),
                                      onTap: () => CallService.instance
                                          .setSpeaker(!cs.isSpeaker),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 24),
                              ],

                              // End call button row
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  if (cs.status == CallStatus.connected)
                                    _ControlButton(
                                      icon: FontAwesomeIcons.message,
                                      label: l.callChat,
                                      color: AppColors.isDark(context)
                                          ? Colors.white.withValues(alpha: 0.2)
                                          : Colors.black.withValues(
                                              alpha: 0.05,
                                            ),
                                      onTap: () {
                                        final id = cs.otherUserId;
                                        final username = cs.otherUsername ?? '';
                                        if (id != null) {
                                          Navigator.pushReplacement(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => DirectChatScreen(
                                                otherUserId: id,
                                                displayName: '@$username',
                                                otherHandle: username,
                                              ),
                                            ),
                                          );
                                        } else {
                                          Navigator.pop(context);
                                        }
                                      },
                                    )
                                  else
                                    const SizedBox(
                                      width: 60,
                                    ), // Placeholder to keep center alignment
                                  // End call button
                                  if (cs.status == CallStatus.calling ||
                                      cs.status == CallStatus.connecting ||
                                      cs.status == CallStatus.connected ||
                                      cs.status == CallStatus.reconnecting)
                                    GestureDetector(
                                      onTap: () =>
                                          CallService.instance.endCall(),
                                      child: Container(
                                        width: 72,
                                        height: 72,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEF4444),
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(
                                                0xFFEF4444,
                                              ).withValues(alpha: 0.45),
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
                                      color: AppColors.isDark(context)
                                          ? Colors.white.withValues(alpha: 0.2)
                                          : Colors.black.withValues(
                                              alpha: 0.05,
                                            ),
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
                  ],
                ),
              ),

              // Proximity black overlay
              if (_isNear)
                Positioned.fill(child: Container(color: Colors.black)),
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
      CallStatus.busy => l.callBusy,
      CallStatus.reconnecting => l.callReconnecting,
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
            child: Center(
              child: FaIcon(
                icon,
                color: AppColors.textPrimary(context),
                size: 22,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 13,
            ),
          ),
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
      color: AppColors.surfaceVariant(context),
      alignment: Alignment.center,
      child: Text(
        username.isNotEmpty ? username[0].toUpperCase() : '?',
        style: TextStyle(
          color: AppColors.textPrimary(context),
          fontSize: 48,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
