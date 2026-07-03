import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../services/analytics_service.dart';

class SellerReportScreen extends StatefulWidget {
  final int streamId;
  final String streamTitle;

  const SellerReportScreen({
    super.key,
    required this.streamId,
    required this.streamTitle,
  });

  @override
  State<SellerReportScreen> createState() => _SellerReportScreenState();
}

class _SellerReportScreenState extends State<SellerReportScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _report;
  bool _loading = true;
  bool _hasError = false;

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _loadReport();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadReport() async {
    final report = await AnalyticsService.getSellerReport(widget.streamId);
    if (!mounted) return;
    setState(() {
      _report = report;
      _loading = false;
      _hasError = report == null;
    });
    if (report != null) _fadeCtrl.forward();
  }

  // ── Formatters ──────────────────────────────────────────────────────────────

  String _fmtBudget(dynamic raw) {
    if (raw == null) return '—';
    final val = (raw as num).toDouble();
    if (val <= 0) return '—';
    final s = val.toInt().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return '${buf.toString()} ₺';
  }

  String _fmtDuration(int minutes, AppLocalizations l) {
    if (minutes < 1) return l.reportDurationLess;
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0) return '$h${l.reportDurationHour} $m${l.reportDurationMin}';
    return '$m ${l.reportDurationMin}';
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1E),
      body: SafeArea(
        child: _loading
            ? _buildLoading()
            : _hasError
                ? _buildError()
                : _buildReport(),
      ),
    );
  }

  Widget _buildLoading() {
    final l = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: kPrimary),
          const SizedBox(height: 16),
          Text(
            l.reportLoading,
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    final l = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, color: Color(0xFF475569), size: 52),
            const SizedBox(height: 16),
            Text(
              l.reportLoadFailed,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 15),
            ),
            const SizedBox(height: 24),
            _PrimaryButton(
              label: l.reportRetry,
              onTap: () {
                setState(() { _loading = true; _hasError = false; });
                _loadReport();
              },
            ),
            const SizedBox(height: 12),
            _SecondaryButton(
              label: l.reportGoHome,
              onTap: _goHome,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReport() {
    final l = AppLocalizations.of(context)!;
    final r = _report!;
    final uniqueViewers = r['unique_viewers'] as int? ?? 0;
    final peakViewers = r['peak_viewers'] as int? ?? 0;
    final avgBudget = r['avg_budget'];
    final hesitations = r['hesitation_count'] as int? ?? 0;
    final duration = r['duration_minutes'] as int? ?? 0;
    final swipeImpressions = r['swipe_impressions'] as int? ?? 0;
    final swipeReach = r['swipe_reach'] as int? ?? 0;
    final recommendation = r['recommendation'] as String? ?? '';
    final auctionSummary = r['auction_summary'] as Map<String, dynamic>? ?? {};
    final totalAuctions = auctionSummary['total_auctions'] as int? ?? 0;
    final successfulAuctions = auctionSummary['successful_auctions'] as int? ?? 0;
    final totalBids = auctionSummary['total_bids'] as int? ?? 0;
    final totalRevenue = (auctionSummary['total_revenue'] as num?)?.toDouble() ?? 0.0;
    final auctionItems = auctionSummary['items'] as List<dynamic>? ?? [];

    return FadeTransition(
      opacity: _fadeAnim,
      child: CustomScrollView(
        slivers: [
          // ── Header ─────────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: _Header(
              title: widget.streamTitle,
              duration: _fmtDuration(duration, l),
              badge: l.reportBadge,
              subtitle: l.reportStreamEndedDesc,
            ),
          ),

          // ── Metrik kartları ────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            sliver: SliverGrid(
              delegate: SliverChildListDelegate([
                _MetricCard(
                  icon: Icons.visibility_outlined,
                  label: l.reportMetricPeakViewers,
                  value: '$peakViewers',
                  color: const Color(0xFF6366F1),
                ),
                _MetricCard(
                  icon: Icons.people_outline_rounded,
                  label: l.reportMetricEngagedViewers,
                  value: '$uniqueViewers',
                  color: const Color(0xFF8B5CF6),
                ),
                _MetricCard(
                  icon: Icons.account_balance_wallet_outlined,
                  label: l.reportMetricAvgBudget,
                  value: _fmtBudget(avgBudget),
                  color: const Color(0xFF10B981),
                ),
                _MetricCard(
                  icon: Icons.timer_outlined,
                  label: l.reportMetricDuration,
                  value: _fmtDuration(duration, l),
                  color: const Color(0xFF3B82F6),
                ),
              ]),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.35,
              ),
            ),
          ),

          // ── Swipe Feed Erişimi (sadece veri varsa) ────────────────────────
          if (swipeImpressions > 0) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: _SectionHeader(
                  icon: Icons.swipe_rounded,
                  label: l.reportSectionSwipeFeed,
                  color: const Color(0xFF06B6D4),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              sliver: SliverGrid(
                delegate: SliverChildListDelegate([
                  _MetricCard(
                    icon: Icons.play_circle_outline_rounded,
                    label: l.reportMetricSwipeImpressions,
                    value: '$swipeImpressions',
                    color: const Color(0xFF06B6D4),
                  ),
                  _MetricCard(
                    icon: Icons.person_search_rounded,
                    label: l.reportMetricSwipeReach,
                    value: '$swipeReach',
                    color: const Color(0xFF0EA5E9),
                  ),
                ]),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1.35,
                ),
              ),
            ),
          ],

          // ── Açık Artırma Özeti (sadece auction varsa) ─────────────────────
          if (totalAuctions > 0) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: _SectionHeader(
                  icon: Icons.gavel_rounded,
                  label: l.reportSectionAuction,
                  color: const Color(0xFFF97316),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              sliver: SliverGrid(
                delegate: SliverChildListDelegate([
                  _MetricCard(
                    icon: Icons.gavel_rounded,
                    label: l.reportMetricTotalAuctions,
                    value: '$totalAuctions',
                    color: const Color(0xFFF97316),
                  ),
                  _MetricCard(
                    icon: Icons.check_circle_outline_rounded,
                    label: l.reportMetricSoldItems,
                    value: '$successfulAuctions',
                    color: const Color(0xFF22C55E),
                  ),
                  _MetricCard(
                    icon: Icons.price_change_outlined,
                    label: l.reportMetricTotalBids,
                    value: '$totalBids',
                    color: const Color(0xFF06B6D4),
                  ),
                  _MetricCard(
                    icon: Icons.payments_outlined,
                    label: l.reportMetricRevenue,
                    value: _fmtBudget(totalRevenue > 0 ? totalRevenue : null),
                    color: const Color(0xFF10B981),
                  ),
                ]),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1.35,
                ),
              ),
            ),

            // ── Ürün listesi ──────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  children: auctionItems.map<Widget>((item) {
                    final m = item as Map<String, dynamic>;
                    return _AuctionItemRow(
                      itemName: m['item_name'] as String? ?? '—',
                      startPrice: (m['start_price'] as num?)?.toDouble() ?? 0,
                      finalPrice: (m['final_price'] as num?)?.toDouble(),
                      winner: m['winner_username'] as String?,
                      bidCount: m['bid_count'] as int? ?? 0,
                      isBoughtItNow: m['is_bought_it_now'] as bool? ?? false,
                      durationMinutes: m['duration_minutes'] as int? ?? 0,
                    );
                  }).toList(),
                ),
              ),
            ),
          ],

          // ── Kararsız teklif (küçük, sadece > 0 ise) ──────────────────────
          if (hesitations > 0)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: _HesitationHint(count: hesitations, l: l),
              ),
            ),

          // ── AI Tavsiye kartı ───────────────────────────────────────────────
          if (recommendation.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: _InsightCard(text: recommendation, insightLabel: l.reportSmartInsight),
              ),
            ),

          // ── Aksiyon butonları ──────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
              child: _PrimaryButton(label: l.reportGoHome, onTap: _goHome),
            ),
          ),
        ],
      ),
    );
  }

  void _goHome() {
    Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
  }
}

// ── Header ──────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final String title;
  final String duration;
  final String badge;
  final String subtitle;
  const _Header({
    required this.title,
    required this.duration,
    required this.badge,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E1B4B), Color(0xFF0A0F1E)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: kPrimary.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: kPrimary.withValues(alpha: 0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bar_chart_rounded, color: kPrimary, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      badge,
                      style: TextStyle(
                        color: kPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                duration,
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ── Metric Card ─────────────────────────────────────────────────────────────

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.20)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 11,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Insight Card ─────────────────────────────────────────────────────────────

class _InsightCard extends StatelessWidget {
  final String text;
  final String insightLabel;
  const _InsightCard({required this.text, required this.insightLabel});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            kPrimary.withValues(alpha: 0.18),
            const Color(0xFF1E1B4B).withValues(alpha: 0.80),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kPrimary.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: kPrimary.withValues(alpha: 0.25),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.auto_awesome_rounded, color: kPrimary, size: 16),
              ),
              const SizedBox(width: 10),
              Text(
                insightLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFFCBD5E1),
              fontSize: 14,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section Header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _SectionHeader({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 14),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}

// ── Auction Item Row ──────────────────────────────────────────────────────────

class _AuctionItemRow extends StatelessWidget {
  final String itemName;
  final double startPrice;
  final double? finalPrice;
  final String? winner;
  final int bidCount;
  final bool isBoughtItNow;
  final int durationMinutes;

  const _AuctionItemRow({
    required this.itemName,
    required this.startPrice,
    required this.finalPrice,
    required this.winner,
    required this.bidCount,
    required this.isBoughtItNow,
    required this.durationMinutes,
  });

  String _fmt(double? v) {
    if (v == null || v <= 0) return '—';
    final s = v.toInt().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return '${buf.toString()} ₺';
  }

  @override
  Widget build(BuildContext context) {
    final sold = winner != null;
    final accent = sold ? const Color(0xFF22C55E) : const Color(0xFF475569);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  itemName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  sold
                      ? (isBoughtItNow
                          ? AppLocalizations.of(context)!.reportItemBuyNow
                          : AppLocalizations.of(context)!.reportItemSold)
                      : AppLocalizations.of(context)!.reportItemNotSold,
                  style: TextStyle(color: accent, fontSize: 10, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _InfoChip(label: AppLocalizations.of(context)!.reportChipStart, value: _fmt(startPrice), color: const Color(0xFF64748B)),
              const SizedBox(width: 8),
              if (sold) _InfoChip(label: AppLocalizations.of(context)!.reportChipSale, value: _fmt(finalPrice), color: const Color(0xFF22C55E)),
              const SizedBox(width: 8),
              _InfoChip(label: AppLocalizations.of(context)!.reportChipBids, value: '$bidCount', color: const Color(0xFF06B6D4)),
              const Spacer(),
              if (durationMinutes > 0)
                Text(
                  '${durationMinutes}dk',
                  style: const TextStyle(color: Color(0xFF475569), fontSize: 11),
                ),
            ],
          ),
          if (sold && winner != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.emoji_events_rounded, color: Color(0xFFFBBF24), size: 14),
                const SizedBox(width: 4),
                Text(
                  '@$winner',
                  style: const TextStyle(
                    color: Color(0xFFFBBF24),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _InfoChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF475569), fontSize: 10)),
        Text(value, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

// ── Hesitation Hint ───────────────────────────────────────────────────────────

class _HesitationHint extends StatelessWidget {
  final int count;
  final AppLocalizations l;
  const _HesitationHint({required this.count, required this.l});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.touch_app_outlined, color: Color(0xFFF59E0B), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l.reportHesitation(count),
              style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Buttons ──────────────────────────────────────────────────────────────────

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PrimaryButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: kPrimary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _SecondaryButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white70,
          side: const BorderSide(color: Color(0xFF334155)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
