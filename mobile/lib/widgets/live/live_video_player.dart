import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import '../../services/localization_service.dart';

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
    debugPrint(
      '[LVP] initState — track=${widget.track?.runtimeType} cameraEnabled=${widget.cameraEnabled}',
    );
    _syncRenderer();
  }

  @override
  void didUpdateWidget(LiveVideoPlayer old) {
    super.didUpdateWidget(old);
    debugPrint(
      '[LVP] didUpdateWidget — old.track=${old.track?.runtimeType} new.track=${widget.track?.runtimeType} trackChanged=${old.track != widget.track} cameraChanged=${old.cameraEnabled != widget.cameraEnabled} isFrontChanged=${old.isFrontCamera != widget.isFrontCamera}',
    );
    if (old.track != widget.track) {
      _syncRenderer();
    }
  }

  void _syncRenderer() {
    if (widget.track == null) {
      debugPrint('[LVP] _syncRenderer — track=null, renderer temizlendi');
      _cachedRenderer = null;
      _cachedTrack = null;
    } else if (widget.track != _cachedTrack) {
      debugPrint(
        '[LVP] _syncRenderer — YENİ renderer oluşturuluyor: track=${widget.track.runtimeType} hashCode=${widget.track.hashCode}',
      );
      _cachedTrack = widget.track;
      _cachedRenderer = _SafeVideoRenderer(track: widget.track!);
    } else {
      debugPrint(
        '[LVP] _syncRenderer — aynı track, renderer korunuyor (identity: ${_cachedRenderer.hashCode})',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.track != null && _cachedRenderer != null) {
      final needsFlip = widget.isFrontCamera == true;
      debugPrint(
        '[LVP] build — Durum 1 | track=${widget.track.runtimeType} isFrontCamera=${widget.isFrontCamera} rendererIdentity=${_cachedRenderer.hashCode} repaintKey=${widget.repaintKey}',
      );
      return LayoutBuilder(
        builder: (ctx, constraints) {
          debugPrint('[LVP] LayoutBuilder constraints: $constraints');
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
        },
      );
    }

    if (!widget.cameraEnabled) {
      debugPrint('[LVP] build — Durum 2 (kamera kapalı)');
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

    if (widget.waitingLabel != null) {
      debugPrint('[LVP] build — Durum 3 (bekleniyor: ${widget.waitingLabel})');
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
                style: const TextStyle(color: Colors.white38, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    debugPrint(
      '[LVP] build — Durum 4 (track=null cameraEnabled=${widget.cameraEnabled})',
    );
    return const ColoredBox(color: Colors.black);
  }
}

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
    debugPrint(
      '[SafeVR] initState — trackHashCode=${widget.track.hashCode} mediaStream=${widget.track.mediaStream.id}',
    );
    _init();
  }

  Future<void> _init() async {
    debugPrint('[SafeVR] _init: RTCVideoRenderer() oluşturuluyor...');
    final r = rtc.RTCVideoRenderer();
    debugPrint('[SafeVR] _init: initialize() çağrılıyor...');
    await r.initialize();
    debugPrint(
      '[SafeVR] _init: initialize() tamamlandı — textureId=${r.textureId}',
    );
    debugPrint(
      '[SafeVR] _init: srcObject set ediliyor — streamId=${widget.track.mediaStream.id}',
    );
    r.srcObject = widget.track.mediaStream;
    debugPrint(
      '[SafeVR] _init: srcObject set edildi — renderVideo=${r.renderVideo} value=${r.value.width}×${r.value.height}',
    );
    r.onResize = () {
      debugPrint(
        '[SafeVR] onResize — ${r.value.width}×${r.value.height} aspectRatio=${r.value.aspectRatio.toStringAsFixed(4)} renderVideo=${r.renderVideo} mounted=$mounted',
      );
      if (mounted) setState(() {});
    };
    r.onFirstFrameRendered = () {
      debugPrint('[SafeVR] onFirstFrameRendered — mounted=$mounted');
    };
    if (!mounted) {
      debugPrint(
        '[SafeVR] _init: widget unmount oldu, renderer dispose ediliyor',
      );
      await r.dispose();
      return;
    }
    debugPrint('[SafeVR] _init: setState(_ready=true) çağrılıyor');
    setState(() {
      _renderer = r;
      _ready = true;
    });
    debugPrint('[SafeVR] _init: setState tamamlandı');
  }

  @override
  void didUpdateWidget(_SafeVideoRenderer old) {
    super.didUpdateWidget(old);
    debugPrint(
      '[SafeVR] didUpdateWidget — trackChanged=${old.track != widget.track}',
    );
    if (old.track != widget.track && _renderer != null) {
      debugPrint(
        '[SafeVR] didUpdateWidget: yeni track — srcObject güncelleniyor: ${widget.track.mediaStream.id}',
      );
      _renderer!.srcObject = widget.track.mediaStream;
    }
  }

  @override
  void dispose() {
    debugPrint(
      '[SafeVR] dispose() — _ready=$_ready textureId=${_renderer?.textureId}',
    );
    _renderer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || _renderer == null) {
      debugPrint(
        '[SafeVR] build — henüz hazır değil (_ready=$_ready renderer=${_renderer == null ? "null" : "ok"})',
      );
      return const ColoredBox(color: Colors.black);
    }
    final val = _renderer!.value;
    debugPrint(
      '[SafeVR] build — RTCVideoView gösteriliyor | textureId=${_renderer!.textureId} renderVideo=${_renderer!.renderVideo} value=${val.width}×${val.height} aspectRatio=${val.aspectRatio.toStringAsFixed(4)}',
    );
    return rtc.RTCVideoView(
      _renderer!,
      objectFit: rtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
      mirror: false,
    );
  }
}
