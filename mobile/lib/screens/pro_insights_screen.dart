import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../config/theme.dart';
import '../l10n/app_localizations.dart';
import '../services/analytics_service.dart';

class ProInsightsScreen extends StatefulWidget {
  const ProInsightsScreen({super.key});

  @override
  State<ProInsightsScreen> createState() => _ProInsightsScreenState();
}

class _ProInsightsScreenState extends State<ProInsightsScreen> {
  Map<String, dynamic>? _data;
  Map<String, dynamic>? _metrics;
  bool _loading = true;
  bool _hasError = false;
  final Map<String, bool> _showAll = {};

  static const int _kMaxVisible = 5;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _hasError = false; });
    final results = await Future.wait([
      AnalyticsService.getProInsights(),
      AnalyticsService.getProMetrics(),
    ]);
    if (mounted) {
      setState(() {
        _data = results[0];
        _metrics = results[1];
        _loading = false;
        _hasError = results[0] == null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        backgroundColor: AppColors.bg(context),
        elevation: 0,
        title: Text(l.proAnalyticsTitle, style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _hasError
              ? _buildError(l)
              : RefreshIndicator(onRefresh: _load, child: _buildBody(l)),
    );
  }

  Widget _buildError(AppLocalizations l) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off_outlined, size: 48, color: AppColors.textSecondary(context)),
          const SizedBox(height: 12),
          Text(l.proLoadFailed, style: TextStyle(color: AppColors.textSecondary(context))),
          const SizedBox(height: 16),
          FilledButton(onPressed: _load, child: Text(l.btnRetry)),
        ],
      ),
    );
  }

  Widget _buildBody(AppLocalizations l) {
    final kpis        = (_data?['kpis']        as Map<String, dynamic>?) ?? {};
    final funnel      = (_data?['funnel']       as Map<String, dynamic>?) ?? {};
    final hotLeads    = (_data?['hot_leads']    as List?)?.cast<Map<String, dynamic>>() ?? [];
    final priceIntel  = (_data?['price_intel']  as List?)?.cast<Map<String, dynamic>>() ?? [];
    final streamStats = (_data?['stream_stats'] as Map<String, dynamic>?) ?? {};
    final peakHours   = (_data?['peak_hours']   as List?)?.cast<Map<String, dynamic>>() ?? [];
    final tips        = (_data?['tips']         as List?)?.cast<Map<String, dynamic>>() ?? [];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
      children: [
        _SectionLabel(l.proSectionOverview),
        _KpiGrid(kpis: kpis, l: l),
        const SizedBox(height: 20),

        _SectionLabel(l.proSectionFunnel),
        _FunnelCard(funnel: funnel, l: l),
        const SizedBox(height: 20),

        if (tips.isNotEmpty) ...[
          _SectionLabel(l.proSectionTips),
          ...tips.map((t) => _TipCard(tip: t)),
          const SizedBox(height: 20),
        ],

        if (hotLeads.isNotEmpty) ...[
          _SectionLabel(l.proSectionHotLeads),
          _SubLabel(l.proHotLeadsDesc),
          ..._limited('hotLeads', hotLeads).map((lead) => _HotLeadRow(lead: lead, l: l)),
          _ShowMoreBtn(
            total: hotLeads.length,
            visible: _visibleCount('hotLeads', hotLeads.length),
            sectionKey: 'hotLeads',
            showAll: _showAll['hotLeads'] ?? false,
            onToggle: () => setState(() => _showAll['hotLeads'] = !(_showAll['hotLeads'] ?? false)),
            l: l,
          ),
          const SizedBox(height: 20),
        ],

        if (priceIntel.isNotEmpty) ...[
          _SectionLabel(l.proSectionPriceIntel),
          _SubLabel(l.proPriceIntelDesc),
          ..._limited('priceIntel', priceIntel).map((p) => _PriceIntelRow(item: p, l: l)),
          _ShowMoreBtn(
            total: priceIntel.length,
            visible: _visibleCount('priceIntel', priceIntel.length),
            sectionKey: 'priceIntel',
            showAll: _showAll['priceIntel'] ?? false,
            onToggle: () => setState(() => _showAll['priceIntel'] = !(_showAll['priceIntel'] ?? false)),
            l: l,
          ),
          const SizedBox(height: 20),
        ],

        _SectionLabel(l.proSectionStreamPerf),
        _StreamStatsCard(stats: streamStats, l: l, showAll: _showAll['streams'] ?? false,
          onToggleAll: () => setState(() => _showAll['streams'] = !(_showAll['streams'] ?? false))),
        const SizedBox(height: 20),

        if (peakHours.isNotEmpty) ...[
          _SectionLabel(l.proSectionPeakHours),
          _SubLabel(l.proPeakHoursDesc),
          ..._buildPeakBars(_limited('peakHours', peakHours), l),
          _ShowMoreBtn(
            total: peakHours.length,
            visible: _visibleCount('peakHours', peakHours.length),
            sectionKey: 'peakHours',
            showAll: _showAll['peakHours'] ?? false,
            onToggle: () => setState(() => _showAll['peakHours'] = !(_showAll['peakHours'] ?? false)),
            l: l,
          ),
          const SizedBox(height: 20),
        ],

        if (_metrics != null) ...[
          _SectionLabel('AI Metrikler'),
          _ProMetricsCard(metrics: _metrics!, l: l),
          const SizedBox(height: 20),
        ],
      ],
    );
  }

  List<T> _limited<T>(String key, List<T> items) {
    if (_showAll[key] == true) return items;
    return items.take(_kMaxVisible).toList();
  }

  int _visibleCount(String key, int total) =>
      _showAll[key] == true ? total : total.clamp(0, _kMaxVisible);

  List<Widget> _buildPeakBars(List<Map<String, dynamic>> hours, AppLocalizations l) {
    final maxCount = hours.map((h) => (h['count'] as int? ?? 0)).reduce((a, b) => a > b ? a : b);
    return hours.asMap().entries.map((e) {
      final i = e.key;
      final h = e.value;
      final count = h['count'] as int? ?? 0;
      final ratio = maxCount > 0 ? count / maxCount : 0.0;
      return _PeakHourBar(label: h['label'] as String, count: count, ratio: ratio, rank: i + 1, l: l);
    }).toList();
  }
}

// ── Bölüm Başlıkları ─────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text, style: TextStyle(
        fontSize: 16, fontWeight: FontWeight.w800,
        color: AppColors.textPrimary(context),
      )),
    );
  }
}

class _SubLabel extends StatelessWidget {
  final String text;
  const _SubLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text, style: TextStyle(
        fontSize: 12, color: AppColors.textSecondary(context),
      )),
    );
  }
}

// ── KPI Grid ─────────────────────────────────────────────────────────────────

class _KpiGrid extends StatelessWidget {
  final Map<String, dynamic> kpis;
  final AppLocalizations l;
  const _KpiGrid({required this.kpis, required this.l});

  @override
  Widget build(BuildContext context) {
    final rev30 = (kpis['revenue_30d'] as num?)?.toDouble() ?? 0;
    final revGrowth = (kpis['revenue_growth_pct'] as num?)?.toDouble();
    final sales30 = kpis['sales_30d'] as int? ?? 0;
    final bids30 = kpis['bids_30d'] as int? ?? 0;
    final activeL = kpis['active_listings'] as int? ?? 0;
    final totalRev = (kpis['total_revenue'] as num?)?.toDouble() ?? 0;

    String growthStr = '';
    if (revGrowth != null) {
      growthStr = '${revGrowth >= 0 ? '+' : ''}${revGrowth.toStringAsFixed(1)}%';
    }

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.5,
      children: [
        _KpiCard(
          icon: '💰', label: l.proKpiRevenue30d,
          value: '${_fmt(rev30)} ₺',
          badge: growthStr,
          badgeColor: (revGrowth ?? 0) >= 0 ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
          gradient: const [Color(0xFF0F766E), Color(0xFF0D9488)],
        ),
        _KpiCard(
          icon: '🛍', label: l.proKpiSales,
          value: '$sales30 ${l.proKpiItemUnit}',
          badge: l.proKpiLast30d,
          badgeColor: const Color(0xFF3B82F6),
          gradient: const [Color(0xFF1D4ED8), Color(0xFF3B82F6)],
        ),
        _KpiCard(
          icon: '🔨', label: l.proKpiBids,
          value: '$bids30 ${l.proKpiBidUnit}',
          badge: l.proKpiLast30d,
          badgeColor: const Color(0xFFF59E0B),
          gradient: const [Color(0xFFB45309), Color(0xFFF59E0B)],
        ),
        _KpiCard(
          icon: '📦', label: l.proKpiActiveListings,
          value: '$activeL ${l.proKpiListingUnit}',
          badge: '${_fmt(totalRev)} ₺ ${l.proKpiTotalUnit}',
          badgeColor: const Color(0xFF8B5CF6),
          gradient: const [Color(0xFF6D28D9), Color(0xFF8B5CF6)],
        ),
      ],
    );
  }

  static String _fmt(double v) {
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}B';
    return v.toStringAsFixed(0);
  }
}

class _KpiCard extends StatelessWidget {
  final String icon, label, value, badge;
  final Color badgeColor;
  final List<Color> gradient;

  const _KpiCard({
    required this.icon, required this.label, required this.value,
    required this.badge, required this.badgeColor, required this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: gradient.last.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 18)),
              const Spacer(),
              if (badge.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(badge, style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(fontSize: 11, color: Colors.white70)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Dönüşüm Hunisi ──────────────────────────────────────────────────────────

class _FunnelCard extends StatelessWidget {
  final Map<String, dynamic> funnel;
  final AppLocalizations l;
  const _FunnelCard({required this.funnel, required this.l});

  @override
  Widget build(BuildContext context) {
    final cardBg = AppColors.card(context);
    final views = funnel['views'] as int? ?? 0;
    final hesitations = funnel['hesitations'] as int? ?? 0;
    final bids = funnel['bids'] as int? ?? 0;
    final sales = funnel['sales'] as int? ?? 0;
    final v2b = (funnel['view_to_bid_pct'] as num?)?.toDouble() ?? 0;
    final b2s = (funnel['bid_to_sale_pct'] as num?)?.toDouble() ?? 0;
    final maxVal = [views, hesitations, bids, sales].reduce((a, b) => a > b ? a : b).toDouble();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          _FunnelRow(label: l.proFunnelViews, count: views, maxVal: maxVal, color: const Color(0xFF3B82F6)),
          const SizedBox(height: 8),
          _FunnelRow(label: l.proFunnelHesitation, count: hesitations, maxVal: maxVal, color: const Color(0xFFF59E0B)),
          const SizedBox(height: 8),
          _FunnelRow(label: l.proFunnelBid, count: bids, maxVal: maxVal, color: const Color(0xFF8B5CF6)),
          const SizedBox(height: 8),
          _FunnelRow(label: l.proFunnelSale, count: sales, maxVal: maxVal, color: const Color(0xFF22C55E)),
          Divider(color: AppColors.border(context), height: 24),
          Row(
            children: [
              _RateBadge(label: l.proFunnelViewToBid, value: '$v2b%',
                  color: v2b >= 5 ? const Color(0xFF22C55E) : const Color(0xFFF59E0B)),
              const SizedBox(width: 12),
              _RateBadge(label: l.proFunnelBidToSale, value: '$b2s%',
                  color: b2s >= 30 ? const Color(0xFF22C55E) : const Color(0xFFEF4444)),
            ],
          ),
        ],
      ),
    );
  }
}

class _FunnelRow extends StatelessWidget {
  final String label;
  final int count;
  final double maxVal;
  final Color color;
  const _FunnelRow({required this.label, required this.count, required this.maxVal, required this.color});

  @override
  Widget build(BuildContext context) {
    final ratio = maxVal > 0 ? count / maxVal : 0.0;
    return Row(
      children: [
        SizedBox(width: 180, child: Text(label, style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context)))),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio, minHeight: 8,
              backgroundColor: AppColors.border(context),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(width: 36, child: Text('$count', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary(context)), textAlign: TextAlign.right)),
      ],
    );
  }
}

class _RateBadge extends StatelessWidget {
  final String label, value;
  final Color color;
  const _RateBadge({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
            Text(label, style: TextStyle(fontSize: 10, color: AppColors.textSecondary(context))),
          ],
        ),
      ),
    );
  }
}

// ── Akıllı Öneri Kartı ───────────────────────────────────────────────────────

class _TipCard extends StatelessWidget {
  final Map<String, dynamic> tip;
  const _TipCard({required this.tip});

  @override
  Widget build(BuildContext context) {
    final typeColors = {
      'price': const Color(0xFFEF4444), 'price_up': const Color(0xFF22C55E),
      'lead': const Color(0xFFF59E0B), 'stream': const Color(0xFF3B82F6),
      'listing_quality': const Color(0xFF8B5CF6), 'general': kPrimary,
    };
    final color = typeColors[tip['type'] as String? ?? 'general'] ?? kPrimary;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Center(child: Text(tip['icon'] as String? ?? '💡', style: const TextStyle(fontSize: 18))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tip['title'] as String? ?? '', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
                const SizedBox(height: 4),
                Text(tip['body'] as String? ?? '', style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context), height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sıcak Talep ─────────────────────────────────────────────────────────────

class _HotLeadRow extends StatelessWidget {
  final Map<String, dynamic> lead;
  final AppLocalizations l;
  const _HotLeadRow({required this.lead, required this.l});

  @override
  Widget build(BuildContext context) {
    final views = lead['views_30d'] as int? ?? 0;
    final hes   = lead['hesitations_30d'] as int? ?? 0;
    final heat  = lead['heat_score'] as int? ?? 0;
    final price = (lead['price'] as num?)?.toDouble();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(12),
        border: heat > 10 ? Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.5)) : null,
      ),
      child: Row(
        children: [
          Container(
            width: 6, height: 40,
            decoration: BoxDecoration(
              color: heat > 15 ? const Color(0xFFEF4444) : heat > 5 ? const Color(0xFFF59E0B) : const Color(0xFF22C55E),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(lead['title'] as String? ?? '', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary(context)), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text('${lead['category']}  •  ${price != null ? '${price.toStringAsFixed(0)} ₺' : '—'}',
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary(context))),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _Chip(l.hotLeadViewed(views), const Color(0xFF3B82F6)),
              const SizedBox(height: 4),
              _Chip(l.hotLeadHesitated(hes), const Color(0xFFF59E0B)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

// ── Fiyat Zekası ─────────────────────────────────────────────────────────────

class _PriceIntelRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final AppLocalizations l;
  const _PriceIntelRow({required this.item, required this.l});

  @override
  Widget build(BuildContext context) {
    final yourPrice  = (item['your_price'] as num?)?.toDouble() ?? 0;
    final marketAvg  = (item['market_avg'] as num?)?.toDouble() ?? 0;
    final diffPct    = (item['diff_pct'] as num?)?.toDouble() ?? 0;
    final signal     = item['signal'] as String? ?? 'uygun';

    final sigColor = signal == 'pahalı' ? const Color(0xFFEF4444)
        : signal == 'ucuz' ? const Color(0xFF22C55E)
        : const Color(0xFF3B82F6);
    final sigLabel = signal == 'pahalı' ? l.priceSignalExpensive
        : signal == 'ucuz' ? l.priceSignalCheap
        : l.priceSignalFair;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.card(context), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(item['title'] as String? ?? '', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary(context)), maxLines: 1, overflow: TextOverflow.ellipsis)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: sigColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                child: Text(sigLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: sigColor)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _PriceBox(label: l.priceYours, value: '${yourPrice.toStringAsFixed(0)} ₺', color: sigColor)),
              const SizedBox(width: 10),
              Expanded(child: _PriceBox(label: l.priceMarketAvg, value: '${marketAvg.toStringAsFixed(0)} ₺', color: AppColors.textSecondary(context))),
              const SizedBox(width: 10),
              Expanded(child: _PriceBox(label: l.priceDiff, value: '${diffPct >= 0 ? '+' : ''}${diffPct.toStringAsFixed(1)}%', color: sigColor)),
            ],
          ),
        ],
      ),
    );
  }
}

class _PriceBox extends StatelessWidget {
  final String label, value;
  final Color color;
  const _PriceBox({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 10, color: AppColors.textSecondary(context)), textAlign: TextAlign.center),
      ],
    );
  }
}

// ── Yayın Performansı ─────────────────────────────────────────────────────────

class _StreamStatsCard extends StatelessWidget {
  final Map<String, dynamic> stats;
  final AppLocalizations l;
  final bool showAll;
  final VoidCallback onToggleAll;
  const _StreamStatsCard({required this.stats, required this.l, this.showAll = false, required this.onToggleAll});

  @override
  Widget build(BuildContext context) {
    final total   = stats['total_streams'] as int? ?? 0;
    final s30     = stats['streams_30d'] as int? ?? 0;
    final avgV    = (stats['avg_viewers'] as num?)?.toDouble() ?? 0;
    final peakV   = stats['peak_viewers'] as int? ?? 0;
    final avgDur  = (stats['avg_duration_min'] as num?)?.toDouble() ?? 0;
    final best    = (stats['best_streams'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    if (total == 0) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: AppColors.card(context), borderRadius: BorderRadius.circular(16)),
        child: Center(child: Text(l.proNoStreams, style: TextStyle(color: AppColors.textSecondary(context)))),
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.card(context), borderRadius: BorderRadius.circular(16)),
          child: Column(
            children: [
              Row(
                children: [
                  _StatBox(l.proStreamTotal, '$total'),
                  _vDivider(context),
                  _StatBox(l.proStreamThisMonth, '$s30'),
                  _vDivider(context),
                  _StatBox(l.proStreamAvgViewers, avgV.toStringAsFixed(1)),
                  _vDivider(context),
                  _StatBox(l.proStreamPeak, '$peakV'),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.timer_outlined, size: 14, color: AppColors.textSecondary(context)),
                  const SizedBox(width: 6),
                  Text(l.proStreamAvgDuration(avgDur.toStringAsFixed(0)),
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context))),
                ],
              ),
            ],
          ),
        ),
        if (best.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...( showAll ? best : best.take(5).toList())
              .asMap().entries.map((e) => _BestStreamRow(rank: e.key + 1, stream: e.value, l: l)),
          if (best.length > 5)
            _ShowMoreBtn(
              total: best.length,
              visible: showAll ? best.length : best.length.clamp(0, 5),
              sectionKey: 'streams',
              showAll: showAll,
              onToggle: onToggleAll,
              l: l,
            ),
        ],
      ],
    );
  }

  Widget _vDivider(BuildContext context) => Container(width: 1, height: 36, color: AppColors.divider(context), margin: const EdgeInsets.symmetric(horizontal: 8));
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  const _StatBox(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary(context))),
          Text(label, style: TextStyle(fontSize: 10, color: AppColors.textSecondary(context))),
        ],
      ),
    );
  }
}

class _BestStreamRow extends StatelessWidget {
  final int rank;
  final Map<String, dynamic> stream;
  final AppLocalizations l;
  const _BestStreamRow({required this.rank, required this.stream, required this.l});

  @override
  Widget build(BuildContext context) {
    final medals = ['🥇', '🥈', '🥉'];
    final medal = rank <= 3 ? medals[rank - 1] : '#$rank';
    final viewers = stream['viewers'] as int? ?? 0;
    final bids = stream['bids'] as int? ?? 0;
    final dur = stream['duration_min'] as int? ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: AppColors.card(context), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Text(medal, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 10),
          Expanded(child: Text(stream['title'] as String? ?? '', style: TextStyle(fontSize: 13, color: AppColors.textPrimary(context)), maxLines: 1, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          Text(l.proStreamRowStats(viewers, bids, dur),
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary(context))),
        ],
      ),
    );
  }
}

// ── Peak Hours ───────────────────────────────────────────────────────────────

class _PeakHourBar extends StatelessWidget {
  final String label;
  final int count, rank;
  final double ratio;
  final AppLocalizations l;
  const _PeakHourBar({required this.label, required this.count, required this.ratio, required this.rank, required this.l});

  @override
  Widget build(BuildContext context) {
    final colors = [kPrimary, const Color(0xFF3B82F6), const Color(0xFF8B5CF6), const Color(0xFF06B6D4), const Color(0xFF10B981)];
    final color = colors[(rank - 1).clamp(0, 4)];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.card(context), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
            child: Center(child: Text('#$rank', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color))),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary(context))),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: ratio, minHeight: 6, backgroundColor: AppColors.border(context), valueColor: AlwaysStoppedAnimation<Color>(color)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text('$count ${l.proEngagements}', style: TextStyle(fontSize: 11, color: AppColors.textSecondary(context))),
        ],
      ),
    );
  }
}

// ── PRO Gelişmiş Metrikler Kartı ─────────────────────────────────────────────

class _ProMetricsCard extends StatelessWidget {
  final Map<String, dynamic> metrics;
  final AppLocalizations l;
  const _ProMetricsCard({required this.metrics, required this.l});

  @override
  Widget build(BuildContext context) {
    final dwell = metrics['avg_detail_dwell_seconds'];
    final bestHour = metrics['best_posting_hour'];
    final returnRate = metrics['return_viewer_rate_pct'];
    final searchVis = (metrics['search_visibility'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.card(context), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _MetricChip(
              label: l.proMetricAvgDwell,
              value: dwell != null ? '${dwell.toStringAsFixed(0)}s' : '--',
            ),
            const SizedBox(width: 10),
            _MetricChip(
              label: l.proMetricBestHour,
              value: bestHour != null ? '${bestHour}:00' : '--',
            ),
            const SizedBox(width: 10),
            _MetricChip(
              label: l.proMetricReturnViewers,
              value: returnRate != null ? '%${returnRate.toStringAsFixed(1)}' : '--',
            ),
          ]),
          if (searchVis.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(l.proMetricSearchVisibility,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary(context))),
            const SizedBox(height: 6),
            ...searchVis.map((e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Expanded(child: Text(e['category'] as String? ?? '', style: TextStyle(fontSize: 12, color: AppColors.textPrimary(context)))),
                Text('${e['search_count']} arama', style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context))),
              ]),
            )),
          ],
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;
  const _MetricChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary(context))),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 9, color: AppColors.textSecondary(context)), textAlign: TextAlign.center, maxLines: 2),
        ],
      ),
    );
  }
}

// ── "Daha fazla gör" butonu ───────────────────────────────────────────────────

class _ShowMoreBtn extends StatelessWidget {
  final int total;
  final int visible;
  final String sectionKey;
  final bool showAll;
  final VoidCallback onToggle;
  final AppLocalizations l;

  const _ShowMoreBtn({
    required this.total,
    required this.visible,
    required this.sectionKey,
    required this.showAll,
    required this.onToggle,
    required this.l,
  });

  @override
  Widget build(BuildContext context) {
    if (total <= visible && !showAll) return const SizedBox.shrink();
    if (total <= 5) return const SizedBox.shrink();
    final remaining = total - 5;
    return GestureDetector(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              showAll ? l.proShowLess : l.proShowAll(remaining),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary(context),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              showAll ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              size: 16,
              color: AppColors.textSecondary(context),
            ),
          ],
        ),
      ),
    );
  }
}
