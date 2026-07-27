import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter/material.dart";
import "../services/localization_service.dart";
import 'package:intl/intl.dart';
import '../config/app_colors.dart';
import '../config/theme.dart';
import '../models/listing_filter_state.dart';
import '../services/analytics_service.dart';
import '../ui_library/components/filters/teq_filter_bar.dart';

class ProInsightsScreen extends ConsumerStatefulWidget {
  final bool isEmbedded;
  const ProInsightsScreen({super.key, this.isEmbedded = false});

  @override
  ConsumerState<ProInsightsScreen> createState() => _ProInsightsScreenState();
}

class _ProInsightsScreenState extends ConsumerState<ProInsightsScreen> {
  Map<String, dynamic>? _data;
  Map<String, dynamic>? _metrics;
  bool _loading = true;
  bool _hasError = false;
  final Map<String, bool> _showAll = {};

  static const int _kMaxVisible = 5;

  // ── Filtre state ─────────────────────────────────────────────────────────
  ListingFilterState _hotLeadsFilter = const ListingFilterState();
  ListingFilterState _priceIntelFilter = const ListingFilterState();
  String _priceIntelSignal = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _onHotLeadsFilterChanged(ListingFilterState f) {
    final dateChanged = f.dateFrom != _hotLeadsFilter.dateFrom || f.dateTo != _hotLeadsFilter.dateTo;
    setState(() {
      _hotLeadsFilter = f;
      if (dateChanged) {
        _priceIntelFilter = _priceIntelFilter.copyWith(dateFrom: f.dateFrom, dateTo: f.dateTo);
      }
      _showAll['hotLeads'] = false;
    });
    if (dateChanged) _load();
  }

  void _onPriceIntelFilterChanged(ListingFilterState f) {
    final dateChanged = f.dateFrom != _priceIntelFilter.dateFrom || f.dateTo != _priceIntelFilter.dateTo;
    setState(() {
      _priceIntelFilter = f;
      if (dateChanged) {
        _hotLeadsFilter = _hotLeadsFilter.copyWith(dateFrom: f.dateFrom, dateTo: f.dateTo);
      }
      _showAll['priceIntel'] = false;
    });
    if (dateChanged) _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _hasError = false; });
    final sd = _hotLeadsFilter.dateFrom?.toIso8601String().substring(0, 10);
    final ed = _hotLeadsFilter.dateTo?.toIso8601String().substring(0, 10);
    final results = await Future.wait([
      AnalyticsService.getProInsights(startDate: sd, endDate: ed),
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
    final loc = ref.read(localizationProvider);
    final bodyContent = _loading
        ? const Center(child: CircularProgressIndicator())
        : _hasError
            ? _buildError(loc)
            : RefreshIndicator(onRefresh: _load, child: _buildBody(loc));

    if (widget.isEmbedded) {
      return bodyContent;
    }

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        backgroundColor: AppColors.bg(context),
        elevation: 0,
        title: Text(loc.t("proToolSalesTitle"), style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: bodyContent,
    );
  }

  Widget _buildError(TranslationPack loc) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off_outlined, size: 48, color: AppColors.textSecondary(context)),
          const SizedBox(height: 12),
          Text(loc.t("proLoadFailed"), style: TextStyle(color: AppColors.textSecondary(context))),
          const SizedBox(height: 16),
          FilledButton(onPressed: _load, child: Text(loc.t("btnRetry"))),
        ],
      ),
    );
  }

  // ── Filtre yardımcıları ──────────────────────────────────────────────────
  List<Map<String, dynamic>> _applyHotLeadsFilter(List<Map<String, dynamic>> raw) {
    var r = raw;
    if (_hotLeadsFilter.searchQuery != null && _hotLeadsFilter.searchQuery!.isNotEmpty) {
      final q = _hotLeadsFilter.searchQuery!.toLowerCase();
      r = r.where((m) => (m['title'] as String? ?? '').toLowerCase().contains(q)).toList();
    }
    if (_hotLeadsFilter.category != null && _hotLeadsFilter.category!.isNotEmpty) {
      r = r.where((m) => m['category'] == _hotLeadsFilter.category).toList();
    }
    return r;
  }

  List<Map<String, dynamic>> _applyPriceIntelFilter(List<Map<String, dynamic>> raw) {
    var r = raw;
    if (_priceIntelFilter.searchQuery != null && _priceIntelFilter.searchQuery!.isNotEmpty) {
      final q = _priceIntelFilter.searchQuery!.toLowerCase();
      r = r.where((m) => (m['title'] as String? ?? '').toLowerCase().contains(q)).toList();
    }
    if (_priceIntelFilter.category != null && _priceIntelFilter.category!.isNotEmpty) {
      r = r.where((m) => m['category'] == _priceIntelFilter.category).toList();
    }
    if (_priceIntelSignal.isNotEmpty) {
      r = r.where((m) => m['signal'] == _priceIntelSignal).toList();
    }
    return r;
  }

  Widget _filterChip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: kPrimary.withValues(alpha: 0.15),
        checkmarkColor: kPrimary,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      ),
    );
  }

  Widget _buildBody(TranslationPack loc) {
    final kpis           = (_data?['kpis']        as Map<String, dynamic>?) ?? {};
    final funnel         = (_data?['funnel']       as Map<String, dynamic>?) ?? {};
    final allHotLeads    = (_data?['hot_leads']    as List?)?.cast<Map<String, dynamic>>() ?? [];
    final allPriceIntel  = (_data?['price_intel']  as List?)?.cast<Map<String, dynamic>>() ?? [];
    final streamStats    = (_data?['stream_stats'] as Map<String, dynamic>?) ?? {};
    final peakHours      = (_data?['peak_hours']   as List?)?.cast<Map<String, dynamic>>() ?? [];
    final tips           = (_data?['tips']         as List?)?.cast<Map<String, dynamic>>() ?? [];

    final hotLeads   = _applyHotLeadsFilter(allHotLeads);
    final priceIntel = _applyPriceIntelFilter(allPriceIntel);

    final bool hlFiltered = !_hotLeadsFilter.isEmpty;
    final bool piFiltered = !_priceIntelFilter.isEmpty || _priceIntelSignal.isNotEmpty;

    return ListView(shrinkWrap: widget.isEmbedded, physics: widget.isEmbedded ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
      children: [
        _SectionLabel(loc.t("proSectionOverview")),
        _KpiGrid(kpis: kpis, loc: loc),
        const SizedBox(height: 20),

        _SectionLabel(loc.t("proSectionFunnel")),
        _FunnelCard(funnel: funnel, loc: loc),
        const SizedBox(height: 20),

        if (tips.isNotEmpty) ...[
          _SectionLabel(loc.t("proSectionTips")),
          ...tips.map((t) => _TipCard(tip: t)),
          const SizedBox(height: 20),
        ],

        if (allHotLeads.isNotEmpty) ...[
          _SectionLabel(loc.t("proSectionHotLeads")),
          _SubLabel(loc.t("proHotLeadsDesc")),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TeqFilterBar(
                filter: _hotLeadsFilter,
                onChanged: _onHotLeadsFilterChanged,
                showSubcategory: false,
                showCity: false,
                showCondition: false,
                showSort: false,
                showPriceRange: false,
              ),
              const SizedBox(height: 10),
            ],
          ),
          if (hlFiltered && hotLeads.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(loc.t("searchNoResults"),
                  style: TextStyle(color: AppColors.textSecondary(context), fontSize: 13)),
            )
          else
            _buildHotLeadsCarousel(hotLeads, loc),
          const SizedBox(height: 20),
        ],

        if (allPriceIntel.isNotEmpty) ...[
          _SectionLabel(loc.t("proSectionPriceIntel")),
          _SubLabel(loc.t("proPriceIntelDesc")),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TeqFilterBar(
                filter: _priceIntelFilter,
                onChanged: _onPriceIntelFilterChanged,
                showSubcategory: false,
                showCity: false,
                showCondition: false,
                showSort: false,
                showPriceRange: false,
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 32,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _filterChip(loc.t("profileFilterAll"), _priceIntelSignal.isEmpty,
                        () => setState(() { _priceIntelSignal = ''; _showAll['priceIntel'] = false; })),
                    _filterChip(loc.t("priceSignalExpensive"), _priceIntelSignal == 'pahalı',
                        () => setState(() { _priceIntelSignal = _priceIntelSignal == 'pahalı' ? '' : 'pahalı'; _showAll['priceIntel'] = false; })),
                    _filterChip(loc.t("priceSignalCheap"), _priceIntelSignal == 'ucuz',
                        () => setState(() { _priceIntelSignal = _priceIntelSignal == 'ucuz' ? '' : 'ucuz'; _showAll['priceIntel'] = false; })),
                    _filterChip(loc.t("priceSignalFair"), _priceIntelSignal == 'uygun',
                        () => setState(() { _priceIntelSignal = _priceIntelSignal == 'uygun' ? '' : 'uygun'; _showAll['priceIntel'] = false; })),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
          if (piFiltered && priceIntel.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(loc.t("searchNoResults"),
                  style: TextStyle(color: AppColors.textSecondary(context), fontSize: 13)),
            )
          else
            _buildPriceIntelCarousel(priceIntel, loc),
          const SizedBox(height: 20),
        ],

        _SectionLabel(loc.t("proSectionStreamPerf")),
        _StreamStatsCard(stats: streamStats, loc: loc, showAll: _showAll['streams'] ?? false,
          onToggleAll: () => setState(() => _showAll['streams'] = !(_showAll['streams'] ?? false))),
        const SizedBox(height: 20),

        if (peakHours.isNotEmpty) ...[
          _SectionLabel(loc.t("proSectionPeakHours")),
          _SubLabel(loc.t("proPeakHoursDesc")),
          ..._buildPeakBars(_limited('peakHours', peakHours), loc),
          _ShowMoreBtn(
            total: peakHours.length,
            visible: _visibleCount('peakHours', peakHours.length),
            sectionKey: 'peakHours',
            showAll: _showAll['peakHours'] ?? false,
            onToggle: () => setState(() => _showAll['peakHours'] = !(_showAll['peakHours'] ?? false)),
            loc: loc,
          ),
          const SizedBox(height: 20),
        ],

        if (_metrics != null) ...[
          _SectionLabel(loc.t("proSectionAIMetrics")),
          _ProMetricsCard(metrics: _metrics!, loc: loc),
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

  Widget _buildHotLeadsCarousel(List<Map<String, dynamic>> items, TranslationPack loc) {
    if (items.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 140,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        itemBuilder: (ctx, i) => _HotLeadCard(lead: items[i], loc: loc),
      ),
    );
  }

  Widget _buildPriceIntelCarousel(List<Map<String, dynamic>> items, TranslationPack loc) {
    if (items.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 160,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        itemBuilder: (ctx, i) => _PriceIntelCard(item: items[i], loc: loc),
      ),
    );
  }

  List<Widget> _buildPeakBars(List<Map<String, dynamic>> hours, TranslationPack loc) {
    final maxCount = hours.map((h) => (h['count'] as num?)?.toInt() ?? 0).reduce((a, b) => a > b ? a : b);
    return hours.asMap().entries.map((e) {
      final i = e.key;
      final h = e.value;
      final count = (h['count'] as num?)?.toInt() ?? 0;
      final ratio = maxCount > 0 ? count / maxCount : 0.0;
      return _PeakHourBar(label: h['label'] as String, count: count, ratio: ratio, rank: i + 1, loc: loc);
    }).toList();
  }
}

// ── Bölüm Başlıkları ─────────────────────────────────────────────────────────

class _SectionLabel extends ConsumerWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text, style: TextStyle(
        fontSize: 16, fontWeight: FontWeight.w800,
        color: AppColors.textPrimary(context),
      )),
    );
  }
}

class _SubLabel extends ConsumerWidget {
  final String text;
  const _SubLabel(this.text);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text, style: TextStyle(
        fontSize: 12, color: AppColors.textSecondary(context),
      )),
    );
  }
}

// ── KPI Grid ─────────────────────────────────────────────────────────────────

class _KpiGrid extends ConsumerWidget {
  final Map<String, dynamic> kpis;
  final TranslationPack loc;
  const _KpiGrid({required this.kpis, required this.loc});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rev30 = (kpis['revenue_30d'] as num?)?.toDouble() ?? 0;
    final revGrowth = (kpis['revenue_growth_pct'] as num?)?.toDouble();
    final sales30 = (kpis['sales_30d'] as num?)?.toInt() ?? 0;
    final bids30 = (kpis['bids_30d'] as num?)?.toInt() ?? 0;
    final activeL = (kpis['active_listings'] as num?)?.toInt() ?? 0;
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
          icon: '💰', label: loc.t("proKpiRevenue30d"),
          value: '${_fmt(rev30)} ₺',
          badge: growthStr,
          badgeColor: (revGrowth ?? 0) >= 0 ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
          gradient: const [Color(0xFF0F766E), Color(0xFF0D9488)],
        ),
        _KpiCard(
          icon: '🛍', label: loc.t("proKpiSales"),
          value: '$sales30 ${loc.t("proKpiItemUnit")}',
          badge: loc.t("proKpiLast30d"),
          badgeColor: const Color(0xFF3B82F6),
          gradient: const [Color(0xFF1D4ED8), Color(0xFF3B82F6)],
        ),
        _KpiCard(
          icon: '🔨', label: loc.t("proKpiBids"),
          value: '$bids30 ${loc.t("proKpiBidUnit")}',
          badge: loc.t("proKpiLast30d"),
          badgeColor: const Color(0xFFF59E0B),
          gradient: const [Color(0xFFB45309), Color(0xFFF59E0B)],
        ),
        _KpiCard(
          icon: '📦', label: loc.t("proKpiActiveListings"),
          value: '$activeL ${loc.t("proKpiListingUnit")}',
          badge: '${_fmt(totalRev)} ₺ ${loc.t("proKpiTotalUnit")}',
          badgeColor: const Color(0xFF8B5CF6),
          gradient: const [Color(0xFF6D28D9), Color(0xFF8B5CF6)],
        ),
      ],
    );
  }

  static String _fmt(double v) => NumberFormat('#,##0', 'tr_TR').format(v);
}

class _KpiCard extends ConsumerWidget {
  final String icon, label, value, badge;
  final Color badgeColor;
  final List<Color> gradient;

  const _KpiCard({
    required this.icon, required this.label, required this.value,
    required this.badge, required this.badgeColor, required this.gradient,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

class _FunnelCard extends ConsumerWidget {
  final Map<String, dynamic> funnel;
  final TranslationPack loc;
  const _FunnelCard({required this.funnel, required this.loc});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardBg = AppColors.card(context);
    final views = (funnel['views'] as num?)?.toInt() ?? 0;
    final hesitations = (funnel['hesitations'] as num?)?.toInt() ?? 0;
    final bids = (funnel['bids'] as num?)?.toInt() ?? 0;
    final sales = (funnel['sales'] as num?)?.toInt() ?? 0;
    final v2b = (funnel['view_to_bid_pct'] as num?)?.toDouble() ?? 0;
    final b2s = (funnel['bid_to_sale_pct'] as num?)?.toDouble() ?? 0;
    final maxVal = [views, hesitations, bids, sales].reduce((a, b) => a > b ? a : b).toDouble();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          _FunnelRow(label: loc.t("proFunnelViews"), count: views, maxVal: maxVal, color: const Color(0xFF3B82F6)),
          const SizedBox(height: 8),
          _FunnelRow(label: loc.t("proFunnelHesitation"), count: hesitations, maxVal: maxVal, color: const Color(0xFFF59E0B)),
          const SizedBox(height: 8),
          _FunnelRow(label: loc.t("proFunnelBid"), count: bids, maxVal: maxVal, color: const Color(0xFF8B5CF6)),
          const SizedBox(height: 8),
          _FunnelRow(label: loc.t("proFunnelSale"), count: sales, maxVal: maxVal, color: const Color(0xFF22C55E)),
          Divider(color: AppColors.border(context), height: 24),
          Row(
            children: [
              _RateBadge(label: loc.t("proFunnelViewToBid"), value: '$v2b%',
                  color: v2b >= 5 ? const Color(0xFF22C55E) : const Color(0xFFF59E0B)),
              const SizedBox(width: 12),
              _RateBadge(label: loc.t("proFunnelBidToSale"), value: '$b2s%',
                  color: b2s >= 30 ? const Color(0xFF22C55E) : const Color(0xFFEF4444)),
            ],
          ),
        ],
      ),
    );
  }
}

class _FunnelRow extends ConsumerWidget {
  final String label;
  final int count;
  final double maxVal;
  final Color color;
  const _FunnelRow({required this.label, required this.count, required this.maxVal, required this.color});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

class _RateBadge extends ConsumerWidget {
  final String label, value;
  final Color color;
  const _RateBadge({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

class _TipCard extends ConsumerWidget {
  final Map<String, dynamic> tip;
  const _TipCard({required this.tip});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

// ── Sıcak Talep Carousel Kartı ───────────────────────────────────────────────

class _HotLeadCard extends ConsumerWidget {
  final Map<String, dynamic> lead;
  final TranslationPack loc;
  const _HotLeadCard({required this.lead, required this.loc});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final views = (lead['views_30d'] as num?)?.toInt() ?? 0;
    final hes   = (lead['hesitations_30d'] as num?)?.toInt() ?? 0;
    final heat  = (lead['heat_score'] as num?)?.toInt() ?? 0;
    final price = (lead['price'] as num?)?.toDouble();
    final catLabel = lead['category'] as String? ?? '';
    final heatColor = heat > 15
        ? const Color(0xFFEF4444)
        : heat > 5 ? const Color(0xFFF59E0B) : const Color(0xFF22C55E);

    return Container(
      width: 170,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: heat > 10
              ? const Color(0xFFF59E0B).withValues(alpha: 0.5)
              : AppColors.border(context),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(color: heatColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(catLabel,
                    style: TextStyle(fontSize: 10, color: AppColors.textSecondary(context)),
                    overflow: TextOverflow.ellipsis),
              ),
              if (price != null)
                Text('${NumberFormat('#,##0', 'tr_TR').format(price)} ₺',
                    style: TextStyle(fontSize: 10, color: AppColors.textSecondary(context))),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            lead['title'] as String? ?? '',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary(context)),
            maxLines: 2, overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(child: _Chip(loc.t("hotLeadViewed", {"count": views.toString()}), const Color(0xFF3B82F6))),
              const SizedBox(width: 4),
              Expanded(child: _Chip(loc.t("hotLeadHesitated", {"count": hes.toString()}), const Color(0xFFF59E0B))),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Fiyat Zekası Carousel Kartı ───────────────────────────────────────────────

class _PriceIntelCard extends ConsumerWidget {
  final Map<String, dynamic> item;
  final TranslationPack loc;
  const _PriceIntelCard({required this.item, required this.loc});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final yourPrice = (item['your_price'] as num?)?.toDouble() ?? 0;
    final marketAvg = (item['market_avg'] as num?)?.toDouble() ?? 0;
    final diffPct   = (item['diff_pct'] as num?)?.toDouble() ?? 0;
    final signal    = item['signal'] as String? ?? 'uygun';

    final sigColor = signal == 'pahalı' ? const Color(0xFFEF4444)
        : signal == 'ucuz' ? const Color(0xFF22C55E)
        : const Color(0xFF3B82F6);
    final sigLabel = signal == 'pahalı' ? loc.t("priceSignalExpensive")
        : signal == 'ucuz' ? loc.t("priceSignalCheap")
        : loc.t("priceSignalFair");

    return Container(
      width: 170,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  item['title'] as String? ?? '',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary(context)),
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: sigColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(sigLabel,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: sigColor)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _PriceRow(
            label: loc.t("priceYours"),
            value: '${NumberFormat('#,##0', 'tr_TR').format(yourPrice)} ₺',
            valueColor: sigColor,
            bold: true,
          ),
          const SizedBox(height: 3),
          _PriceRow(
            label: loc.t("priceMarketAvg"),
            value: '${NumberFormat('#,##0', 'tr_TR').format(marketAvg)} ₺',
          ),
          const SizedBox(height: 3),
          _PriceRow(
            label: loc.t("priceDiff"),
            value: '${diffPct >= 0 ? '+' : ''}${diffPct.toStringAsFixed(1)}%',
            valueColor: sigColor,
            bold: true,
          ),
        ],
      ),
    );
  }
}

// ── Sıcak Talep (eski dikey satır - geriye dönük uyumluluk için) ─────────────


class _Chip extends ConsumerWidget {
  final String label;
  final Color color;
  const _Chip(this.label, this.color);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

// ── Fiyat Zekası ─────────────────────────────────────────────────────────────


class _PriceRow extends ConsumerWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool bold;
  const _PriceRow({required this.label, required this.value, this.valueColor, this.bold = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(fontSize: 10, color: AppColors.textSecondary(context))),
        Text(value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
              color: valueColor ?? AppColors.textPrimary(context),
            ),
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    );
  }
}


// ── Yayın Performansı ─────────────────────────────────────────────────────────

class _StreamStatsCard extends ConsumerWidget {
  final Map<String, dynamic> stats;
  final TranslationPack loc;
  final bool showAll;
  final VoidCallback onToggleAll;
  const _StreamStatsCard({required this.stats, required this.loc, this.showAll = false, required this.onToggleAll});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total   = (stats['total_streams'] as num?)?.toInt() ?? 0;
    final s30     = (stats['streams_30d'] as num?)?.toInt() ?? 0;
    final avgV    = (stats['avg_viewers'] as num?)?.toDouble() ?? 0;
    final peakV   = (stats['peak_viewers'] as num?)?.toInt() ?? 0;
    final avgDur  = (stats['avg_duration_min'] as num?)?.toDouble() ?? 0;
    final best    = (stats['best_streams'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    if (total == 0) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: AppColors.card(context), borderRadius: BorderRadius.circular(16)),
        child: Center(child: Text(loc.t("proNoStreams"), style: TextStyle(color: AppColors.textSecondary(context)))),
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
                  _StatBox(loc.t("proStreamTotal"), '$total'),
                  _vDivider(context),
                  _StatBox(loc.t("proStreamThisMonth"), '$s30'),
                  _vDivider(context),
                  _StatBox(loc.t("proStreamAvgViewers"), avgV.toStringAsFixed(1)),
                  _vDivider(context),
                  _StatBox(loc.t("proStreamPeak"), '$peakV'),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.timer_outlined, size: 14, color: AppColors.textSecondary(context)),
                  const SizedBox(width: 6),
                  Text(loc.t("proStreamAvgDuration", {"dur": avgDur.toStringAsFixed(0)}),
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context))),
                ],
              ),
            ],
          ),
        ),
        if (best.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...( showAll ? best : best.take(5).toList())
              .asMap().entries.map((e) => _BestStreamRow(rank: e.key + 1, stream: e.value, loc: loc)),
          if (best.length > 5)
            _ShowMoreBtn(
              total: best.length,
              visible: showAll ? best.length : best.length.clamp(0, 5),
              sectionKey: 'streams',
              showAll: showAll,
              onToggle: onToggleAll,
              loc: loc,
            ),
        ],
      ],
    );
  }

  Widget _vDivider(BuildContext context) => Container(width: 1, height: 36, color: AppColors.divider(context), margin: const EdgeInsets.symmetric(horizontal: 8));
}

class _StatBox extends ConsumerWidget {
  final String label;
  final String value;
  const _StatBox(this.label, this.value);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

class _BestStreamRow extends ConsumerWidget {
  final int rank;
  final Map<String, dynamic> stream;
  final TranslationPack loc;
  const _BestStreamRow({required this.rank, required this.stream, required this.loc});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final medals = ['🥇', '🥈', '🥉'];
    final medal = rank <= 3 ? medals[rank - 1] : '#$rank';
    final viewers = (stream['viewers'] as num?)?.toInt() ?? 0;
    final bids = (stream['bids'] as num?)?.toInt() ?? 0;
    final dur = (stream['duration_min'] as num?)?.toInt() ?? 0;
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
          Text(loc.t("proStreamRowStats", {"viewers": viewers.toString(), "bids": bids.toString(), "dur": dur.toString()}),
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary(context))),
        ],
      ),
    );
  }
}

// ── Peak Hours ───────────────────────────────────────────────────────────────

class _PeakHourBar extends ConsumerWidget {
  final String label;
  final int count, rank;
  final double ratio;
  final TranslationPack loc;
  const _PeakHourBar({required this.label, required this.count, required this.ratio, required this.rank, required this.loc});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          Text('$count ${loc.t("proEngagements")}', style: TextStyle(fontSize: 11, color: AppColors.textSecondary(context))),
        ],
      ),
    );
  }
}

// ── PRO Gelişmiş Metrikler Kartı ─────────────────────────────────────────────

class _ProMetricsCard extends ConsumerWidget {
  final Map<String, dynamic> metrics;
  final TranslationPack loc;
  const _ProMetricsCard({required this.metrics, required this.loc});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              label: loc.t("proMetricAvgDwell"),
              value: dwell != null ? '${dwell.toStringAsFixed(0)}s' : '--',
            ),
            const SizedBox(width: 10),
            _MetricChip(
              label: loc.t("proMetricBestHour"),
              value: bestHour != null ? '$bestHour:00' : '--',
            ),
            const SizedBox(width: 10),
            _MetricChip(
              label: loc.t("proMetricReturnViewers"),
              value: returnRate != null ? '%${returnRate.toStringAsFixed(1)}' : '--',
            ),
          ]),
          if (searchVis.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(loc.t("proMetricSearchVisibility"),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary(context))),
            const SizedBox(height: 6),
            ...searchVis.map((e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Expanded(child: Text(
                  e['category'] as String? ?? '',
                  style: TextStyle(fontSize: 12, color: AppColors.textPrimary(context)))),
                Text(loc.t("proSearchCount", {"count": ((e['search_count'] as num?)?.toInt() ?? 0).toString()}), style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context))),
              ]),
            )),
          ],
        ],
      ),
    );
  }
}

class _MetricChip extends ConsumerWidget {
  final String label;
  final String value;
  const _MetricChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

class _ShowMoreBtn extends ConsumerWidget {
  final int total;
  final int visible;
  final String sectionKey;
  final bool showAll;
  final VoidCallback onToggle;
  final TranslationPack loc;

  const _ShowMoreBtn({
    required this.total,
    required this.visible,
    required this.sectionKey,
    required this.showAll,
    required this.onToggle,
    required this.loc,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              showAll ? loc.t("proShowLess") : loc.t("proShowAll", {"count": remaining.toString()}),
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
