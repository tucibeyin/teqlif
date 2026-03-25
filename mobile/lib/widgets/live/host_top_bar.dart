import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';

/// Canlı yayın host ekranı — üst bilgi çubuğu.
///
/// CANLI rozeti, izleyici sayacı (tıklanabilir), başlık,
/// mikrofon/kamera/çevirme kontrolleri ve "Bitir" butonu içerir.
/// Tüm etkileşimler callback ile üst widget'a iletilir; bu widget
/// tamamen stateless'tır.
class HostTopBar extends StatelessWidget {
  final double topPad;
  final int viewerCount;
  final String title;
  final bool micEnabled;
  final bool cameraEnabled;
  final VoidCallback onViewersTap;
  final VoidCallback onToggleMic;
  final VoidCallback onToggleCamera;
  final VoidCallback onSwitchCamera;
  final VoidCallback onEndStream;

  const HostTopBar({
    super.key,
    required this.topPad,
    required this.viewerCount,
    required this.title,
    required this.micEnabled,
    required this.cameraEnabled,
    required this.onViewersTap,
    required this.onToggleMic,
    required this.onToggleCamera,
    required this.onSwitchCamera,
    required this.onEndStream,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Container(
      padding: EdgeInsets.only(
        top: topPad + 14,
        left: 16,
        right: 16,
        bottom: 32,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xBB000000), Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          // CANLI rozeti
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              l.liveBadgeLabel,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 6),

          // İzleyici sayısı (tıklanabilir)
          GestureDetector(
            onTap: onViewersTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '👁 $viewerCount',
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Başlık
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
                shadows: [Shadow(blurRadius: 6, color: Colors.black)],
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),

          // Mikrofon toggle
          _TopCtrlBtn(
            key: const Key('host_btn_mikrofon_toggle'),
            icon: micEnabled ? Icons.mic_rounded : Icons.mic_off_rounded,
            active: micEnabled,
            onTap: onToggleMic,
          ),
          const SizedBox(width: 6),

          // Kamera toggle
          _TopCtrlBtn(
            key: const Key('host_btn_kamera_toggle'),
            icon: cameraEnabled ? Icons.videocam_rounded : Icons.videocam_off_rounded,
            active: cameraEnabled,
            onTap: onToggleCamera,
          ),
          const SizedBox(width: 6),

          // Kamera değiştir
          _TopCtrlBtn(
            key: const Key('host_btn_kamera_cevir'),
            icon: Icons.flip_camera_ios_rounded,
            active: true,
            onTap: onSwitchCamera,
          ),
          const SizedBox(width: 10),

          // Yayını Bitir
          GestureDetector(
            key: const Key('host_btn_yayin_bitir'),
            onTap: onEndStream,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.85),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                l.liveEndStreamBtn,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Üst bardaki küçük dairesel kontrol butonu.
class _TopCtrlBtn extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _TopCtrlBtn({
    super.key,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: active ? Colors.black54 : Colors.red.withOpacity(0.75),
          shape: BoxShape.circle,
          border: Border.all(
            color: active ? Colors.white30 : Colors.transparent,
          ),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}
