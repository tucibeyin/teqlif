import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../config/theme.dart';
import '../../../models/recording.dart';
import '../../../services/localization_service.dart';
import '../widgets/rd_formatters.dart';

class BidsSubTab extends StatelessWidget {
  final List<RecordingParticipantActivity> participants;
  final TranslationPack loc;

  const BidsSubTab({
    super.key,
    required this.participants,
    required this.loc,
  });

  @override
  Widget build(BuildContext context) {
    final bidders = participants
        .where((p) => p.bids.isNotEmpty)
        .toList()
      ..sort((a, b) => b.bidTotal.compareTo(a.bidTotal));

    if (bidders.isEmpty) {
      return Center(
        child: Text(
          loc.t('recordingNoBuyers'),
          style: TextStyle(color: AppColors.textSecondary(context)),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: bidders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final p = bidders[i];
        return _BidderCard(participant: p, rank: i + 1, loc: loc);
      },
    );
  }
}

class _BidderCard extends StatelessWidget {
  final RecordingParticipantActivity participant;
  final int rank;
  final TranslationPack loc;

  const _BidderCard({
    required this.participant,
    required this.rank,
    required this.loc,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = participant;

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
                    rdPrice(p.bidTotal, loc.lang),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: kPrimary,
                    ),
                  ),
                  Text(
                    '${p.bids.length} ${loc.t("recordingMetricBids").toLowerCase()}',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary(context),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (p.bids.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: p.bids
                  .map((b) => _BidChip(
                        auctionName: b.auctionName,
                        amount: b.amount,
                        lang: loc.lang,
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _BidChip extends StatelessWidget {
  final String auctionName;
  final double amount;
  final String lang;

  const _BidChip({
    required this.auctionName,
    required this.amount,
    required this.lang,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: kPrimary.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '${auctionName.length > 12 ? "${auctionName.substring(0, 12)}…" : auctionName} · ${rdPrice(amount, lang)}',
        style: TextStyle(
          fontSize: 11,
          color: cs.primary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
