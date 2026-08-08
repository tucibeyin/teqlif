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
    _syncRenderer();
  }

  @override
  void didUpdateWidget(LiveVideoPlayer old) {
    super.didUpdateWidget(old);
    if (old.track != widget.track) _syncRenderer();
  }

  void _syncRenderer() {
    if (widget.track == null) {
      _cachedRenderer = null;
      _cachedTrack = null;
    } else if (widget.track != _cachedTrack) {
      _cachedTrack = widget.track;
      _cachedRenderer = _SafeVideoRenderer(track: widget.track!);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.track != null && _cachedRenderer != null) {
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
                style: const TextStyle(color: Colors.white38, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

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
    _init();
  }

  Future<void> _init() async {
    final r = rtc.RTCVideoRenderer();
    await r.initialize();
    r.srcObject = widget.track.mediaStream;
    r.onResize = () {
      if (mounted) setState(() {});
    };
    if (!mounted) {
      await r.dispose();
      return;
    }
    setState(() {
      _renderer = r;
      _ready = true;
    });
  }

  @override
  void didUpdateWidget(_SafeVideoRenderer old) {
    super.didUpdateWidget(old);
    if (old.track != widget.track && _renderer != null) {
      _renderer!.srcObject = widget.track.mediaStream;
    }
  }

  @override
  void dispose() {
    _renderer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || _renderer == null)
      return const ColoredBox(color: Colors.black);
    return rtc.RTCVideoView(
      _renderer!,
      objectFit: rtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
      mirror: false,
    );
  }
}
