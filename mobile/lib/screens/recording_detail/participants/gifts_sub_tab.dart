import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../models/recording.dart';
import '../../../services/localization_service.dart';

class GiftsSubTab extends StatelessWidget {
  final List<RecordingParticipantActivity> participants;
  final TranslationPack loc;

  const GiftsSubTab({
    super.key,
    required this.participants,
    required this.loc,
  });

  @override
  Widget build(BuildContext context) {
    final gifters = participants
        .where((p) => p.gifts.isNotEmpty)
        .toList()
      ..sort((a, b) => b.giftTeqlik.compareTo(a.giftTeqlik));

    if (gifters.isEmpty) {
      return Center(
        child: Text(
          loc.t('recordingNoBuyers'),
          style: TextStyle(color: AppColors.textSecondary(context)),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: gifters.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _GifterCard(
        participant: gifters[i],
        rank: i + 1,
        loc: loc,
      ),
    );
  }
}

class _GifterCard extends StatelessWidget {
  final RecordingParticipantActivity participant;
  final int rank;
  final TranslationPack loc;

  const _GifterCard({
    required this.participant,
    required this.rank,
    required this.loc,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = participant;
    const orange = Color(0xFFF97316);
    const pink = Color(0xFFE91E63);

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
                    '${p.giftTeqlik}⚡',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: orange,
                    ),
                  ),
                  Text(
                    '${p.gifts.length} ${loc.t("recordingMetricGifts").toLowerCase()}',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary(context),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (p.gifts.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: p.gifts
                  .map((g) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: pink.withAlpha(20),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${g.giftName} · ${g.costTeqlik}⚡',
                          style: const TextStyle(
                            fontSize: 11,
                            color: pink,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}
