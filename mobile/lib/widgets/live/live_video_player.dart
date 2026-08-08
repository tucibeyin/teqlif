import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/localization_service.dart';

/// Canlı yayın — video render katmanı (host & viewer ortak).
///
/// Dört durumu yönetir:
///   1. [track] != null          → VideoTrackRenderer ile video çizer.
///   2. [track] == null
///      && [cameraEnabled] false → "Kamera Kapalı" placeholder (host).
///   3. [track] == null
///      && [cameraEnabled] true
///      && [waitingLabel] != null → Bekleme placeholder'ı (viewer).
///   4. Diğer durum               → Siyah arka plan.
///
/// [track] olarak hem [LocalVideoTrack] (host) hem [RemoteVideoTrack]
/// (viewer) geçilebilir; ikisi de [VideoTrack]'in alt tipidir.
///
/// [repaintKey] thumbnail yakalama (RenderRepaintBoundary) için
/// RepaintBoundary'e atanır; null geçilirse anahtar kullanılmaz.
class LiveVideoPlayer extends ConsumerStatefulWidget {
  final VideoTrack? track;
  final bool cameraEnabled;
  final GlobalKey? repaintKey;

  /// [track] null + [cameraEnabled] true olduğunda gösterilecek metin.
  final String? waitingLabel;

  /// Host'un aktif kamera yönü. Ön kamera auto-mirror, arka kamera
  /// açıkça mirror gerektirir. Viewer (remote track) için null geçilir.
  final bool? isFrontCamera;

  const LiveVideoPlayer({
    super.key,
    required this.track,
    required this.cameraEnabled,
    this.repaintKey,
    this.waitingLabel,
    this.isFrontCamera,
  });

  @override
  ConsumerState<LiveVideoPlayer> createState() => _LiveVideoPlayerState();
}

class _LiveVideoPlayerState extends ConsumerState<LiveVideoPlayer> {
  // VideoTrackRenderer instance'ı cache'lenir. Parent her rebuild ettiğinde
  // _aynı_ instance döner. Flutter'ın updateChild() optimizasyonu:
  //   "if (child.widget == newWidget) → skip rebuild"
  // Böylece _VideoTrackRendererState.build() çağrılmaz ve
  // _initializeRenderer() yalnızca bir kez koşar → RTCVideoRenderer race yok.
  VideoTrackRenderer? _trackRenderer;
  VideoTrack? _cachedTrack;

  @override
  void initState() {
    super.initState();
    _syncRenderer();
  }

  @override
  void didUpdateWidget(LiveVideoPlayer old) {
    super.didUpdateWidget(old);
    if (old.track != widget.track) {
      _syncRenderer();
    }
    // Track aynıysa _trackRenderer dokunulmaz — aynı instance korunur.
  }

  void _syncRenderer() {
    if (widget.track == null) {
      _trackRenderer = null;
      _cachedTrack = null;
    } else if (widget.track != _cachedTrack) {
      _cachedTrack = widget.track;
      _trackRenderer = VideoTrackRenderer(
        widget.track!,
        fit: VideoViewFit.contain,
        mirrorMode: VideoViewMirrorMode.off,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // ── Durum 1: Aktif video track ──────────────────────────────────────────
    if (widget.track != null && _trackRenderer != null) {
      debugPrint('[LVP] Durum 1 build — track=${widget.track.runtimeType} isFrontCamera=${widget.isFrontCamera}');
      final needsFlip = widget.isFrontCamera == true;
      return RepaintBoundary(
        key: widget.repaintKey,
        child: needsFlip
            ? Transform(
                alignment: Alignment.center,
                transform: Matrix4.diagonal3Values(-1, 1, 1),
                child: _trackRenderer!,
              )
            : _trackRenderer!,
      );
    }

    // ── Durum 2: Kamera kasıtlı olarak kapatıldı (host) ────────────────────
    if (!widget.cameraEnabled) {
      final loc = ref.watch(localizationProvider);
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.videocam_off_rounded,
                color: Colors.white24,
                size: 60,
              ),
              const SizedBox(height: 12),
              Text(
                loc.t("liveCameraClosed"),
                style: const TextStyle(
                  color: Colors.white30,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ── Durum 3: Track bekleniyor — viewer için özel mesaj ─────────────────
    if (widget.waitingLabel != null) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.videocam_off_outlined,
                color: Colors.white24,
                size: 52,
              ),
              const SizedBox(height: 12),
              Text(
                widget.waitingLabel!,
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ── Durum 4: Siyah arka plan (track henüz publish edilmedi) ────────────
    debugPrint('[LVP] Durum 4 — track=null cameraEnabled=${widget.cameraEnabled} waitingLabel=${widget.waitingLabel}');
    return const ColoredBox(color: Colors.black);
  }
}
