import 'package:flutter/material.dart';

import '../../../models/recording.dart';
import 'activity_timeline.dart';
import 'rd_formatters.dart';
import 'stacked_avatars.dart';

class ParticipantCard extends StatelessWidget {
  final RecordingParticipantActivity participant;
  final int rank;
  final String lang;
  final double? durationSecs;
  final VoidCallback? onTap;

  const ParticipantCard({
    super.key,
    required this.participant,
    required this.rank,
    required this.lang,
    this.durationSecs,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = participant;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _rankBadge(context, rank),
                const SizedBox(width: 10),
                StackedAvatars(
                  avatarUrls: [p.avatarUrl],
                  size: 36,
                  maxVisible: 1,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.username,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (p.monetaryTotal > 0)
                        Text(
                          rdPrice(p.monetaryTotal, lang),
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
                _chipRow(context, p),
              ],
            ),
            if (p.timeline.isNotEmpty) ...[
              const SizedBox(height: 8),
              ActivityTimeline(
                actions: p.timeline,
                durationSecs: durationSecs,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _rankBadge(BuildContext context, int rank) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 24,
      child: Text(
        '$rank',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: cs.onSurfaceVariant,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _chipRow(BuildContext context, RecordingParticipantActivity p) {
    final cs = Theme.of(context).colorScheme;
    final chips = <Widget>[];

    if (p.bids.isNotEmpty) {
      chips.add(_Chip(
        icon: Icons.gavel_rounded,
        label: '${p.bids.length}',
        color: cs.primary,
      ));
    }
    if (p.orders.isNotEmpty) {
      chips.add(_Chip(
        icon: Icons.shopping_bag_rounded,
        label: '${p.orders.length}',
        color: cs.tertiary,
      ));
    }
    if (p.gifts.isNotEmpty) {
      chips.add(_Chip(
        icon: Icons.card_giftcard_rounded,
        label: rdTeqliq(p.giftTeqlik, lang),
        color: const Color(0xFFE91E63),
      ));
    }
    if (p.chats.isNotEmpty) {
      chips.add(_Chip(
        icon: Icons.chat_bubble_outline_rounded,
        label: '${p.chatCount}',
        color: cs.secondary,
      ));
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: chips,
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _Chip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
