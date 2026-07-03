import 'package:flutter/material.dart';

/// Canlı yayın odası için compact dikey Hype Meter çubuğu.
///
/// 0-30 → gri/mavi | 31-75 → turuncu | 76-100 → kırmızı + 🔥
/// Skor 0 olduğunda widget tamamen gizlenir (AnimatedOpacity ile).
class HypeMeterWidget extends StatelessWidget {
  final ValueNotifier<int> hypeScore;

  const HypeMeterWidget({super.key, required this.hypeScore});

  static const double _barHeight = 64;
  static const double _barWidth  = 10;

  Color _barColor(int score) {
    if (score <= 30) return const Color(0xFF60A5FA);
    if (score <= 75) return const Color(0xFFF97316);
    return const Color(0xFFEF4444);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: hypeScore,
      builder: (_, score, _) {
        final color    = _barColor(score);
        final fraction = (score / 100.0).clamp(0.0, 1.0);
        final isHot    = score > 75;

        return AnimatedOpacity(
          opacity: score == 0 ? 0.0 : 1.0,
          duration: const Duration(milliseconds: 400),
          child: Container(
            width: 36,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Flame emoji — sadece kırmızı bölgede
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: isHot
                      ? const Text('🔥',
                          key: ValueKey(true),
                          style: TextStyle(fontSize: 13))
                      : const SizedBox(key: ValueKey(false), height: 0),
                ),
                if (isHot) const SizedBox(height: 2),
                // Dikey çubuk
                SizedBox(
                  width: _barWidth,
                  height: _barHeight,
                  child: Stack(
                    alignment: Alignment.bottomCenter,
                    children: [
                      // Arka plan
                      Container(
                        width: _barWidth,
                        height: _barHeight,
                        decoration: BoxDecoration(
                          color: Colors.white12,
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                      // Dolgu (aşağıdan yukarıya)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeOut,
                        width: _barWidth,
                        height: _barHeight * fraction,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(5),
                          boxShadow: [
                            BoxShadow(
                              color: color.withValues(alpha: 0.55),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                // Sayısal skor
                Text(
                  '$score',
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'HYPE',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 7,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
