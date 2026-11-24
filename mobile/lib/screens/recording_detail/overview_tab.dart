import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../config/theme.dart';
import '../../core/user_tier.dart';
import '../../models/recording.dart';
import '../../screens/subscription_plans_screen.dart';
import '../../services/category_service.dart';
import '../../services/localization_service.dart';
import 'widgets/metric_grid.dart';
import 'widgets/podium_widget.dart';
import 'widgets/rd_formatters.dart';
import 'widgets/stacked_avatars.dart';

class OverviewTab extends StatelessWidget {
  final RecordingDetail detail;
  final List<RecordingParticipantActivity> participants;
  final TranslationPack loc;

  const OverviewTab({
    super.key,
    required this.detail,
    required this.participants,
    required this.loc,
  });

  @override
  Widget build(BuildContext context) {
    final s = detail.stream;
    final m = detail.metrics;

    final categoryLabel = s.category != null
        ? CategoryService.localizedLabelFor(loc, s.category!)
        : null;

    final top3 = participants.take(3).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        // ── Stream başlığı ──────────────────────────────────────────────
        Text(
          s.title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary(context),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            if (s.startedAt != null) ...[
              Icon(Icons.calendar_today_outlined,
                  size: 13, color: AppColors.textTertiary(context)),
              const SizedBox(width: 4),
              Text(
                _formatDate(s.startedAt!),
                style: TextStyle(fontSize: 12, color: AppColors.textTertiary(context)),
              ),
            ],
            if (s.startedAt != null && s.endedAt != null) ...[
              const SizedBox(width: 12),
              Icon(Icons.timer_outlined,
                  size: 13, color: AppColors.textTertiary(context)),
              const SizedBox(width: 4),
              Text(
                _formatDuration(s.startedAt!, s.endedAt!),
                style: TextStyle(fontSize: 12, color: AppColors.textTertiary(context)),
              ),
            ],
          ],
        ),

        if (categoryLabel != null) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            children: [
              _CategoryBadge(label: categoryLabel),
              if (s.subcategory != null)
                _CategoryBadge(
                  label: loc.tOr('subcat_${s.subcategory}', s.subcategory!),
                  secondary: true,
                ),
            ],
          ),
        ],

        const SizedBox(height: 16),

        // ── Kazanç kartı ────────────────────────────────────────────────
        _EarningsCard(metrics: m, loc: loc),
        const SizedBox(height: 10),

        // ── Metrik grid ─────────────────────────────────────────────────
        MetricGrid(
          tiles: [
            MetricTile(
              label: loc.t('recordingMetricViewers'),
              value: s.peakViewerCount != null ? '${s.peakViewerCount}' : '—',
              icon: Icons.people_outline_rounded,
            ),
            MetricTile(
              label: loc.t('recordingMetricBids'),
              value: '${m.totalBids}',
              icon: Icons.gavel_rounded,
            ),
            MetricTile(
              label: loc.t('recordingDetailAuctions'),
              value: '${detail.auctions.length}',
              icon: Icons.storefront_outlined,
            ),
            MetricTile(
              label: loc.t('recordingDetailDirectSales'),
              value: '${detail.directSales.length}',
              icon: Icons.shopping_bag_outlined,
            ),
            MetricTile(
              label: loc.t('recordingMetricGifts'),
              value: rdTeqliq(detail.gifts.totalTeqlik, loc.lang),
              icon: Icons.card_giftcard_outlined,
              valueColor: const Color(0xFFF97316),
            ),
          ],
        ),

        // ── Podyum ──────────────────────────────────────────────────────
        if (top3.isNotEmpty) ...[
          const SizedBox(height: 24),
          PodiumWidget(
            participants: top3,
            title: loc.t('recordingPodiumTitle'),
          ),
        ],

        // ── En büyük destekçi ────────────────────────────────────────────
        if (participants.isNotEmpty) ...[
          const SizedBox(height: 24),
          _TopSupporterCard(
            participant: participants.first,
            label: loc.t('recordingTopSupporterLabel'),
            lang: loc.lang,
          ),
        ],

        // ── Tüm katılımcı avatarları ─────────────────────────────────────
        if (participants.length > 3) ...[
          const SizedBox(height: 20),
          Row(
            children: [
              StackedAvatars(
                avatarUrls: participants.map((p) => p.avatarUrl).toList(),
                size: 28,
                maxVisible: 8,
              ),
              const SizedBox(width: 10),
              Text(
                '${participants.length} ${loc.t("recordingNoBuyers").split(" ").last}',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textTertiary(context),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  String _formatDate(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    return '$d.$mo.${dt.year}';
  }

  String _formatDuration(DateTime start, DateTime end) {
    final diff = end.difference(start);
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    return h > 0 ? '${h}s ${m}dk' : '${m}dk';
  }
}

class _EarningsCard extends StatelessWidget {
  final RecordingMetrics metrics;
  final TranslationPack loc;

  const _EarningsCard({required this.metrics, required this.loc});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rate = metrics.commissionRate;
    final pct = (rate * 100).round();

    final fomoNextTier = _fomoNextTier(rate);
    final fomoSavings = fomoNextTier != null
        ? metrics.totalRevenue * (fomoNextTier.$2 - rate)
        : null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined,
                  size: 14, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  loc.tOr('recordingNetEarnings', 'Net Kazanç'),
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              _CommissionBadge(pct: pct, rate: rate),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            rdPrice(metrics.netEarnings, loc.lang),
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF16A34A),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${loc.tOr('recordingGrossRevenue', 'Brüt Gelir')}: ${rdPrice(metrics.totalRevenue, loc.lang)}',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          if (fomoNextTier != null && fomoSavings != null && fomoSavings > 0) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => SubscriptionPlansScreen.show(
                context,
                initialTier: fomoNextTier.$1,
              ),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: kPrimary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        loc
                            .tOr(
                              'recordingFomoLine',
                              '{tier}\'a geçseydiniz {amount} daha kazanırdınız',
                            )
                            .replaceAll('{tier}', fomoNextTier.$1 == UserTier.pro
                                ? 'PRO'
                                : fomoNextTier.$1 == UserTier.proPlus
                                    ? 'PRO+'
                                    : 'PREMIUM')
                            .replaceAll('{amount}', rdPrice(fomoSavings, loc.lang)),
                        style: TextStyle(
                          fontSize: 12,
                          color: kPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_forward_rounded, size: 14, color: kPrimary),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Returns (nextTierString, nextRate) or null if already PREMIUM.
  (String, double)? _fomoNextTier(double rate) {
    if (rate < 0.75) return (UserTier.pro, 0.75);
    if (rate < 0.90) return (UserTier.proPlus, 0.90);
    if (rate < 1.00) return (UserTier.premium, 1.00);
    return null;
  }
}

class _CommissionBadge extends StatelessWidget {
  final int pct;
  final double rate;

  const _CommissionBadge({required this.pct, required this.rate});

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    if (rate >= 1.0) {
      bg = const Color(0xFFF59E0B);
      fg = Colors.white;
    } else if (rate >= 0.9) {
      bg = const Color(0xFF9333EA);
      fg = Colors.white;
    } else if (rate >= 0.75) {
      bg = const Color(0xFF6366F1);
      fg = Colors.white;
    } else {
      bg = Theme.of(context).colorScheme.surfaceContainerHigh;
      fg = Theme.of(context).colorScheme.onSurfaceVariant;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$pct% kom.',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}

class _TopSupporterCard extends StatelessWidget {
  final RecordingParticipantActivity participant;
  final String label;
  final String lang;

  const _TopSupporterCard({
    required this.participant,
    required this.label,
    required this.lang,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = participant;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            kPrimary.withAlpha(30),
            kPrimary.withAlpha(10),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kPrimary.withAlpha(60)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFFFD700), width: 2),
              color: cs.surfaceContainerHighest,
            ),
            clipBehavior: Clip.antiAlias,
            child: p.avatarUrl != null
                ? Image.network(p.avatarUrl!, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.person, size: 24))
                : const Icon(Icons.person, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary(context),
                    letterSpacing: 0.3,
                  ),
                ),
                Text(
                  p.username,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary(context),
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                rdPrice(p.monetaryTotal, lang),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: kPrimary,
                ),
              ),
              if (p.giftTeqlik > 0)
                Text(
                  rdTeqliq(p.giftTeqlik, lang),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFF97316),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CategoryBadge extends StatelessWidget {
  final String label;
  final bool secondary;

  const _CategoryBadge({required this.label, this.secondary = false});

  @override
  Widget build(BuildContext context) {
    final color = secondary ? AppColors.textTertiary(context) : kPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(64)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: secondary ? FontWeight.normal : FontWeight.w600,
        ),
      ),
    );
  }
}
