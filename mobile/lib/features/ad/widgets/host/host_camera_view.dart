import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

/// Full-screen camera or loading placeholder for the host.
class HostCameraView extends StatelessWidget {
  final dynamic roomState; // LiveRoomState
  final Room? room;
  final VideoTrack? localVideoTrack;
  final bool isCameraEnabled;

  const HostCameraView({
    super.key,
    required this.roomState,
    required this.room,
    required this.localVideoTrack,
    required this.isCameraEnabled,
  });

  @override
  Widget build(BuildContext context) {
    if (roomState.isConnecting || (room == null && roomState.error == null)) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black, Color(0xFF1a1a1a)],
          ),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.red),
              SizedBox(height: 24),
              Text('Arena Hazırlanıyor...',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('Bağlantı kuruluyor, lütfen bekleyin.',
                  style: TextStyle(color: Colors.white70, fontSize: 14)),
            ],
          ),
        ),
      );
    } else if (localVideoTrack != null && isCameraEnabled) {
      return SizedBox.expand(
        child: VideoTrackRenderer(
          localVideoTrack!,
          fit: VideoViewFit.cover,
        ),
      );
    } else {
      return const Center(
          child: Icon(Icons.videocam_off, size: 80, color: Colors.white54));
    }
  }
}

/// Draggable Picture-in-Picture for the guest participant.
class GuestTrackPiP extends StatelessWidget {
  final VideoTrack guestTrack;
  final String? guestIdentity;
  final VoidCallback onKick;

  const GuestTrackPiP({
    super.key,
    required this.guestTrack,
    required this.guestIdentity,
    required this.onKick,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                  color: Colors.white.withOpacity(0.5), width: 2),
              borderRadius: BorderRadius.circular(16),
              color: Colors.black,
            ),
            child: guestTrack.muted
                ? const Center(
                    child: Icon(Icons.videocam_off, color: Colors.white54))
                : VideoTrackRenderer(guestTrack, fit: VideoViewFit.cover),
          ),
        ),
        if (guestIdentity != null)
          Positioned(
            top: -8,
            right: -8,
            child: GestureDetector(
              onTap: onKick,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                    color: Colors.red, shape: BoxShape.circle),
                child:
                    const Icon(Icons.close, color: Colors.white, size: 16),
              ),
            ),
          ),
      ],
    );
  }
}
