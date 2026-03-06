import 'dart:ui';

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';

class ViewerSoldOverlay extends StatelessWidget {
  final String? soldWinnerName;
  final double? soldFinalPrice;
  final ConfettiController confettiController;
  final VoidCallback onClose;

  const ViewerSoldOverlay({
    super.key,
    required this.soldWinnerName,
    required this.soldFinalPrice,
    required this.confettiController,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            color: Colors.black.withOpacity(0.72),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: ConfettiWidget(
                    confettiController: confettiController,
                    blastDirectionality: BlastDirectionality.explosive,
                    shouldLoop: false,
                    numberOfParticles: 60,
                    maxBlastForce: 55,
                    minBlastForce: 25,
                    emissionFrequency: 0.06,
                    colors: const [
                      Colors.amber,
                      Color(0xFFFFA500),
                      Color(0xFF00B4CC),
                      Colors.white,
                      Color(0xFF22c55e),
                      Color(0xFFFF6B35),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Text('🏆', style: TextStyle(fontSize: 72)),
                const SizedBox(height: 12),
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [
                      Color(0xFFFFD700),
                      Color(0xFFFFA500),
                      Color(0xFFFFD700)
                    ],
                  ).createShader(bounds),
                  child: const Text(
                    'SATILDI!',
                    style: TextStyle(
                      fontSize: 64,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 4,
                      shadows: [
                        Shadow(color: Color(0xFFFF8C00), blurRadius: 30),
                        Shadow(color: Color(0xFFFFD700), blurRadius: 50),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'KAZANAN',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  soldWinnerName ?? 'Katılımcı',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF10b981), Color(0xFF059669)],
                    ),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x5010b981),
                        blurRadius: 24,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Text(
                    '₺${soldFinalPrice?.toStringAsFixed(0) ?? '-'}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'Bu ürün ${soldWinnerName ?? 'Katılımcı'} adlı kullanıcıya '
                    '₺${soldFinalPrice?.toStringAsFixed(0) ?? '-'}\'ye satılmıştır.',
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 14,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: onClose,
                  icon: const Icon(Icons.close, color: Colors.white),
                  label: const Text(
                    'Sohbete Dön / Kapat',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.15),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 14),
                    shape: const StadiumBorder(
                      side: BorderSide(color: Colors.white54, width: 1.5),
                    ),
                    elevation: 0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
