import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import '../config/app_colors.dart';
import '../services/analytics_service.dart';
import '../services/storage_service.dart';

class CompetitorRadarScreen extends StatefulWidget {
  const CompetitorRadarScreen({super.key});

  @override
  State<CompetitorRadarScreen> createState() => _CompetitorRadarScreenState();
}

class _CompetitorRadarScreenState extends State<CompetitorRadarScreen> {
  List<Map<String, dynamic>> _listings = [];
  Map<String, dynamic>? _selectedListing;
  Map<String, dynamic>? _radarData;
  Map<String, dynamic>? _velocityData;
  bool _loadingListings = true;
  bool _loadingData = false;

  @override
  void initState() {
    super.initState();
    _loadListings();
  }

  Future<void> _loadListings() async {
    try {
      final token = await StorageService.getToken();
      if (token == null) {
        if (mounted) setState(() => _loadingListings = false);
        return;
      }
      final resp = await http.get(
        Uri.parse('$kBaseUrl/listings/my'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200 && mounted) {
        final all = (jsonDecode(resp.body) as List).cast<Map<String, dynamic>>();
        final active = all.where((l) => l['is_active'] == true || l['status'] == 'active').toList();
        setState(() {
          _listings = active;
          _loadingListings = false;
          if (_listings.isNotEmpty) {
            _selectedListing = _listings.first;
            _loadData();
          }
        });
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingListings = false);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        title: const Text('Rakip Radarı & Satış Hızı'),
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
      body: _loadingListings
          ? const Center(child: CircularProgressIndicator())
          : _listings.isEmpty
              ? _emptyState()
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      _ListingPicker(
                        listings: _listings,
                        selected: _selectedListing!,
                        onChanged: (l) {
                          setState(() => _selectedListing = l);
                          _loadData();
                        },
                      ),
                      const SizedBox(height: 20),
                      if (_loadingData)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(48),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      else ...[
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
                                'Veri yüklenemedi.',
                                style: TextStyle(color: AppColors.textSecondary(context)),
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
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
            'Aktif ilanın bulunamadı.',
            style: TextStyle(fontSize: 15, color: AppColors.textSecondary(context)),
          ),
          const SizedBox(height: 6),
          Text(
            'Rakip radarı için en az 1 aktif ilana ihtiyaç var.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context)),
          ),
        ],
      ),
    );
  }
}

// ── İlan Seçici ───────────────────────────────────────────────────────────────

class _ListingPicker extends StatelessWidget {
  final List<Map<String, dynamic>> listings;
  final Map<String, dynamic> selected;
  final ValueChanged<Map<String, dynamic>> onChanged;

  const _ListingPicker({
    required this.listings,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<Map<String, dynamic>>(
          isExpanded: true,
          value: selected,
          dropdownColor: AppColors.card(context),
          style: TextStyle(fontSize: 14, color: AppColors.textPrimary(context)),
          icon: Icon(Icons.keyboard_arrow_down, color: AppColors.textSecondary(context)),
          items: listings.map((l) {
            final price = l['price'];
            final priceStr = price != null ? ' · ${_fmt(price)} ₺' : '';
            return DropdownMenuItem(
              value: l,
              child: Text(
                '${l['title'] ?? '—'}$priceStr',
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
          onChanged: (v) { if (v != null) onChanged(v); },
        ),
      ),
    );
  }

  String _fmt(dynamic v) {
    final n = (v as num).toDouble();
    if (n >= 1000) {
      return '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}K';
    }
    return n.toStringAsFixed(0);
  }
}

// ── Rakip Fiyat Radarı Bölümü ─────────────────────────────────────────────────

class _RadarSection extends StatelessWidget {
  final Map<String, dynamic> data;
  final String listingTitle;

  const _RadarSection({required this.data, required this.listingTitle});

  @override
  Widget build(BuildContext context) {
    final signal = data['signal'] as String? ?? '';

    if (signal == 'no_price' || signal == 'no_data') {
      return _SectionCard(
        icon: Icons.radar,
        iconColor: const Color(0xFF6366F1),
        title: 'Rakip Fiyat Radarı',
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: Text(
              signal == 'no_price'
                  ? 'Bu ilana fiyat girilmemiş.'
                  : 'Bu kategori için yeterli rakip verisi yok.',
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
        signalLabel = 'Pahalı';
        break;
      case 'ucuz':
        signalColor = const Color(0xFF06B6D4);
        signalIcon = Icons.trending_down;
        signalLabel = 'Ucuz';
        break;
      default:
        signalColor = const Color(0xFF22C55E);
        signalIcon = Icons.check_circle_outline;
        signalLabel = 'Uygun';
    }

    return _SectionCard(
      icon: Icons.radar,
      iconColor: const Color(0xFF6366F1),
      title: 'Rakip Fiyat Radarı',
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
              _PriceMetric(
                label: 'Senin fiyatın',
                value: myPrice,
                color: signalColor,
              ),
              const SizedBox(width: 10),
              _PriceMetric(
                label: 'Rakip ort.',
                value: avgPrice,
                color: AppColors.textPrimary(context),
              ),
              const SizedBox(width: 10),
              _PriceMetric(
                label: 'Önerilen',
                value: suggestedPrice,
                color: const Color(0xFF22C55E),
              ),
            ],
          ),
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
              Text('${_fmtPrice(minPrice)} ₺ (min)', style: TextStyle(fontSize: 10, color: AppColors.textSecondary(context))),
              Text('${_fmtPrice(maxPrice)} ₺ (max)', style: TextStyle(fontSize: 10, color: AppColors.textSecondary(context))),
            ],
          ),
          const SizedBox(height: 14),

          // Yüzdelik + fark
          Row(
            children: [
              Expanded(
                child: _StatChip(
                  label: 'Yüzdelik',
                  value: '%$pctRank',
                  sub: 'rakipten pahalı',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatChip(
                  label: 'Fark',
                  value: '${diffPct >= 0 ? '+' : ''}${diffPct.toStringAsFixed(1)}%',
                  sub: 'ort. fiyattan',
                  valueColor: diffPct > 0 ? const Color(0xFFEF4444) : const Color(0xFF22C55E),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatChip(
                  label: 'Rakip',
                  value: '$competitorCount',
                  sub: 'aktif ilan',
                ),
              ),
            ],
          ),

          // Rakipler listesi
          if (competitors.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Yakın Rakipler',
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

  String _fmtPrice(double v) {
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}K';
    return v.toStringAsFixed(0);
  }
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
      title: 'Satış Hızı — $category',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (totalSold == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Son 90 günde bu kategoride satış verisi yok.',
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
                      'gün (ortalama)',
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary(context)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              if (minDays != null && maxDays != null)
                Text(
                  'Aralık: ${minDays.toStringAsFixed(0)} – ${maxDays.toStringAsFixed(0)} gün',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context)),
                ),
              const SizedBox(height: 14),
            ],

            // Metrik satırı
            Row(
              children: [
                Expanded(
                  child: _StatChip(
                    label: 'Satılan',
                    value: '$totalSold',
                    sub: '90 günde',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatChip(
                    label: 'Aktif Rakip',
                    value: '$activeCount',
                    sub: 'şu an',
                  ),
                ),
                if (avgSoldPrice != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: _StatChip(
                      label: 'Satış Fiyatı',
                      value: '${_fmtPrice(avgSoldPrice)} ₺',
                      sub: 'ortalama',
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
                            'En çok satılan fiyat aralığı',
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
                'Fiyat Hassasiyeti',
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
                        bucket == 'ucuz' ? 'Uygun fiyatlı' : 'Pahalı fiyatlı',
                        style: TextStyle(fontSize: 12, color: AppColors.textPrimary(context)),
                      ),
                      const Spacer(),
                      Text(
                        '${days.toStringAsFixed(1)} gün  ($count satış)',
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

  String _fmtPrice(double v) {
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}K';
    return v.toStringAsFixed(0);
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
    String fmt;
    if (value >= 1000) {
      fmt = '${(value / 1000).toStringAsFixed(value % 1000 == 0 ? 0 : 1)}K ₺';
    } else {
      fmt = '${value.toStringAsFixed(0)} ₺';
    }
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
