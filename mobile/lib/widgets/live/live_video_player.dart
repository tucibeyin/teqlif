import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

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
///
/// Bu widget tamamen stateless'tır; LiveKit bağlantı mantığı
/// çağıran ekranda kalmaktadır.
class LiveVideoPlayer extends StatelessWidget {
  final VideoTrack? track;
  final bool cameraEnabled;
  final GlobalKey? repaintKey;

  /// [track] null + [cameraEnabled] true olduğunda gösterilecek metin.
  /// Viewer ekranı için 'Video bekleniyor...' gibi bir değer geçilir.
  final String? waitingLabel;

  const LiveVideoPlayer({
    super.key,
    required this.track,
    required this.cameraEnabled,
    this.repaintKey,
    this.waitingLabel,
  });

  @override
  Widget build(BuildContext context) {
    // ── Durum 1: Aktif video track ──────────────────────────────────────────
    if (track != null) {
      return RepaintBoundary(
        key: repaintKey,
        child: VideoTrackRenderer(
          track!,
          fit: VideoViewFit.contain,
        ),
      );
    }

    // ── Durum 2: Kamera kasıtlı olarak kapatıldı (host) ────────────────────
    if (!cameraEnabled) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.videocam_off_rounded,
                color: Colors.white24,
                size: 60,
              ),
              SizedBox(height: 12),
              Text(
                'Kamera Kapalı',
                style: TextStyle(
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
    if (waitingLabel != null) {
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
                waitingLabel!,
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
    return const ColoredBox(color: Colors.black);
  }
}
