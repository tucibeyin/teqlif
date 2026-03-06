import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:livekit_client/livekit_client.dart';

import '../../../../core/models/ad.dart';
import '../../controllers/live_arena_host_controller.dart';

/// Circular FAB column: stage requests, bids, camera flip, camera toggle, mic toggle.
class HostControlsWidget extends ConsumerWidget {
  final Room? room;
  final AdModel ad;
  final VoidCallback onShowBidsSheet;

  const HostControlsWidget({
    super.key,
    required this.room,
    required this.ad,
    required this.onShowBidsSheet,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(hostControllerProvider(ad));
    final controller = ref.read(hostControllerProvider(ad).notifier);

    return Column(
      children: [
        // Stage request badge
        if (state.stageRequests.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: CircularControlButton(
              icon: Icons.record_voice_over,
              onPressed: () {
                final req = state.stageRequests.first;
                showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                          title: const Text('Sahne İsteği'),
                          content: Text(
                              '${req.name} adlı kullanıcı sahneye katılmak istiyor. Kabul ediyor musunuz?'),
                          actions: [
                            TextButton(
                                onPressed: () {
                                  controller.dismissStageRequest(req.id);
                                  Navigator.pop(ctx);
                                },
                                child: const Text('Reddet')),
                            TextButton(
                                onPressed: () {
                                  controller.inviteToStage(req.id, context);
                                  controller.dismissStageRequest(req.id);
                                  Navigator.pop(ctx);
                                },
                                child: const Text('Kabul Et',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold))),
                          ],
                        ));
              },
              badge: '${state.stageRequests.length}',
              badgeColor: Colors.blueAccent,
            ),
          ),
        // Bids button
        CircularControlButton(
          icon: Icons.gavel,
          onPressed: onShowBidsSheet,
          badge: state.unreadBids > 0 ? '${state.unreadBids}' : null,
        ),
        const SizedBox(height: 12),
        // Camera flip
        CircularControlButton(
          icon: Icons.switch_camera,
          onPressed: () async {
            final p = room?.localParticipant;
            if (p != null) {
              final trackPub = p.videoTrackPublications.firstOrNull;
              if (trackPub != null && trackPub.track != null) {
                try {
                  final mediaTrack = trackPub.track!.mediaStreamTrack;
                  if (mediaTrack != null) {
                    await webrtc.Helper.switchCamera(mediaTrack);
                  }
                } catch (e) {
                  debugPrint('Error switching camera: $e');
                }
              }
            }
          },
        ),
        const SizedBox(height: 12),
        // Camera toggle
        CircularControlButton(
          icon: state.isCameraEnabled ? Icons.videocam : Icons.videocam_off,
          onPressed: () async {
            final p = room?.localParticipant;
            if (p != null) {
              final next = !state.isCameraEnabled;
              await p.setCameraEnabled(next);
              controller.setCameraEnabled(next);
            }
          },
        ),
        const SizedBox(height: 12),
        // Mic toggle
        CircularControlButton(
          icon: state.isMicEnabled ? Icons.mic : Icons.mic_off,
          onPressed: () async {
            final p = room?.localParticipant;
            if (p != null) {
              final next = !state.isMicEnabled;
              await p.setMicrophoneEnabled(next);
              controller.setMicEnabled(next);
            }
          },
        ),
      ],
    );
  }
}

/// Circular icon button with optional badge.
class CircularControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String? badge;
  final Color badgeColor;

  const CircularControlButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.badge,
    this.badgeColor = Colors.red,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.black45,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24),
          ),
          child: IconButton(
            icon: Icon(icon, color: Colors.white),
            onPressed: onPressed,
          ),
        ),
        if (badge != null)
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: badgeColor,
                shape: BoxShape.circle,
              ),
              child: Text(
                badge!,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ),
      ],
    );
  }
}
