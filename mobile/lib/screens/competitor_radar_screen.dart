import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import '../config/app_colors.dart';
import '../config/theme.dart';
import '../l10n/app_localizations.dart';
import '../services/analytics_service.dart';
import '../services/category_service.dart';
import '../services/storage_service.dart';
import 'package:cached_network_image/cached_network_image.dart';

class CompetitorRadarScreen extends StatefulWidget {
  final bool isEmbedded;
  const CompetitorRadarScreen({super.key, this.isEmbedded = false});

  @override
  State<CompetitorRadarScreen> createState() => _CompetitorRadarScreenState();
}

class _CompetitorRadarScreenState extends State<CompetitorRadarScreen> {
  Map<String, dynamic>? _selectedListing;
  Map<String, dynamic>? _radarData;
  Map<String, dynamic>? _velocityData;
  bool _loadingData = false;

  final TextEditingController _searchCtrl = TextEditingController();
  String _listingQuery = '';
  DateTimeRange? _dateRange;
  Timer? _searchDebounce;
  String? _categoryFilter;
  List<(String, String)>? _categories;

  List<Map<String, dynamic>> _listings = [];
  bool _listingsLoading = true;

  @override
  void initState() {
    super.initState();
    _loadListings();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_categories == null) {
      CategoryService.getCategories(locale: Localizations.localeOf(context).languageCode)
          .then((cats) { if (mounted) setState(() => _categories = cats); });
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _fetchListingsPage(int offset) async {
    final token = await StorageService.getToken();
    if (token == null) return [];
    var url = '$kBaseUrl/listings/my?limit=50&offset=$offset&active=true';
    if (_dateRange != null) {
      url += '&start_date=${_dateRange!.start.toIso8601String().substring(0, 10)}';
      url += '&end_date=${_dateRange!.end.toIso8601String().substring(0, 10)}';
    }
    final resp = await http.get(Uri.parse(url), headers: {'Authorization': 'Bearer $token'});
    if (resp.statusCode == 200) {
      return (jsonDecode(resp.body) as List).cast<Map<String, dynamic>>();
    }
    return [];
  }

  String _fmtDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';

  Widget _buildDateRangePicker(AppLocalizations l) {
    final hasRange = _dateRange != null;
    return InkWell(
      onTap: () async {
        final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
          initialDateRange: _dateRange,
          locale: Localizations.localeOf(context),
        );
        if (picked != null) { setState(() => _dateRange = picked); _loadListings(); }
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: hasRange ? kPrimary : AppColors.border(context)),
          borderRadius: BorderRadius.circular(8),
          color: hasRange ? kPrimary.withValues(alpha: 0.08) : null,
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined, size: 16,
                color: hasRange ? kPrimary : AppColors.textSecondary(context)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hasRange
                    ? '${_fmtDate(_dateRange!.start)} – ${_fmtDate(_dateRange!.end)}'
                    : l.filterSelectDate,
                style: TextStyle(fontSize: 13,
                    color: hasRange ? kPrimary : AppColors.textSecondary(context)),
              ),
            ),
            if (hasRange)
              GestureDetector(
                onTap: () { setState(() => _dateRange = null); _loadListings(); },
                child: Icon(Icons.close, size: 16, color: kPrimary),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryChips() {
    final cats = _categories;
    if (cats == null || cats.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _chip('Tümü', _categoryFilter == null, () => setState(() => _categoryFilter = null)),
          ...cats.map((c) => _chip(c.$2, _categoryFilter == c.$1,
              () => setState(() => _categoryFilter = _categoryFilter == c.$1 ? null : c.$1))),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? kPrimary : AppColors.card(context),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? kPrimary : AppColors.border(context)),
          ),
          child: Text(label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? Colors.white : AppColors.textPrimary(context),
              )),
        ),
      ),
    );
  }

  Future<void> _loadData() async {
    final listing = _selectedListing;
    if (listing == null) return;
    final id = listing['id'] as int;
    final category = listing['category'] as String? ?? '';
    setState(() {
      _loadingData = true;
      _radarData = null;
      _velocityData = null;
    });
    final results = await Future.wait([
      AnalyticsService.competitorRadar(id),
      AnalyticsService.categoryVelocity(category, listingId: id),
    ]);
    if (mounted) {
      setState(() {
        _radarData = results[0];
        _velocityData = results[1];
        _loadingData = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredListings {
    var result = _listings;
    if (_listingQuery.isNotEmpty) {
      final q = _listingQuery.toLowerCase();
      result = result.where((l) => (l['title'] as String? ?? '').toLowerCase().contains(q)).toList();
    }
    if (_categoryFilter != null) {
      result = result.where((l) => l['category'] == _categoryFilter).toList();
    }
    return result;
  }

  Future<void> _loadListings() async {
    if (mounted) setState(() => _listingsLoading = true);
    final results = await _fetchListingsPage(0);
    if (!mounted) return;
    final prevId = _selectedListing?['id'];
    final stillHere = prevId != null ? results.any((r) => r['id'] == prevId) : false;
    setState(() {
      _listings = results;
      _listingsLoading = false;
      if (!stillHere) _selectedListing = results.isNotEmpty ? results.first : null;
    });
    if (_selectedListing != null) _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final bodyContent = RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        shrinkWrap: widget.isEmbedded, 
        physics: widget.isEmbedded ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context)!.searchHintTextListing,
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _listingQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _listingQuery = '');
                        },
                      )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: (v) {
                _searchDebounce?.cancel();
                _searchDebounce = Timer(const Duration(milliseconds: 400), () {
                  setState(() => _listingQuery = v.trim());
                });
              },
            ),
          ),
          _buildDateRangePicker(l),
          const SizedBox(height: 8),
          _buildCategoryChips(),
          const SizedBox(height: 8),
          _buildHorizontalCarousel(l),
          const SizedBox(height: 20),
          if (_loadingData)
            const _RadarSkeleton()
          else if (_selectedListing != null) ...[
            if (_radarData != null)
              _RadarSection(
                data: _radarData!,
                listingTitle: _selectedListing!['title'] as String? ?? '',
              ),
            if (_velocityData != null) ...[
              const SizedBox(height: 16),
              _VelocitySection(data: _velocityData!),
            ],
            if (_radarData == null && _velocityData == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Center(
                  child: Text(
                    l.proLoadError,
                    style: TextStyle(color: AppColors.textSecondary(context)),
                  ),
                ),
              ),
          ],
        ],
      ),
    );

    if (widget.isEmbedded) {
      return bodyContent;
    }

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        title: Text(l.radarScreenTitle),
        backgroundColor: AppColors.bg(context),
        elevation: 0,
        actions: [
          if (_selectedListing != null && !_loadingData)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadData,
            ),
        ],
      ),
      body: bodyContent,
    );
  }

  Widget _buildHorizontalCarousel(AppLocalizations l) {
    if (_listingsLoading) {
      return const SizedBox(
        height: 112,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final items = _filteredListings;
    if (items.isEmpty) return _emptyState();
    return SizedBox(
      height: 112,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        itemBuilder: (ctx, i) {
          final item = items[i];
          final isSelected = _selectedListing != null && item['id'] == _selectedListing!['id'];
          final imageUrls = item['image_urls'] as List? ?? [];
          final rawImg = imageUrls.isNotEmpty ? imageUrls.first as String? : item['image_url'] as String?;
          final imageUrl = rawImg != null ? imgUrl(rawImg) : null;
          return GestureDetector(
            onTap: () {
              if (!isSelected) {
                setState(() => _selectedListing = item);
                _loadData();
              }
            },
            child: Container(
              width: 128,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: AppColors.card(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? const Color(0xFF6366F1) : AppColors.border(context),
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    imageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(color: AppColors.border(context)),
                            errorWidget: (_, __, ___) => Container(
                              color: AppColors.border(context),
                              child: Icon(Icons.image_not_supported_outlined,
                                  color: AppColors.textSecondary(context)),
                            ),
                          )
                        : Container(
                            color: AppColors.border(context),
                            child: Icon(Icons.image_not_supported_outlined,
                                color: AppColors.textSecondary(context)),
                          ),
                    Positioned(
                      bottom: 0, left: 0, right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter, end: Alignment.topCenter,
                            colors: [Colors.black.withValues(alpha: 0.80), Colors.transparent],
                          ),
                        ),
                        child: Text(
                          item['title'] as String? ?? '—',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (isSelected)
                      Positioned(
                        top: 6, right: 6,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(color: Color(0xFF6366F1), shape: BoxShape.circle),
                          child: const Icon(Icons.check, color: Colors.white, size: 12),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined, size: 56, color: AppColors.textSecondary(context)),
          const SizedBox(height: 12),
          Text(
            AppLocalizations.of(context)!.radarNoActiveListing,
            style: TextStyle(fontSize: 15, color: AppColors.textSecondary(context)),
          ),
          const SizedBox(height: 6),
          Text(
            AppLocalizations.of(context)!.radarNeedActiveListing,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context)),
          ),
        ],
      ),
    );
  }
}

// ── Rakip Fiyat Radarı Bölümü ─────────────────────────────────────────────────

class _RadarSection extends StatelessWidget {
  final Map<String, dynamic> data;
  final String listingTitle;

  const _RadarSection({required this.data, required this.listingTitle});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final signal = data['signal'] as String? ?? '';

    if (signal == 'no_price' || signal == 'no_data') {
      return _SectionCard(
        icon: Icons.radar,
        iconColor: const Color(0xFF6366F1),
        title: AppLocalizations.of(context)!.competitorRadarTitle,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: Text(
              signal == 'no_price'
                  ? AppLocalizations.of(context)!.radarNoPriceSet
                  : AppLocalizations.of(context)!.radarNoCompetitorData,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary(context)),
            ),
          ),
        ),
      );
    }

    final myPrice = (data['my_price'] as num?)?.toDouble() ?? 0;
    final avgPrice = (data['avg_price'] as num?)?.toDouble() ?? 0;
    final minPrice = (data['min_price'] as num?)?.toDouble() ?? 0;
    final maxPrice = (data['max_price'] as num?)?.toDouble() ?? 0;
    final diffPct = (data['diff_pct'] as num?)?.toDouble() ?? 0;
    final pctRank = (data['pct_rank'] as num?)?.toInt() ?? 0;
    final suggestedPrice = (data['suggested_price'] as num?)?.toDouble() ?? 0;
    final competitorCount = data['competitor_count'] as int? ?? 0;
    final signalDetail = data['signal_detail'] as String? ?? '';
    final competitors = (data['competitors'] as List? ?? []).cast<Map<String, dynamic>>();

    final Color signalColor;
    final IconData signalIcon;
    final String signalLabel;
    switch (signal) {
      case 'pahalı':
        signalColor = const Color(0xFFEF4444);
        signalIcon = Icons.trending_up;
        signalLabel = l.radarExpensive;
        break;
      case 'ucuz':
        signalColor = const Color(0xFF06B6D4);
        signalIcon = Icons.trending_down;
        signalLabel = l.radarCheapLabel;
        break;
      case 'uygun':
      default:
        signalColor = const Color(0xFF22C55E);
        signalIcon = Icons.check_circle_outline;
        signalLabel = l.radarFairLabel;
        break;
    }

    return _SectionCard(
      icon: Icons.radar,
      iconColor: const Color(0xFF6366F1),
      title: AppLocalizations.of(context)!.competitorRadarTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sinyal chip + fiyat karşılaştırması
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: signalColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: signalColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(signalIcon, size: 16, color: signalColor),
                    const SizedBox(width: 6),
                    Text(
                      signalLabel,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: signalColor),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  signalDetail,
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Fiyat metrikleri
          Row(
            children: [
              _PriceMetric(label: AppLocalizations.of(context)!.competitorRadarYourPrice, value: myPrice, color: signalColor),
              const SizedBox(width: 10),
              _PriceMetric(label: AppLocalizations.of(context)!.competitorRadarAvg, value: avgPrice, color: AppColors.textPrimary(context)),
              const SizedBox(width: 10),
              _PriceMetric(label: AppLocalizations.of(context)!.competitorRadarSuggested, value: suggestedPrice, color: const Color(0xFF22C55E)),
            ],
          ),
          if (signal != 'uygun' && suggestedPrice > 0) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () {
                final l = AppLocalizations.of(context)!;
                Clipboard.setData(ClipboardData(text: suggestedPrice.toStringAsFixed(0)));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(l.radarSuggestedCopied(NumberFormat('#,##0', 'tr_TR').format(suggestedPrice))),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ));
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF22C55E).withValues(alpha: 0.25)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.content_copy_outlined, size: 14, color: Color(0xFF22C55E)),
                    const SizedBox(width: 6),
                    Text(
                      AppLocalizations.of(context)!.radarCopyBtn(NumberFormat('#,##0', 'tr_TR').format(suggestedPrice)),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF22C55E)),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),

          // Fiyat aralığı çubuğu
          _PriceRangeBar(
            myPrice: myPrice,
            minPrice: minPrice,
            maxPrice: maxPrice,
            avgPrice: avgPrice,
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l.priceMinLabel(_fmtPrice(minPrice)), style: TextStyle(fontSize: 10, color: AppColors.textSecondary(context))),
              Text(l.priceMaxLabel(_fmtPrice(maxPrice)), style: TextStyle(fontSize: 10, color: AppColors.textSecondary(context))),
            ],
          ),
          const SizedBox(height: 14),

          // Yüzdelik + fark
          Row(
            children: [
              Expanded(
                child: _StatChip(
                  label: AppLocalizations.of(context)!.competitorRadarPercentile,
                  value: '%$pctRank',
                  sub: l.radarExpensiveThanCompetitor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatChip(
                  label: AppLocalizations.of(context)!.competitorRadarDifference,
                  value: '${diffPct >= 0 ? '+' : ''}${diffPct.toStringAsFixed(1)}%',
                  sub: l.radarVsAvgPrice,
                  valueColor: diffPct > 0 ? const Color(0xFFEF4444) : const Color(0xFF22C55E),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatChip(
                  label: AppLocalizations.of(context)!.competitorRadarCompetitor,
                  value: '$competitorCount',
                  sub: l.radarActiveListings,
                ),
              ),
            ],
          ),

          // Rakipler listesi
          if (competitors.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              l.radarCloseCompetitors,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary(context)),
            ),
            const SizedBox(height: 8),
            ...competitors.take(5).map((c) {
              final cPrice = (c['price'] as num).toDouble();
              final isMore = cPrice > myPrice;
              final diff = ((cPrice - myPrice) / myPrice * 100).abs().toStringAsFixed(0);
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        c['title'] as String? ?? '—',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: AppColors.textPrimary(context)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_fmtPrice(cPrice)} ₺',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isMore
                            ? const Color(0xFF22C55E)
                            : const Color(0xFFEF4444),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '(${isMore ? '+' : '-'}$diff%)',
                      style: TextStyle(
                        fontSize: 10,
                        color: isMore
                            ? const Color(0xFF22C55E)
                            : const Color(0xFFEF4444),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  String _fmtPrice(double v) => NumberFormat('#,##0', 'tr_TR').format(v);
}

// ── Satış Hızı Bölümü ─────────────────────────────────────────────────────────

class _VelocitySection extends StatelessWidget {
  final Map<String, dynamic> data;

  const _VelocitySection({required this.data});

  @override
  Widget build(BuildContext context) {
    final category = data['category'] as String? ?? '—';
    final totalSold = data['total_sold_90d'] as int? ?? 0;
    final avgDays = (data['avg_days_to_sell'] as num?)?.toDouble();
    final minDays = (data['min_days_to_sell'] as num?)?.toDouble();
    final maxDays = (data['max_days_to_sell'] as num?)?.toDouble();
    final avgSoldPrice = (data['avg_sold_price'] as num?)?.toDouble();
    final sweetMin = (data['sweet_spot_min'] as num?)?.toDouble();
    final sweetMax = (data['sweet_spot_max'] as num?)?.toDouble();
    final activeCount = data['active_competitor_count'] as int? ?? 0;
    final tip = data['tip'] as String?;
    final sensitivity = (data['price_sensitivity'] as List? ?? []).cast<Map<String, dynamic>>();

    return _SectionCard(
      icon: Icons.speed_outlined,
      iconColor: const Color(0xFF10B981),
      title: AppLocalizations.of(context)!.competitorRadarSalesSpeed,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (totalSold == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                AppLocalizations.of(context)!.radarNo90DayData,
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary(context)),
              ),
            )
          else ...[
            // Ortalama süre
            if (avgDays != null) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    avgDays.toStringAsFixed(1),
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary(context),
                      height: 1,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4, left: 6),
                    child: Text(
                      AppLocalizations.of(context)!.radarDaysAvg,
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary(context)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              if (minDays != null && maxDays != null)
                Text(
                  AppLocalizations.of(context)!.radarDayRange(minDays.toStringAsFixed(0), maxDays.toStringAsFixed(0)),
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context)),
                ),
              const SizedBox(height: 14),
            ],

            // Metrik satırı
            Row(
              children: [
                Expanded(
                  child: _StatChip(
                    label: AppLocalizations.of(context)!.competitorRadarSold,
                    value: '$totalSold',
                    sub: AppLocalizations.of(context)!.radarIn90Days,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatChip(
                    label: AppLocalizations.of(context)!.competitorRadarActive,
                    value: '$activeCount',
                    sub: AppLocalizations.of(context)!.radarRightNow,
                  ),
                ),
                if (avgSoldPrice != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: _StatChip(
                      label: AppLocalizations.of(context)!.competitorRadarSalePrice,
                      value: '${_fmtPrice(avgSoldPrice)} ₺',
                      sub: AppLocalizations.of(context)!.radarAverage,
                    ),
                  ),
                ],
              ],
            ),

            // Sweet spot
            if (sweetMin != null && sweetMax != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome, size: 18, color: Color(0xFF10B981)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.of(context)!.radarSweetSpotLabel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSecondary(context),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_fmtPrice(sweetMin)} ₺ – ${_fmtPrice(sweetMax)} ₺',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF10B981),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Fiyat hassasiyeti
            if (sensitivity.length == 2) ...[
              const SizedBox(height: 14),
              Text(
                AppLocalizations.of(context)!.radarPriceSensitivity,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary(context)),
              ),
              const SizedBox(height: 8),
              ...sensitivity.map((s) {
                final bucket = s['bucket'] as String;
                final days = (s['avg_days'] as num).toDouble();
                final count = s['count'] as int;
                final color = bucket == 'ucuz' ? const Color(0xFF06B6D4) : const Color(0xFFF59E0B);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 8, height: 8,
                        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        bucket == 'ucuz' ? AppLocalizations.of(context)!.radarAffordable : AppLocalizations.of(context)!.radarExpensivePrice,
                        style: TextStyle(fontSize: 12, color: AppColors.textPrimary(context)),
                      ),
                      const Spacer(),
                      Text(
                        AppLocalizations.of(context)!.radarDaySaleStat(days.toStringAsFixed(1), count),
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],

          // Öneri
          if (tip != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_outline, size: 16, color: Color(0xFF6366F1)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tip,
                      style: TextStyle(fontSize: 12, color: AppColors.textPrimary(context), height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _fmtPrice(double v) => NumberFormat('#,##0', 'tr_TR').format(v);
}

// ── Skeleton Loading ──────────────────────────────────────────────────────────

class _RadarSkeleton extends StatelessWidget {
  const _RadarSkeleton();

  @override
  Widget build(BuildContext context) {
    final base = AppColors.border(context);
    box(double h, {double? w, double r = 8}) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(r)),
        );
    card(Widget child) => Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: base),
          ),
          child: child,
        );
    return Column(
      children: [
        card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          box(14, w: 140),
          const SizedBox(height: 14),
          Row(children: [
            box(24, w: 80, r: 6), const SizedBox(width: 10), Expanded(child: box(14)),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: box(60, r: 10)), const SizedBox(width: 10),
            Expanded(child: box(60, r: 10)), const SizedBox(width: 10),
            Expanded(child: box(60, r: 10)),
          ]),
          const SizedBox(height: 14),
          box(10, r: 4),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: box(64, r: 10)), const SizedBox(width: 8),
            Expanded(child: box(64, r: 10)), const SizedBox(width: 8),
            Expanded(child: box(64, r: 10)),
          ]),
        ])),
        card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          box(14, w: 160),
          const SizedBox(height: 14),
          box(48, w: 100, r: 4),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: box(64, r: 10)), const SizedBox(width: 8),
            Expanded(child: box(64, r: 10)), const SizedBox(width: 8),
            Expanded(child: box(64, r: 10)),
          ]),
        ])),
      ],
    );
  }
}

// ── Ortak Widgets ─────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget child;

  const _SectionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _PriceMetric extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const _PriceMetric({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final fmt = '${NumberFormat('#,##0', 'tr_TR').format(value)} ₺';
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: AppColors.textSecondary(context))),
          const SizedBox(height: 2),
          Text(fmt, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}

class _PriceRangeBar extends StatelessWidget {
  final double myPrice, minPrice, maxPrice, avgPrice;

  const _PriceRangeBar({
    required this.myPrice,
    required this.minPrice,
    required this.maxPrice,
    required this.avgPrice,
  });

  @override
  Widget build(BuildContext context) {
    final range = maxPrice - minPrice;
    if (range <= 0) return const SizedBox.shrink();
    final myPos = ((myPrice - minPrice) / range).clamp(0.0, 1.0);
    final avgPos = ((avgPrice - minPrice) / range).clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        return SizedBox(
          height: 28,
          child: Stack(
            children: [
              // Track
              Positioned(
                left: 0, right: 0, top: 12,
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Avg marker
              Positioned(
                left: (avgPos * w - 1).clamp(0, w - 2), top: 8,
                child: Container(
                  width: 2, height: 12,
                  color: AppColors.textSecondary(context).withValues(alpha: 0.5),
                ),
              ),
              // My price marker
              Positioned(
                left: (myPos * w - 7).clamp(0, w - 14), top: 2,
                child: Container(
                  width: 14, height: 14,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF6366F1), width: 2.5),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  final Color? valueColor;

  const _StatChip({required this.label, required this.value, required this.sub, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.bg(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: AppColors.textSecondary(context))),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: valueColor ?? AppColors.textPrimary(context),
            ),
          ),
          Text(sub, style: TextStyle(fontSize: 9, color: AppColors.textSecondary(context))),
        ],
      ),
    );
  }
}
