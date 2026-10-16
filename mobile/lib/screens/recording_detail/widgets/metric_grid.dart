import 'package:flutter/material.dart';

class MetricTile {
  final String label;
  final String value;
  final IconData? icon;
  final Color? valueColor;

  const MetricTile({
    required this.label,
    required this.value,
    this.icon,
    this.valueColor,
  });
}

class MetricGrid extends StatelessWidget {
  final List<MetricTile> tiles;
  final int crossAxisCount;

  const MetricGrid({
    super.key,
    required this.tiles,
    this.crossAxisCount = 2,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: tiles.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisExtent: 80,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemBuilder: (context, i) => _MetricCard(tile: tiles[i]),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final MetricTile tile;
  const _MetricCard({required this.tile});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              if (tile.icon != null) ...[
                Icon(tile.icon, size: 14, color: cs.onSurfaceVariant),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  tile.label,
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                    letterSpacing: 0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Text(
            tile.value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: tile.valueColor ?? cs.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
