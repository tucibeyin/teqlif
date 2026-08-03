import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter/material.dart";
import "../services/localization_service.dart";
import 'package:intl/intl.dart';
import '../config/app_colors.dart';
import '../config/theme.dart';
import '../models/pro_insights_data.dart';
import '../ui_library/components/filters/teq_filter_bar.dart';
import 'viewmodels/pro_insights_view_model.dart';

class ProInsightsScreen extends ConsumerStatefulWidget {
  final bool isEmbedded;
  const ProInsightsScreen({super.key, this.isEmbedded = false});

  @override
  ConsumerState<ProInsightsScreen> createState() => _ProInsightsScreenState();
}

class _ProInsightsScreenState extends ConsumerState<ProInsightsScreen> {
  static const int _kMaxVisible = 5;

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(localizationProvider);
    final state = ref.watch(proInsightsProvider);
    final viewModel = ref.read(proInsightsProvider.notifier);

    final bodyContent = state.loading
        ? const Center(child: CircularProgressIndicator())
        : state.hasError
            ? _buildError(loc, viewModel)
            : RefreshIndicator(onRefresh: () => viewModel.load(bypassCache: true), child: _buildBody(loc, state, viewModel));

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
            onPressed: () => viewModel.load(bypassCache: true),
          ),
        ],
      ),
      body: bodyContent,
    );
  }

  Widget _buildError(TranslationPack loc, ProInsightsViewModel viewModel) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off_outlined, size: 48, color: AppColors.textSecondary(context)),
          const SizedBox(height: 12),
          Text(loc.t("proLoadFailed"), style: TextStyle(color: AppColors.textSecondary(context))),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => viewModel.load(bypassCache: true), child: Text(loc.t("btnRetry"))),
        ],
      ),
    );
  }

  // ── Filtre yardımcıları ──────────────────────────────────────────────────
  List<HotLead> _applyHotLeadsFilter(List<HotLead> raw, ProInsightsState state) {
    var r = raw;
    if (state.hotLeadsFilter.searchQuery != null && state.hotLeadsFilter.searchQuery!.isNotEmpty) {
      final q = state.hotLeadsFilter.searchQuery!.toLowerCase();
      r = r.where((m) => m.title.toLowerCase().contains(q)).toList();
    }
    if (state.hotLeadsFilter.category != null && state.hotLeadsFilter.category!.isNotEmpty) {
      r = r.where((m) => m.category == state.hotLeadsFilter.category).toList();
    }
    if (state.hotLeadsFilter.subcategory != null && state.hotLeadsFilter.subcategory!.isNotEmpty) {
      r = r.where((m) => m.subcategory == state.hotLeadsFilter.subcategory).toList();
    }
    return r;
  }

  List<PriceIntel> _applyPriceIntelFilter(List<PriceIntel> raw, ProInsightsState state) {
    var r = raw;
    if (state.priceIntelFilter.searchQuery != null && state.priceIntelFilter.searchQuery!.isNotEmpty) {
      final q = state.priceIntelFilter.searchQuery!.toLowerCase();
      r = r.where((m) => m.title.toLowerCase().contains(q)).toList();
    }
    if (state.priceIntelFilter.category != null && state.priceIntelFilter.category!.isNotEmpty) {
      r = r.where((m) => m.category == state.priceIntelFilter.category).toList();
    }
    if (state.priceIntelFilter.subcategory != null && state.priceIntelFilter.subcategory!.isNotEmpty) {
      r = r.where((m) => m.subcategory == state.priceIntelFilter.subcategory).toList();
    }
    if (state.priceIntelSignal.isNotEmpty) {
      r = r.where((m) => m.signal == state.priceIntelSignal).toList();
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

  Widget _buildBody(TranslationPack loc, ProInsightsState state, ProInsightsViewModel viewModel) {
    final kpis        = state.data?.kpis ?? ProKpis.empty;
    final funnel      = state.data?.funnel ?? ProFunnel.empty;
    final allHotLeads = state.data?.hotLeads ?? <HotLead>[];
    final allPriceIntel = state.data?.priceIntel ?? <PriceIntel>[];
    final streamStats = state.data?.streamStats ?? StreamStats.empty;
    final peakHours   = state.data?.peakHours ?? <PeakHour>[];
    final tips        = state.data?.tips ?? <ProTip>[];

    final hotLeads   = _applyHotLeadsFilter(allHotLeads, state);
    final priceIntel = _applyPriceIntelFilter(allPriceIntel, state);

    final bool hlFiltered = !state.hotLeadsFilter.isEmpty;
    final bool piFiltered = !state.priceIntelFilter.isEmpty || state.priceIntelSignal.isNotEmpty;

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
                filter: state.hotLeadsFilter,
                onChanged: (f) => viewModel.updateHotLeadsFilter(f),
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
                filter: state.priceIntelFilter,
                onChanged: (f) => viewModel.updatePriceIntelFilter(f),
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
                    _filterChip(loc.t("profileFilterAll"), state.priceIntelSignal.isEmpty,
                        () => viewModel.updatePriceIntelSignal('')),
                    _filterChip(loc.t("priceSignalExpensive"), state.priceIntelSignal == 'pahalı',
                        () => viewModel.updatePriceIntelSignal(state.priceIntelSignal == 'pahalı' ? '' : 'pahalı')),
                    _filterChip(loc.t("priceSignalCheap"), state.priceIntelSignal == 'ucuz',
                        () => viewModel.updatePriceIntelSignal(state.priceIntelSignal == 'ucuz' ? '' : 'ucuz')),
                    _filterChip(loc.t("priceSignalFair"), state.priceIntelSignal == 'uygun',
                        () => viewModel.updatePriceIntelSignal(state.priceIntelSignal == 'uygun' ? '' : 'uygun')),
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
        _StreamStatsCard(stats: streamStats, loc: loc, showAll: state.showAll['streams'] ?? false,
          onToggleAll: () => viewModel.toggleShowAll('streams')),
        const SizedBox(height: 20),

        if (peakHours.isNotEmpty) ...[
          _SectionLabel(loc.t("proSectionPeakHours")),
          _SubLabel(loc.t("proPeakHoursDesc")),
          ..._buildPeakBars(_limited('peakHours', peakHours, state), loc),
          _ShowMoreBtn(
            total: peakHours.length,
            visible: _visibleCount('peakHours', peakHours.length, state),
            sectionKey: 'peakHours',
            showAll: state.showAll['peakHours'] ?? false,
            onToggle: () => viewModel.toggleShowAll('peakHours'),
            loc: loc,
          ),
          const SizedBox(height: 20),
        ],

        if (state.metrics != null) ...[
          _SectionLabel(loc.t("proSectionAIMetrics")),
          _ProMetricsCard(metrics: state.metrics!, loc: loc),
          const SizedBox(height: 20),
        ],
      ],
    );
  }

  List<T> _limited<T>(String key, List<T> items, ProInsightsState state) {
    if (state.showAll[key] == true) return items;
    return items.take(_kMaxVisible).toList();
  }

  int _visibleCount(String key, int total, ProInsightsState state) =>
      state.showAll[key] == true ? total : total.clamp(0, _kMaxVisible);

  Widget _buildHotLeadsCarousel(List<HotLead> items, TranslationPack loc) {
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

  Widget _buildPriceIntelCarousel(List<PriceIntel> items, TranslationPack loc) {
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

  List<Widget> _buildPeakBars(List<PeakHour> hours, TranslationPack loc) {
    final maxCount = hours.map((h) => h.count).reduce((a, b) => a > b ? a : b);
    return hours.asMap().entries.map((e) {
      final h = e.value;
      final ratio = maxCount > 0 ? h.count / maxCount : 0.0;
      return _PeakHourBar(label: h.label, count: h.count, ratio: ratio, rank: e.key + 1, loc: loc);
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
  final ProKpis kpis;
  final TranslationPack loc;
  const _KpiGrid({required this.kpis, required this.loc});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rev30 = kpis.revenue30d;
    final revGrowth = kpis.revenueGrowthPct;
    final sales30 = kpis.sales30d;
    final bids30 = kpis.bids30d;
    final activeL = kpis.activeListings;
    final totalRev = kpis.totalRevenue;

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
  final ProFunnel funnel;
  final TranslationPack loc;
  const _FunnelCard({required this.funnel, required this.loc});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardBg = AppColors.card(context);
    final views = funnel.views;
    final dwells = funnel.dwells;
    final hesitations = funnel.hesitations;
    final bids = funnel.bids;
    final sales = funnel.sales;
    final v2b = funnel.viewToBidPct;
    final b2s = funnel.bidToSalePct;
    final maxVal = [views, dwells, hesitations, bids, sales].reduce((a, b) => a > b ? a : b).toDouble();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          _FunnelRow(label: loc.t("proFunnelViews"), count: views, maxVal: maxVal, color: const Color(0xFF3B82F6)),
          const SizedBox(height: 8),
          _FunnelRow(label: loc.t("proFunnelDwells"), count: dwells, maxVal: maxVal, color: const Color(0xFF06B6D4)),
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
  final ProTip tip;
  const _TipCard({required this.tip});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final typeColors = {
      'price': const Color(0xFFEF4444), 'price_up': const Color(0xFF22C55E),
      'lead': const Color(0xFFF59E0B), 'stream': const Color(0xFF3B82F6),
      'listing_quality': const Color(0xFF8B5CF6), 'general': kPrimary,
    };
    final color = typeColors[tip.type] ?? kPrimary;

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
            child: Center(child: Text(tip.icon, style: const TextStyle(fontSize: 18))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tip.title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
                const SizedBox(height: 4),
                Text(tip.body, style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context), height: 1.4)),
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
  final HotLead lead;
  final TranslationPack loc;
  const _HotLeadCard({required this.lead, required this.loc});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final views     = lead.views30d;
    final hes       = lead.hesitations30d;
    final heat      = lead.heatScore;
    final price     = lead.price;
    final catLabel  = lead.category;
    final isBoosted = lead.isBoosted;
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
              if (isBoosted) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.4)),
                  ),
                  child: Text(loc.t("hotLeadBoosted"),
                      style: const TextStyle(fontSize: 9, color: Color(0xFF8B5CF6), fontWeight: FontWeight.w600)),
                ),
              ] else if (price != null)
                Text('${NumberFormat('#,##0', 'tr_TR').format(price)} ₺',
                    style: TextStyle(fontSize: 10, color: AppColors.textSecondary(context))),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            lead.title,
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
  final PriceIntel item;
  final TranslationPack loc;
  const _PriceIntelCard({required this.item, required this.loc});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final yourPrice = item.yourPrice;
    final marketAvg = item.marketAvg;
    final diffPct   = item.diffPct;
    final signal    = item.signal;

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
                  item.title,
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
  final StreamStats stats;
  final TranslationPack loc;
  final bool showAll;
  final VoidCallback onToggleAll;
  const _StreamStatsCard({required this.stats, required this.loc, this.showAll = false, required this.onToggleAll});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total   = stats.totalStreams;
    final s30     = stats.streams30d;
    final avgV    = stats.avgViewers;
    final peakV   = stats.peakViewers;
    final avgDur  = stats.avgDurationMin;
    final best    = stats.bestStreams;

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
          ...(showAll ? best : best.take(5).toList())
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
  final BestStream stream;
  final TranslationPack loc;
  const _BestStreamRow({required this.rank, required this.stream, required this.loc});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final medals = ['🥇', '🥈', '🥉'];
    final medal = rank <= 3 ? medals[rank - 1] : '#$rank';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: AppColors.card(context), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Text(medal, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 10),
          Expanded(child: Text(stream.title, style: TextStyle(fontSize: 13, color: AppColors.textPrimary(context)), maxLines: 1, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          Text(loc.t("proStreamRowStats", {"viewers": stream.viewers.toString(), "bids": stream.bids.toString(), "dur": stream.durationMin.toString()}),
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
  final ProMetrics metrics;
  final TranslationPack loc;
  const _ProMetricsCard({required this.metrics, required this.loc});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dwell = metrics.avgDetailDwellSeconds;
    final bestHour = metrics.bestPostingHour;
    final returnRate = metrics.returnViewerRatePct;
    final searchVis = metrics.searchVisibility;

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
                  e.category,
                  style: TextStyle(fontSize: 12, color: AppColors.textPrimary(context)))),
                Text(loc.t("proSearchCount", {"count": e.searchCount.toString()}), style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context))),
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
