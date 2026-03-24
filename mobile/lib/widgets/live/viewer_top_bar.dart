import 'package:flutter/material.dart';

/// Canlı yayın izleyici ekranı — üst bilgi çubuğu.
///
/// Geri butonu, CANLI rozeti, izleyici sayacı, başlık, host
/// kullanıcı adı, isteğe bağlı MOD rozeti ve "Ayrıl" butonu
/// içerir. Tamamen stateless'tır; "Yayını Bitir" butonu
/// kasıtlı olarak dahil edilmemiştir.
class ViewerTopBar extends StatelessWidget {
  final double topPad;
  final int viewerCount;
  final String title;
  final String hostUsername;
  final bool isCoHost;
  final VoidCallback onLeave;

  const ViewerTopBar({
    super.key,
    required this.topPad,
    required this.viewerCount,
    required this.title,
    required this.hostUsername,
    required this.isCoHost,
    required this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
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
          // Geri
          GestureDetector(
            key: const Key('viewer_btn_geri'),
            onTap: onLeave,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.black38,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
          const SizedBox(width: 10),

          // CANLI rozeti
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(5),
            ),
            child: const Text(
              'CANLI',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 6),

          // İzleyici sayısı
          Container(
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
          const SizedBox(width: 10),

          // Başlık + host kullanıcı adı
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    shadows: [Shadow(blurRadius: 6, color: Colors.black)],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '@$hostUsername',
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),

          // MOD rozeti — sadece co-host olduğunda
          if (isCoHost) ...[
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF16A34A),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                '🛡 MOD',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],

          // Ayrıl
          GestureDetector(
            key: const Key('viewer_btn_ayril'),
            onTap: onLeave,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white24),
              ),
              child: const Text(
                'Ayrıl',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
