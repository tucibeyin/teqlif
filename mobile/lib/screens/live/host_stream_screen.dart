import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show Helper;
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../config/theme.dart';
import '../../models/stream.dart';
import '../../services/stream_service.dart';
import '../../widgets/auction_panel.dart';
import '../../widgets/chat_panel.dart';

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
  LocalVideoTrack? _localVideoTrack;
  bool _micEnabled = true;
  bool _cameraEnabled = true;
  bool _connecting = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();
    _connect();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
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
        if (event.publication.track is LocalVideoTrack) {
          setState(() {
            _localVideoTrack = event.publication.track as LocalVideoTrack;
          });
        }
      });

      _listener!.on<RoomDisconnectedEvent>((_) {
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
        }
      });

      await room.connect(
        widget.streamToken.livekitUrl,
        widget.streamToken.token,
      );

      await room.localParticipant?.setCameraEnabled(true);
      await room.localParticipant?.setMicrophoneEnabled(true);

      for (final pub in room.localParticipant!.videoTrackPublications) {
        if (pub.track != null) {
          _localVideoTrack = pub.track as LocalVideoTrack;
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

  Future<void> _switchCamera() async {
    if (_localVideoTrack == null) return;
    await Helper.switchCamera(_localVideoTrack!.mediaStreamTrack);
  }

  Future<void> _endStream() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Yayını Bitir',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: const Text('Yayını sonlandırmak istiyor musunuz?',
            style: TextStyle(color: Color(0xFF94A3B8))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal',
                style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Bitir',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await StreamService.endStream(widget.streamToken.streamId);
    } catch (_) {}

    await _room?.disconnect();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final botPad = MediaQuery.of(context).padding.bottom;
    final live = !_connecting && _error == null;

    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // ── Kamera önizleme (tam ekran) ─────────────────────────────────
          if (_localVideoTrack != null)
            Positioned.fill(
              child: VideoTrackRenderer(
                _localVideoTrack!,
                fit: VideoViewFit.contain,
              ),
            ),

          // ── Bağlanıyor ──────────────────────────────────────────────────
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
                      Text('Yayın başlatılıyor...',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 14)),
                    ],
                  ),
                ),
              ),
            ),

          // ── Hata ────────────────────────────────────────────────────────
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
                            color: Colors.red, size: 52),
                        const SizedBox(height: 12),
                        Text(_error!,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 14),
                            textAlign: TextAlign.center),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: () => Navigator.pushNamedAndRemoveUntil(
                              context, '/home', (route) => false),
                          child: const Text('Geri Dön'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // ── Üst bar: LIVE + başlık + kontrol ikonları ──────────────────
          if (live)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.only(
                    top: topPad + 14, left: 16, right: 16, bottom: 32),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xBB000000), Colors.transparent],
                  ),
                ),
                child: Row(
                  children: [
                    // LIVE badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(5)),
                      child: const Text('CANLI',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5)),
                    ),
                    const SizedBox(width: 10),
                    // Başlık
                    Expanded(
                      child: Text(
                        widget.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          shadows: [
                            Shadow(blurRadius: 6, color: Colors.black)
                          ],
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Mikrofon
                    _TopIconBtn(
                      icon: _micEnabled ? Icons.mic_rounded : Icons.mic_off_rounded,
                      active: _micEnabled,
                      onTap: _toggleMic,
                    ),
                    const SizedBox(width: 6),
                    // Kamera
                    _TopIconBtn(
                      icon: _cameraEnabled
                          ? Icons.videocam_rounded
                          : Icons.videocam_off_rounded,
                      active: _cameraEnabled,
                      onTap: _toggleCamera,
                    ),
                    const SizedBox(width: 6),
                    // Kamera çevir
                    _TopIconBtn(
                      icon: Icons.flip_camera_ios_rounded,
                      active: true,
                      onTap: _switchCamera,
                    ),
                    const SizedBox(width: 10),
                    // Yayını Bitir
                    GestureDetector(
                      onTap: _endStream,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text('Bitir',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Alt panel: sohbet + açık artırma ───────────────────────────
          if (live)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.only(bottom: botPad + 8),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xCC000000), Colors.transparent],
                    stops: [0.0, 1.0],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Sohbet (mesajlar üstte yüzer)
                    ChatPanel(streamId: widget.streamToken.streamId),
                    // Açık artırma şeridi (altta sabit)
                    AuctionPanel(
                      streamId: widget.streamToken.streamId,
                      isHost: true,
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Yardımcı widget'lar ────────────────────────────────────────────────────

class _TopIconBtn extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _TopIconBtn({
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: active ? Colors.black45 : Colors.red.withOpacity(0.75),
          shape: BoxShape.circle,
          border: Border.all(
              color: active ? Colors.white30 : Colors.transparent),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}
