import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ViewerFinalizationOverlay extends StatelessWidget {
  final bool show;
  final String? winnerName;
  final double? amount;

  const ViewerFinalizationOverlay({
    super.key,
    required this.show,
    this.winnerName,
    this.amount,
  });

  String _formatSenderName(String? name) {
    if (name == null || name.isEmpty) return 'Katılımcı';
    final parts = name.trim().split(' ');
    if (parts.length == 1) return parts[0];
    final firstName = parts[0];
    final otherParts = parts
        .skip(1)
        .map((p) => p.isNotEmpty ? '${p[0]}.' : '')
        .where((s) => s.isNotEmpty)
        .join(' ');
    return '$firstName $otherParts';
  }

  @override
  Widget build(BuildContext context) {
    if (!show) return const SizedBox.shrink();

    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.7),
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.5, end: 1.0),
            duration: const Duration(milliseconds: 600),
            curve: Curves.elasticOut,
            builder: (context, scale, child) {
              return Transform.scale(
                scale: scale,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.celebration,
                        color: Colors.amber, size: 80),
                    const SizedBox(height: 16),
                    const Text(
                      'SATILDI!',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                        shadows: [Shadow(blurRadius: 10, color: Colors.amber)],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Tebrikler ${_formatSenderName(winnerName)}!',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (amount != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        NumberFormat.currency(
                                locale: 'tr_TR', symbol: '₺')
                            .format(amount),
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
