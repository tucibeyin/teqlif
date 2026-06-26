import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';
import '../../providers/pip_provider.dart';
import '../../screens/live/swipe_live_screen.dart';

class PipVideoWidget extends ConsumerStatefulWidget {
  const PipVideoWidget({super.key});

  @override
  ConsumerState<PipVideoWidget> createState() => _PipVideoWidgetState();
}

class _PipVideoWidgetState extends ConsumerState<PipVideoWidget> {
  Offset? _position;

  @override
  Widget build(BuildContext context) {
    final pip = ref.watch(pipProvider);
    if (!pip.isActive || pip.track == null) return const SizedBox.shrink();

    final size = MediaQuery.of(context).size;
    _position ??= Offset(size.width - 136, size.height - 360);

    return Positioned(
      left: _position!.dx,
      top: _position!.dy,
      child: Material(
        color: Colors.transparent,
        child: GestureDetector(
          onPanUpdate: (details) {
            setState(() {
              _position = Offset(
                (_position!.dx + details.delta.dx).clamp(0.0, size.width - 120),
                (_position!.dy + details.delta.dy).clamp(0.0, size.height - 200),
              );
            });
          },
          onTap: _expandToFullScreen,
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 120,
                  height: 200,
                  child: VideoTrackRenderer(
                    pip.track!,
                    fit: VideoViewFit.cover,
                    mirrorMode: VideoViewMirrorMode.off,
                  ),
                ),
              ),
              // shadow / border
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white24),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              // CANLI badge
              Positioned(
                bottom: 6,
                left: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'CANLI',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),
              // Kapat butonu
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: _closePip,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, color: Colors.white, size: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _closePip() {
    ref.read(pipProvider.notifier).disablePip();
  }

  void _expandToFullScreen() {
    final pip = ref.read(pipProvider);
    final streamId = pip.currentStreamId;
    if (streamId == null) return;
    // Önce PiP'i kapat (Room'u da disconnect eder)
    ref.read(pipProvider.notifier).disablePip();
    // Tam ekrana yeni bağlantıyla aç
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => SwipeLiveScreen.single(streamId: streamId),
      ),
    );
  }
}
