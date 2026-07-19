import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:proximity_sensor/proximity_sensor.dart';
import 'package:livekit_client/livekit_client.dart';
import '../l10n/app_localizations.dart';
import '../config/api.dart';
import '../config/app_colors.dart';
import '../services/call_service.dart';
import '../models/call_participant.dart';
import 'messages_screen.dart';

void _cpLog(String phase, String msg) {
  debugPrint('[CALL_PROCESS][${DateTime.now().toIso8601String()}][$phase] $msg');
}

void _uiLog(String component, String event, String detail) {
  debugPrint('[UI_CALL][$component][${DateTime.now().toIso8601String()}] $event | $detail');
}

class CallScreen extends StatefulWidget {
  const CallScreen({super.key});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  bool _isNear = false;
  bool _hasPopped = false;
  late StreamSubscription<int> _proximitySubscription;

  // PiP local video position (left/top from screen origin, lazy-init on first build)
  Offset? _pipPos;

  // Toast for participant joined/left/removed
  String? _toastMessage;
  Timer? _toastTimer;

  @override
  void initState() {
    super.initState();
    _cpLog('UI', 'CallScreen initState | callId=${CallService.instance.state.value.callId} status=${CallService.instance.state.value.status.name}');
    _uiLog('CALL_SCREEN', 'OPEN', 'callId=${CallService.instance.state.value.callId} status=${CallService.instance.state.value.status.name}');
    // isCallScreenVisible → CallRouteObserver yönetir (call_route_observer.dart).
    // initState'den set etmek observer'a ihtiyaç bırakmaz ve frame gecikmesi yaratırdı.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onStateChange();
    });
    CallService.instance.state.addListener(_onStateChange);
    CallService.instance.state.addListener(_onParticipantStateChange);
    _proximitySubscription = ProximitySensor.events.listen((int event) {
      if (mounted) {
        final isNear = event > 0;
        if (isNear != _isNear) {
          _cpLog('HW', 'proximitySensor CHANGED | isNear=$isNear → screen ${isNear ? "BLACKOUT (ear-mode)" : "RESTORE (away-from-ear)"}');
        }
        setState(() {
          _isNear = isNear;
        });
      }
    });
  }

  void _onStateChange() {
    final s = CallService.instance.state.value.status;
    // elapsed artık CallState'te değil — ayrı notifier'da. _onStateChange'de kullanılmaz.
    final acceptedAt = CallService.instance.state.value.acceptedAt;
    _cpLog('UI', 'CallScreen._onStateChange | status=${s.name} hasActiveCall=${CallService.instance.hasActiveCall} hasPopped=$_hasPopped');
    _uiLog('CALL_SCREEN', 'STATUS_CHANGE', 'callId=${CallService.instance.state.value.callId} status=${s.name}');
    if (s == CallStatus.connected && CallService.instance.elapsed.value == Duration.zero) {
      final nowUtc = DateTime.now().toUtc();
      _cpLog('TIMER', 'CallScreen: first CONNECTED state | acceptedAt=${acceptedAt?.toIso8601String() ?? "NULL"} elapsedNotifier=${CallService.instance.elapsed.value.inMilliseconds}ms nowUtc=${nowUtc.toIso8601String()}');
      _uiLog('CALL_SCREEN', 'CONNECTED', 'callId=${CallService.instance.state.value.callId} acceptedAt=${acceptedAt?.toIso8601String() ?? "NULL"}');
    }
    if (!CallService.instance.hasActiveCall && mounted && !_hasPopped) {
      if (s == CallStatus.rejected ||
          s == CallStatus.missed ||
          s == CallStatus.busy ||
          s == CallStatus.noAnswer) {
        _cpLog('UI', 'CallScreen → delayed pop (2s) | reason=${s.name}');
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted && !_hasPopped) {
            _cpLog('UI', 'CallScreen → pop (delayed) | reason=${s.name}');
            _hasPopped = true;
            Navigator.of(context).pop();
          }
        });
      } else {
        _cpLog('UI', 'CallScreen → pop immediately | reason=${s.name}');
        _hasPopped = true;
        Navigator.of(context).pop();
      }
    }
  }

  @override
  void dispose() {
    _cpLog('UI', 'CallScreen dispose | callId=${CallService.instance.state.value.callId}');
    _uiLog('CALL_SCREEN', 'CLOSE', 'callId=${CallService.instance.state.value.callId} status=${CallService.instance.state.value.status.name}');
    try {
      _proximitySubscription.cancel().catchError((e) {
        _cpLog('UI', 'CallScreen proximity cancel error | $e');
      });
    } catch (e) {
      _cpLog('UI', 'CallScreen proximity cancel sync error | $e');
    }
    CallService.instance.state.removeListener(_onStateChange);
    CallService.instance.state.removeListener(_onParticipantStateChange);
    _toastTimer?.cancel();
    // isCallScreenVisible → Navigator.pop tetikler didPop → CallRouteObserver false set eder.
    super.dispose();
  }

  List<CallParticipant> _prevParticipants = [];

  void _onParticipantStateChange() {
    final cs = CallService.instance.state.value;
    final current = cs.participants;

    // Detect joined
    for (final p in current) {
      if (!_prevParticipants.any((pp) => pp.userId == p.userId)) {
        _showToast('${p.username} aramaya katıldı');
      }
    }
    // Detect left/removed
    for (final p in _prevParticipants) {
      if (!current.any((pp) => pp.userId == p.userId)) {
        _showToast('${p.username} aramadan ayrıldı');
      }
    }
    _prevParticipants = List.from(current);
  }

  void _showToast(String message) {
    _cpLog('UI', 'CallScreen toast | $message');
    _toastTimer?.cancel();
    if (mounted) {
      setState(() => _toastMessage = message);
      _toastTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _toastMessage = null);
      });
    }
  }

  void _showInviteModal(BuildContext context, CallState cs) {
    if (cs.callId == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => InviteToCallModal(callId: cs.callId!),
    );
  }

  void _showRemoveParticipantSheet(BuildContext context, CallParticipant p, CallState cs) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('@${p.username}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.person_remove, color: Colors.red),
                title: const Text('Aramadan Çıkar', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Aramadan Çıkar'),
                      content: Text('${p.username} kişisini aramadan çıkarmak istiyor musunuz?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            _cpLog('UI', 'Remove participant confirmed | userId=${p.userId}');
                            CallService.instance.removeParticipant(p.userId).catchError((e) {
                              _cpLog('UI', 'removeParticipant ERROR | $e');
                            });
                          },
                          child: const Text('Çıkar', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatElapsed(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    _cpLog('UI', 'CallScreen build | status=${CallService.instance.state.value.status.name}');
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

              // Remote video — BEFORE SafeArea so controls always render on top
              if (cs.remoteVideoEnabled && cs.status == CallStatus.connected) ...[
                Positioned.fill(
                  child: _RemoteVideoView(
                    room: CallService.instance.room,
                  ),
                ),
                Positioned.fill(
                  child: Container(color: Colors.black.withValues(alpha: 0.25)),
                ),
              ],

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
                          _cpLog('UI', 'CallScreen minimize tapped → pop');
                          _uiLog('CALL_SCREEN', 'MINIMIZE_TAP', 'callId=${CallService.instance.state.value.callId}');
                          _hasPopped = true;
                          // Prevent overlay from auto-pushing call screen back when
                          // isCallScreenVisible drops to false during the pop.
                          CallService.instance.preventCallScreenAutoOpen.value = true;
                          Navigator.of(context).pop();
                        },
                      ),
                    ),

                    // Poor connection banner — slides in/out at the top
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: AnimatedSlide(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                        offset: cs.isPoorConnection && cs.status == CallStatus.connected
                            ? Offset.zero
                            : const Offset(0, -1),
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 250),
                          opacity: cs.isPoorConnection && cs.status == CallStatus.connected ? 1.0 : 0.0,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            color: Colors.orange.withValues(alpha: 0.92),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.signal_wifi_bad,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  l.callAudioQualityPoor,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    Column(
                      children: [
                        // Hide avatar/name/status when remote video is fullscreen
                        if (!cs.remoteVideoEnabled || cs.status != CallStatus.connected) ...[
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
                          ValueListenableBuilder<Duration>(
                            valueListenable: CallService.instance.elapsed,
                            builder: (context, elapsedDuration, _) {
                              return Text(
                                _statusText(cs.status, l, elapsedDuration),
                                style: TextStyle(
                                  color: AppColors.textSecondary(context),
                                  fontSize: 16,
                                ),
                              );
                            },
                          ),
                        ] else ...[
                          // Video mode: show name + timer in a compact top bar
                          Padding(
                            padding: const EdgeInsets.only(top: 16, left: 16, right: 16),
                            child: Row(
                              children: [
                                const SizedBox(width: 48), // space for minimize button
                                Expanded(
                                  child: Column(
                                    children: [
                                      Text(
                                        '@$username',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                                        ),
                                      ),
                                      ValueListenableBuilder<Duration>(
                                        valueListenable: CallService.instance.elapsed,
                                        builder: (context, elapsed, _) => Text(
                                          _statusText(cs.status, l, elapsed),
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 13,
                                            shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 48), // symmetric
                              ],
                            ),
                          ),
                        ],

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
                                      icon: cs.localVideoEnabled
                                          ? FontAwesomeIcons.videoSlash
                                          : FontAwesomeIcons.video,
                                      label: cs.localVideoEnabled
                                          ? l.callCameraOff
                                          : l.callCameraOn,
                                      color: cs.localVideoEnabled
                                          ? const Color(0xFF22C55E).withValues(alpha: 0.25)
                                          : AppColors.isDark(context)
                                          ? Colors.white.withValues(alpha: 0.2)
                                          : Colors.black.withValues(alpha: 0.05),
                                      onTap: () {
                                        _cpLog('UI', 'Camera toggle tap | localVideo=${cs.localVideoEnabled}');
                                        CallService.instance.toggleCamera();
                                      },
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
                                          // Prevent overlay from re-pushing call screen when
                                          // pushReplacement drops isCallScreenVisible to false.
                                          CallService.instance.preventCallScreenAutoOpen.value = true;
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
                                      onTap: () {
                                        _cpLog('END', 'CallScreen END CALL tapped | callId=${CallService.instance.state.value.callId}');
                                        _uiLog('CALL_SCREEN', 'END_TAP', 'callId=${CallService.instance.state.value.callId}');
                                        CallService.instance.endCall();
                                      },
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
                                          : Colors.black.withValues(alpha: 0.05),
                                      onTap: () {
                                        _cpLog('UI', 'Invite person tap | callId=${cs.callId}');
                                        _showInviteModal(context, cs);
                                      },
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

              // Local video PiP — freely draggable anywhere on screen
              if (cs.localVideoEnabled && cs.status == CallStatus.connected)
                Builder(builder: (context) {
                  const double pipW = 100, pipH = 140, pad = 8;
                  final size = MediaQuery.of(context).size;
                  _pipPos ??= Offset(
                    size.width - pipW - 16,
                    size.height - pipH - 200,
                  );
                  return Positioned(
                    left: _pipPos!.dx,
                    top: _pipPos!.dy,
                    child: GestureDetector(
                      onPanUpdate: (d) {
                        setState(() {
                          _pipPos = Offset(
                            (_pipPos!.dx + d.delta.dx).clamp(pad, size.width - pipW - pad),
                            (_pipPos!.dy + d.delta.dy).clamp(pad, size.height - pipH - pad),
                          );
                        });
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: pipW,
                          height: pipH,
                          child: _LocalVideoView(
                            room: CallService.instance.room,
                          ),
                        ),
                      ),
                    ),
                  );
                }),

              // Camera switch button — top-right when local video active
              if (cs.localVideoEnabled && cs.status == CallStatus.connected)
                Positioned(
                  top: 16,
                  right: 16,
                  child: SafeArea(
                    child: GestureDetector(
                      onTap: () {
                        _cpLog('UI', 'Camera switch tap');
                        CallService.instance.switchCamera();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.flip_camera_ios,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ),

              // Participant avatar strip — top center when group call active
              if (cs.status == CallStatus.connected && cs.participants.isNotEmpty)
                Positioned(
                  top: 60,
                  left: 0,
                  right: 0,
                  child: _ParticipantStrip(
                    participants: cs.participants,
                    onLongPress: (p) => _showRemoveParticipantSheet(context, p, cs),
                  ),
                ),

              // Toast — bottom center, 3s auto-dismiss
              if (_toastMessage != null)
                Positioned(
                  bottom: 160,
                  left: 32,
                  right: 32,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Text(
                        _toastMessage!,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ),
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
    if (s == CallStatus.connected) {
      final formatted = _formatElapsed(elapsed);
      if (elapsed.inSeconds <= 5) {
        _cpLog('TIMER', 'CallScreen UI RENDER | elapsed=${elapsed.inMilliseconds}ms ($formatted) acceptedAt=${CallService.instance.state.value.acceptedAt?.toIso8601String() ?? "NULL"}');
      }
      return formatted;
    }
    return switch (s) {
      CallStatus.calling => l.callCalling,
      CallStatus.connecting => l.callConnecting,
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

// ── Remote video fullscreen view ─────────────────────────────────────────────

class _RemoteVideoView extends StatelessWidget {
  final Room? room;
  const _RemoteVideoView({this.room});

  @override
  Widget build(BuildContext context) {
    final room = this.room;
    if (room == null) return const SizedBox.shrink();
    final remote = room.remoteParticipants.values.firstOrNull;
    if (remote == null) return const SizedBox.shrink();
    final pub = remote.videoTrackPublications
        .where((p) => p.subscribed && p.track != null)
        .firstOrNull;
    if (pub?.track == null) return const SizedBox.shrink();
    return VideoTrackRenderer(pub!.track as VideoTrack);
  }
}

// ── Local video PiP view ──────────────────────────────────────────────────────

class _LocalVideoView extends StatelessWidget {
  final Room? room;
  const _LocalVideoView({this.room});

  @override
  Widget build(BuildContext context) {
    final room = this.room;
    if (room == null) return const SizedBox.shrink();
    final pub = room.localParticipant?.videoTrackPublications
        .where((p) => p.track != null)
        .firstOrNull;
    if (pub?.track == null) return const SizedBox.shrink();
    return VideoTrackRenderer(pub!.track as VideoTrack, mirrorMode: VideoViewMirrorMode.mirror);
  }
}

// ── Participant avatar strip ──────────────────────────────────────────────────

class _ParticipantStrip extends StatelessWidget {
  final List<CallParticipant> participants;
  final void Function(CallParticipant) onLongPress;

  const _ParticipantStrip({
    required this.participants,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final shown = participants.take(3).toList();
    final extra = participants.length - 3;
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final p in shown)
            GestureDetector(
              onLongPress: () => onLongPress(p),
              child: Tooltip(
                message: '@${p.username}',
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: ClipOval(
                    child: p.avatar != null && p.avatar!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: imgUrl(p.avatar!),
                            fit: BoxFit.cover,
                          )
                        : Container(
                            color: Colors.grey.shade700,
                            alignment: Alignment.center,
                            child: Text(
                              p.username.isNotEmpty ? p.username[0].toUpperCase() : '?',
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                  ),
                ),
              ),
            ),
          if (extra > 0)
            Container(
              margin: const EdgeInsets.only(left: 4),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.5),
                border: Border.all(color: Colors.white, width: 2),
              ),
              alignment: Alignment.center,
              child: Text('+$extra', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
    );
  }
}

// ── InviteToCallModal ─────────────────────────────────────────────────────────

class InviteToCallModal extends StatefulWidget {
  final int callId;
  const InviteToCallModal({super.key, required this.callId});

  @override
  State<InviteToCallModal> createState() => _InviteToCallModalState();
}

class _InviteToCallModalState extends State<InviteToCallModal> {
  final TextEditingController _search = TextEditingController();
  List<Map<String, dynamic>> _following = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  final Map<int, String> _inviteState = {}; // userId → 'pending'|'sent'

  @override
  void initState() {
    super.initState();
    _loadFollowing();
    _search.addListener(_onSearch);
  }

  @override
  void dispose() {
    _search.removeListener(_onSearch);
    _search.dispose();
    super.dispose();
  }

  void _onSearch() {
    final q = _search.text.toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? _following
          : _following.where((u) {
              final name = (u['username'] as String? ?? '').toLowerCase();
              return name.contains(q);
            }).toList();
    });
  }

  Future<void> _loadFollowing() async {
    try {
      final data = await CallService.instance.fetchFollowingForInvite();
      if (mounted) {
        setState(() {
          _following = data;
          _filtered = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        left: 24,
        right: 24,
        top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Aramaya Davet Et',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: 'Takip ettiklerini ara...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_filtered.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text('Kimse bulunamadı', style: TextStyle(color: AppColors.textSecondary(context))),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _filtered.length,
                itemBuilder: (_, i) {
                  final u = _filtered[i];
                  final uid = u['id'] as int;
                  final username = u['username'] as String? ?? '';
                  final avatar = u['avatar'] as String?;
                  final state = _inviteState[uid];
                  final isInThisCall = u['in_this_call'] == true;
                  final isInOtherCall = u['in_other_call'] == true;

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: (avatar != null && avatar.isNotEmpty)
                          ? CachedNetworkImageProvider(imgUrl(avatar))
                          : null,
                      child: (avatar == null || avatar.isEmpty)
                          ? Text(username.isNotEmpty ? username[0].toUpperCase() : '?')
                          : null,
                    ),
                    title: Text('@$username'),
                    trailing: isInThisCall
                        ? Text('Aramada', style: TextStyle(color: Colors.grey, fontSize: 12))
                        : isInOtherCall
                        ? Text('Meşgul', style: TextStyle(color: Colors.red, fontSize: 12))
                        : state == 'pending'
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : state == 'sent'
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : TextButton(
                            onPressed: () async {
                              setState(() => _inviteState[uid] = 'pending');
                              try {
                                await CallService.instance.inviteToCall(uid);
                                if (mounted) setState(() => _inviteState[uid] = 'sent');
                              } catch (e) {
                                if (mounted) setState(() => _inviteState.remove(uid));
                              }
                            },
                            child: const Text('Davet Gönder'),
                          ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
