import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../config/theme.dart';
import '../../models/stream.dart';
import '../../services/stream_service.dart';
import '../../services/auth_service.dart';

class HostStreamScreen extends StatefulWidget {
  final StreamTokenOut streamToken;
  final String title;

  const HostStreamScreen({
    super.key,
    required this.streamToken,
    required this.title,
  });

  @override
  State<HostStreamScreen> createState() => _HostStreamScreenState();
}

class _HostStreamScreenState extends State<HostStreamScreen> {
  Room? _room;
  EventsListener<RoomEvent>? _listener;
  VideoTrack? _localVideoTrack;
  bool _micEnabled = true;
  bool _cameraEnabled = true;
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
    final camStatus = await Permission.camera.request();
    final micStatus = await Permission.microphone.request();

    if (camStatus.isDenied || micStatus.isDenied) {
      setState(() {
        _error = 'Kamera ve mikrofon izni gerekli';
        _connecting = false;
      });
      return;
    }

    try {
      final room = Room();
      _listener = room.createListener();

      _listener!.on<LocalTrackPublishedEvent>((event) {
        if (event.publication.track is VideoTrack) {
          setState(() {
            _localVideoTrack = event.publication.track as VideoTrack;
          });
        }
      });

      _listener!.on<RoomDisconnectedEvent>((_) {
        if (mounted) Navigator.pop(context);
      });

      await room.connect(
        widget.streamToken.livekitUrl,
        widget.streamToken.token,
      );

      await room.localParticipant?.setCameraEnabled(true);
      await room.localParticipant?.setMicrophoneEnabled(true);

      // Eğer track zaten publish edildiyse
      for (final pub in room.localParticipant!.videoTrackPublications) {
        if (pub.track != null) {
          _localVideoTrack = pub.track as VideoTrack;
          break;
        }
      }

      setState(() {
        _room = room;
        _connecting = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Bağlantı hatası: ${e.toString()}';
        _connecting = false;
      });
    }
  }

  Future<void> _toggleMic() async {
    _micEnabled = !_micEnabled;
    await _room?.localParticipant?.setMicrophoneEnabled(_micEnabled);
    setState(() {});
  }

  Future<void> _toggleCamera() async {
    _cameraEnabled = !_cameraEnabled;
    await _room?.localParticipant?.setCameraEnabled(_cameraEnabled);
    setState(() {});
  }

  Future<void> _endStream() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yayını Bitir'),
        content: const Text('Yayını sonlandırmak istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Bitir', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await StreamService.endStream(widget.streamToken.streamId);
    } catch (_) {}

    await _room?.disconnect();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Kamera önizleme
          if (_localVideoTrack != null)
            Positioned.fill(
              child: VideoTrackRenderer(
                _localVideoTrack!,
                fit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
              ),
            ),

          // Bağlanıyor overlay
          if (_connecting)
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
                        'Yayın başlatılıyor...',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
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

          // Üst bar
          if (!_connecting && _error == null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  _LiveBadge(),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

          // Alt kontroller
          if (!_connecting && _error == null)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 32,
              left: 24,
              right: 24,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _RoundButton(
                    icon: _micEnabled ? Icons.mic : Icons.mic_off,
                    label: _micEnabled ? 'Mikrofon' : 'Sessiz',
                    onTap: _toggleMic,
                  ),
                  const SizedBox(width: 20),
                  _RoundButton(
                    icon: _cameraEnabled
                        ? Icons.videocam
                        : Icons.videocam_off,
                    label: _cameraEnabled ? 'Kamera' : 'Kamera Kapalı',
                    onTap: _toggleCamera,
                  ),
                  const SizedBox(width: 20),
                  _RoundButton(
                    icon: Icons.call_end,
                    label: 'Bitir',
                    color: Colors.red,
                    onTap: _endStream,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(5),
      ),
      child: const Text(
        'CANLI',
        style: TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _RoundButton({
    required this.icon,
    required this.label,
    this.color = const Color(0x99000000),
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              shadows: [Shadow(blurRadius: 4, color: Colors.black)],
            ),
          ),
        ],
      ),
    );
  }
}
