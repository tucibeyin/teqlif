import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import '../../services/localization_service.dart';

/// Canlı yayın — video render katmanı (host & viewer ortak).
///
/// Dört durumu yönetir:
///   1. [track] != null          → _SafeVideoRenderer ile video çizer.
///   2. [track] == null
///      && [cameraEnabled] false → "Kamera Kapalı" placeholder (host).
///   3. [track] == null
///      && [cameraEnabled] true
///      && [waitingLabel] != null → Bekleme placeholder'ı (viewer).
///   4. Diğer durum               → Siyah arka plan.
class LiveVideoPlayer extends ConsumerStatefulWidget {
  final VideoTrack? track;
  final bool cameraEnabled;
  final GlobalKey? repaintKey;
  final String? waitingLabel;
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
  _SafeVideoRenderer? _cachedRenderer;
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
  }

  void _syncRenderer() {
    if (widget.track == null) {
      _cachedRenderer = null;
      _cachedTrack = null;
    } else if (widget.track != _cachedTrack) {
      _cachedTrack = widget.track;
      // Her track değişiminde yeni renderer widget yaratılır.
      // Aynı track ise aynı instance korunur — Flutter identity check ile
      // _SafeVideoRendererState.build() gereksiz çağrılmaz.
      _cachedRenderer = _SafeVideoRenderer(track: widget.track!);
    }
  }

  @override
  Widget build(BuildContext context) {
    // ── Durum 1: Aktif video track ──────────────────────────────────────────
    if (widget.track != null && _cachedRenderer != null) {
      debugPrint('[LVP] Durum 1 — track=${widget.track.runtimeType} isFrontCamera=${widget.isFrontCamera}');
      final needsFlip = widget.isFrontCamera == true;
      return RepaintBoundary(
        key: widget.repaintKey,
        child: needsFlip
            ? Transform(
                alignment: Alignment.center,
                transform: Matrix4.diagonal3Values(-1, 1, 1),
                child: _cachedRenderer!,
              )
            : _cachedRenderer!,
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

    // ── Durum 4: Siyah arka plan (track henüz yok) ──────────────────────────
    debugPrint('[LVP] Durum 4 — track=null cameraEnabled=${widget.cameraEnabled} waitingLabel=${widget.waitingLabel}');
    return const ColoredBox(color: Colors.black);
  }
}

/// RTCVideoRenderer'ı kendi State'inde yöneten güvenli video widget'ı.
///
/// [VideoTrackRenderer]'dan farklı olarak initialize() + srcObject ataması
/// initState() içinde sıralı (await) yapılır. FutureBuilder kullanılmaz,
/// dolayısıyla parent rebuild race condition'ı yoktur.
class _SafeVideoRenderer extends StatefulWidget {
  final VideoTrack track;

  const _SafeVideoRenderer({required this.track});

  @override
  State<_SafeVideoRenderer> createState() => _SafeVideoRendererState();
}

class _SafeVideoRendererState extends State<_SafeVideoRenderer> {
  rtc.RTCVideoRenderer? _renderer;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    debugPrint('[SafeVR] initState → initialize() başlıyor...');
    final r = rtc.RTCVideoRenderer();
    await r.initialize();
    debugPrint('[SafeVR] initialize() tamamlandı — srcObject set ediliyor');
    r.srcObject = widget.track.mediaStream;
    debugPrint('[SafeVR] srcObject=${widget.track.mediaStream.id} set edildi');
    r.onResize = () {
      debugPrint('[SafeVR] onResize — ${r.value.width}×${r.value.height}');
      if (mounted) setState(() {});
    };
    if (!mounted) {
      debugPrint('[SafeVR] widget unmounted, renderer dispose edildi');
      await r.dispose();
      return;
    }
    setState(() {
      _renderer = r;
      _ready = true;
    });
    debugPrint('[SafeVR] _ready=true → RTCVideoView gösterilecek');
  }

  @override
  void didUpdateWidget(_SafeVideoRenderer old) {
    super.didUpdateWidget(old);
    if (old.track != widget.track && _renderer != null) {
      debugPrint('[SafeVR] didUpdateWidget: yeni track, srcObject güncelleniyor');
      _renderer!.srcObject = widget.track.mediaStream;
    }
  }

  @override
  void dispose() {
    debugPrint('[SafeVR] dispose()');
    _renderer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || _renderer == null) {
      return const ColoredBox(color: Colors.black);
    }
    debugPrint('[SafeVR] build() → RTCVideoView gösteriliyor');
    return rtc.RTCVideoView(
      _renderer!,
      objectFit: rtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
      mirror: false,
    );
  }
}
