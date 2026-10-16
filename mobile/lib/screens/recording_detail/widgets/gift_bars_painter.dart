import 'package:flutter/material.dart';

import '../../../models/recording.dart';

class GiftBarsChart extends StatelessWidget {
  final RecordingGifts gifts;
  final int topN;

  const GiftBarsChart({
    super.key,
    required this.gifts,
    this.topN = 5,
  });

  @override
  Widget build(BuildContext context) {
    if (gifts.events.isEmpty) return const SizedBox.shrink();

    final Map<String, int> totals = {};
    for (final e in gifts.events) {
      totals[e.giftName] = (totals[e.giftName] ?? 0) + e.costTeqlik;
    }
    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final visible = sorted.take(topN).toList();
    if (visible.isEmpty) return const SizedBox.shrink();

    final maxVal = visible.first.value.toDouble();

    return Column(
      children: visible
          .map((e) => _GiftBar(
                name: e.key,
                value: e.value,
                maxValue: maxVal,
              ))
          .toList(),
    );
  }
}

class _GiftBar extends StatelessWidget {
  final String name;
  final int value;
  final double maxValue;

  const _GiftBar({
    required this.name,
    required this.value,
    required this.maxValue,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fraction = maxValue > 0 ? value / maxValue : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              name,
              style: TextStyle(fontSize: 12, color: cs.onSurface),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              return Stack(
                children: [
                  Container(
                    height: 14,
                    decoration: BoxDecoration(
                      color: cs.outlineVariant.withAlpha(60),
                      borderRadius: BorderRadius.circular(7),
                    ),
                  ),
                  Container(
                    height: 14,
                    width: constraints.maxWidth * fraction,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE91E63).withAlpha(200),
                      borderRadius: BorderRadius.circular(7),
                    ),
                  ),
                ],
              );
            }),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 48,
            child: Text(
              '$value⚡',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
