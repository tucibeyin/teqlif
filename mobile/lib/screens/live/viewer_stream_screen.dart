import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart';
import '../../config/theme.dart';
import '../../models/stream.dart';
import '../../services/stream_service.dart';

class ViewerStreamScreen extends StatefulWidget {
  final JoinTokenOut joinToken;

  const ViewerStreamScreen({super.key, required this.joinToken});

  @override
  State<ViewerStreamScreen> createState() => _ViewerStreamScreenState();
}

class _ViewerStreamScreenState extends State<ViewerStreamScreen> {
  Room? _room;
  EventsListener<RoomEvent>? _listener;
  VideoTrack? _remoteVideoTrack;
  bool _connecting = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _connect();
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _listener?.dispose();
    _room?.disconnect();
    super.dispose();
  }

  Future<void> _connect() async {
    try {
      final room = Room();
      _listener = room.createListener();

      _listener!.on<TrackSubscribedEvent>((event) {
        if (event.track is VideoTrack) {
          setState(() {
            _remoteVideoTrack = event.track as VideoTrack;
            _connecting = false;
          });
        }
      });

      _listener!.on<TrackUnsubscribedEvent>((event) {
        if (event.track is VideoTrack) {
          setState(() => _remoteVideoTrack = null);
        }
      });

      _listener!.on<RoomDisconnectedEvent>((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Yayın sona erdi')),
          );
          Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
        }
      });

      await room.connect(
        widget.joinToken.livekitUrl,
        widget.joinToken.token,
        connectOptions: const ConnectOptions(
          autoSubscribe: true,
        ),
      );

      // Zaten yayınlanan track'leri kontrol et (race condition fix)
      for (final participant in room.remoteParticipants.values) {
        for (final pub in participant.videoTrackPublications) {
          if (pub.track != null) {
            _remoteVideoTrack = pub.track as VideoTrack;
            break;
          }
        }
      }

      setState(() {
        _room = room;
        if (_remoteVideoTrack != null) _connecting = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Bağlantı hatası: ${e.toString()}';
        _connecting = false;
      });
    }
  }

  Future<void> _leave() async {
    try {
      await StreamService.leaveStream(widget.joinToken.streamId);
    } catch (_) {}
    await _room?.disconnect();
    if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Uzak video
          if (_remoteVideoTrack != null)
            Positioned.fill(
              child: VideoTrackRenderer(
                _remoteVideoTrack!,
                fit: VideoViewFit.contain,
              ),
            ),

          // Bağlanıyor overlay
          if (_connecting && _error == null)
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.black,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: kPrimary),
                      SizedBox(height: 16),
                      Text(
                        'Yayına bağlanıyor...',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Video yok ama bağlı
          if (!_connecting && _remoteVideoTrack == null && _error == null)
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.black,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.videocam_off_outlined,
                          color: Colors.white38, size: 48),
                      SizedBox(height: 12),
                      Text(
                        'Video bekleniyor...',
                        style: TextStyle(color: Colors.white54, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Hata
          if (_error != null)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            color: Colors.red, size: 48),
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Geri Dön'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Üst bar (gradient + bilgi)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 12,
                left: 16,
                right: 16,
                bottom: 24,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xCC000000), Colors.transparent],
                ),
              ),
              child: Row(
                children: [
                  // Geri
                  GestureDetector(
                    onTap: _leave,
                    child: const Icon(Icons.arrow_back_ios_new,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'CANLI',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.joinToken.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '@${widget.joinToken.hostUsername}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Alt — Ayrıl butonu
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 32,
            left: 0,
            right: 0,
            child: Center(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.exit_to_app, size: 18),
                label: const Text('Yayından Ayrıl'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black54,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                    side: const BorderSide(color: Colors.white24),
                  ),
                ),
                onPressed: _leave,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
