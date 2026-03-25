import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';

/// Canlı yayın host ekranı — üst bilgi çubuğu.
///
/// CANLI rozeti, izleyici sayacı (tıklanabilir), başlık ve
/// "Bitir" butonu içerir. Tüm etkileşimler callback ile üst
/// widget'a iletilir; bu widget tamamen stateless'tır.
class HostTopBar extends StatelessWidget {
  final double topPad;
  final int viewerCount;
  final String title;
  final VoidCallback onViewersTap;
  final VoidCallback onEndStream;

  const HostTopBar({
    super.key,
    required this.topPad,
    required this.viewerCount,
    required this.title,
    required this.onViewersTap,
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
