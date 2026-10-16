import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../models/recording.dart';
import '../../../services/localization_service.dart';

class ShoppingSubTab extends StatelessWidget {
  final List<RecordingParticipantActivity> participants;
  final TranslationPack loc;

  const ShoppingSubTab({
    super.key,
    required this.participants,
    required this.loc,
  });

  @override
  Widget build(BuildContext context) {
    final buyers = participants
        .where((p) => p.orders.isNotEmpty)
        .toList()
      ..sort((a, b) => b.orderTotal.compareTo(a.orderTotal));

    if (buyers.isEmpty) {
      return Center(
        child: Text(
          loc.t('recordingNoBuyers'),
          style: TextStyle(color: AppColors.textSecondary(context)),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: buyers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _BuyerCard(
        participant: buyers[i],
        rank: i + 1,
        loc: loc,
      ),
    );
  }
}

class _BuyerCard extends StatelessWidget {
  final RecordingParticipantActivity participant;
  final int rank;
  final TranslationPack loc;

  const _BuyerCard({
    required this.participant,
    required this.rank,
    required this.loc,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = participant;
    const purple = Color(0xFF6366F1);

    return Container(
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
              SizedBox(
                width: 24,
                child: Text(
                  '$rank',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textTertiary(context),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                radius: 16,
                backgroundImage: p.avatarUrl != null
                    ? NetworkImage(p.avatarUrl!)
                    : null,
                child: p.avatarUrl == null
                    ? const Icon(Icons.person, size: 16)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  p.username,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '₺${p.orderTotal.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: purple,
                    ),
                  ),
                  Text(
                    '${p.orders.length} alım',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary(context),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (p.orders.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...p.orders.map(
              (o) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    const SizedBox(width: 32),
                    const Icon(Icons.shopping_bag_outlined,
                        size: 13, color: purple),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        o.itemName,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary(context),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '×${o.quantity} · ₺${o.unitPrice.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: purple,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
