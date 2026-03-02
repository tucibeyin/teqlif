import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';

import '../../../core/models/ad.dart';
import '../../../core/providers/live_room_provider.dart';
import '../../../core/api/api_client.dart';

class LiveArenaHost extends ConsumerStatefulWidget {
  final AdModel ad;
  const LiveArenaHost({super.key, required this.ad});

  @override
  ConsumerState<LiveArenaHost> createState() => _LiveArenaHostState();
}

class _LiveArenaHostState extends ConsumerState<LiveArenaHost> {
  // Ephemeral Chat
  final List<_EphemeralMessage> _messages = [];
  final TextEditingController _chatCtrl = TextEditingController();
  final FocusNode _chatFocus = FocusNode();

  bool _isCameraEnabled = true;
  bool _isMicEnabled = true;

  @override
  void initState() {
    super.initState();
    // Connect to room as Host
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Request permissions first
      final cameraStatus = await Permission.camera.request();
      final micStatus = await Permission.microphone.request();

      if (cameraStatus.isGranted && micStatus.isGranted) {
        final notifier = ref.read(liveRoomProvider(widget.ad.id).notifier);
        await notifier.connect(true);
        
        final room = ref.read(liveRoomProvider(widget.ad.id)).room;
        if (room != null) {
          room.events.listen(_onRoomEvent);
          
          // Signal backend that we are LIVE
          try {
            await ApiClient().post('/api/ads/${widget.ad.id}/live', data: {
              'isLive': true,
              'liveKitRoomId': widget.ad.id,
            });
          } catch (e) {
            debugPrint('Failed to set isLive to true: $e');
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Yayın başlatmak için kamera ve mikrofon izni gereklidir.')),
          );
          context.pop();
        }
      }
    });
  }

  @override
  void dispose() {
    _chatCtrl.dispose();
    _chatFocus.dispose();
    super.dispose();
  }

  void _handleDataChannelMessage(List<int> data, RemoteParticipant? p) {
    final message = String.fromCharCodes(data);
    setState(() {
      _messages.add(_EphemeralMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: message,
        senderName: p?.name ?? 'Biri',
        timestamp: DateTime.now(),
      ));
      if (_messages.length > 5) { // Host sees maybe a bit more or 3 like viewer
        _messages.removeAt(0);
      }
    });
    // Remove after 4 seconds
    Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() {
          if (_messages.isNotEmpty) {
            _messages.removeAt(0);
          }
        });
      }
    });
  }

  Future<void> _sendChatMessage() async {
    final text = _chatCtrl.text.trim();
    if (text.isEmpty) return;
    final state = ref.read(liveRoomProvider(widget.ad.id));
    if (state.room != null) {
      await state.room!.localParticipant?.publishData(text.codeUnits);
      _handleDataChannelMessage(text.codeUnits, null); // Add my own
    }
    _chatCtrl.clear();
    _chatFocus.unfocus();
  }

  void _onRoomEvent(RoomEvent event) {
    if (event is DataReceivedEvent) {
      _handleDataChannelMessage(event.data, event.participant);
    }
  }

  Future<void> _endLiveStream() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yayını Bitir'),
        content: const Text('Canlı mezatı bitirmek istediğinize emin misiniz? Yayın kapandıktan sonra teklifler onay için hesabınıza düşecektir.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yayını Bitir', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // 1. Tell backend that we are no longer live
      // This ensures the isLive flag is cleared even if webhook takes a moment
      try {
        await ApiClient().post('/api/ads/${widget.ad.id}/live', data: {
          'isLive': false,
        });
      } catch (e) {
        debugPrint('Failed to update isLive status: $e');
      }

      // 2. Disconnect from LiveKit.
      await ref.read(liveRoomProvider(widget.ad.id).notifier).disconnect();
      if (mounted) context.pop(); // Go back to normal ad detail
    }
  }

  Future<void> _kickGuest(String targetUserId) async {
    try {
      await ApiClient().post('/api/livekit/signal', data: {
        'adId': widget.ad.id,
        'targetUserId': targetUserId,
        'signal': 'KICK_FROM_STAGE',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Konuk sahneden alındı.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('İşlem başarısız.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Auto-pop when room is disconnected or closed by host
    ref.listen(liveRoomProvider(widget.ad.id), (previous, next) {
      if (previous?.room != null && next.room == null && !next.isConnecting) {
        if (mounted) context.pop();
      }
    });

    final roomState = ref.watch(liveRoomProvider(widget.ad.id));
    final room = roomState.room;

    VideoTrack? localVideoTrack;
    VideoTrack? guestTrack;
    String? guestIdentity;

    if (room != null) {
      if (room.localParticipant != null) {
        for (var pub in room.localParticipant!.videoTrackPublications) {
          if (pub.track != null) {
            localVideoTrack = pub.track as VideoTrack?;
            break;
          }
        }
      }

      // Guest logic
      if (room.remoteParticipants.isNotEmpty) {
        final firstGuest = room.remoteParticipants.values.first;
        guestIdentity = firstGuest.identity;
        
        for (var pub in firstGuest.videoTrackPublications) {
          if (pub.track != null) {
            guestTrack = pub.track as VideoTrack?;
            break;
          }
        }
      }
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Camera Preview
          if (roomState.isConnecting)
            const Center(child: CircularProgressIndicator(color: Colors.white))
          else if (localVideoTrack != null && _isCameraEnabled)
            SizedBox.expand(
              child: VideoTrackRenderer(
                localVideoTrack,
                fit: VideoViewFit.cover,
              ),
            )
          else
            const Center(child: Icon(Icons.videocam_off, size: 80, color: Colors.white54)),

          if (guestTrack != null)
            Positioned(
              top: 80,
              right: 16,
              width: 100,
              height: 140,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 2),
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.black,
                      ),
                      child: VideoTrackRenderer(
                        guestTrack,
                        fit: VideoViewFit.cover,
                      ),
                    ),
                  ),
                  if (guestIdentity != null)
                    Positioned(
                      top: -12,
                      right: -12,
                      child: IconButton(
                        icon: const Icon(Icons.cancel, color: Colors.redAccent, size: 28),
                        onPressed: () => _kickGuest(guestIdentity!),
                      ),
                    ),
                ],
              ),
            ),

          // 2. UI Overlay
          SafeArea(
            child: Column(
              children: [
                // Header (Host Info)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.sensors, color: Colors.white, size: 14),
                            const SizedBox(width: 6),
                            const Text('YAYINDASIN',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white, size: 28),
                        onPressed: _endLiveStream,
                      )
                    ],
                  ),
                ),

                const Spacer(),

                // Ephemeral Chat & Info Drawer Button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Chat flow
                      Expanded(
                        child: ShaderMask(
                          shaderCallback: (Rect bounds) {
                            return LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.white,
                                Colors.white,
                              ],
                              stops: const [0.0, 0.4, 1.0],
                            ).createShader(bounds);
                          },
                          blendMode: BlendMode.dstIn,
                          child: SizedBox(
                            height: 200,
                            child: ListView.builder(
                              reverse: true,
                              itemCount: _messages.length,
                              itemBuilder: (context, index) {
                                final msg = _messages[_messages.length - 1 - index];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${msg.senderName}:',
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                          shadows: [Shadow(color: Colors.black54, blurRadius: 2)],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          msg.text,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            shadows: [Shadow(color: Colors.black54, blurRadius: 2)],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      // Controls
                      Column(
                        children: [
                          IconButton(
                            icon: Icon(_isCameraEnabled ? Icons.videocam : Icons.videocam_off, color: Colors.white),
                            style: IconButton.styleFrom(backgroundColor: Colors.black45),
                            onPressed: () async {
                              final p = room?.localParticipant;
                              if (p != null) {
                                await p.setCameraEnabled(!_isCameraEnabled);
                                setState(() => _isCameraEnabled = !_isCameraEnabled);
                              }
                            },
                          ),
                          const SizedBox(height: 8),
                          IconButton(
                            icon: Icon(_isMicEnabled ? Icons.mic : Icons.mic_off, color: Colors.white),
                            style: IconButton.styleFrom(backgroundColor: Colors.black45),
                            onPressed: () async {
                              final p = room?.localParticipant;
                              if (p != null) {
                                await p.setMicrophoneEnabled(!_isMicEnabled);
                                setState(() => _isMicEnabled = !_isMicEnabled);
                              }
                            },
                          ),
                        ],
                      )
                    ],
                  ),
                ),

                // Chat Input box
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black87],
                    ),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _chatCtrl,
                            focusNode: _chatFocus,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              hintText: 'İzleyicilere yaz...',
                              hintStyle: TextStyle(color: Colors.white54),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(horizontal: 16),
                            ),
                            onSubmitted: (_) => _sendChatMessage(),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.send, color: Color(0xFF00B4CC)),
                          onPressed: _sendChatMessage,
                        )
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EphemeralMessage {
  final String id;
  final String text;
  final String senderName;
  final DateTime timestamp;

  _EphemeralMessage({
    required this.id,
    required this.text,
    required this.senderName,
    required this.timestamp,
  });
}
