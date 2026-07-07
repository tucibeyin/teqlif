import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import '../config/app_colors.dart';
import '../config/theme.dart';
import '../l10n/app_localizations.dart';
import '../services/storage_service.dart';

Future<Map<String, dynamic>> _fetchBestStreamTime() async {
  final token = await StorageService.getToken();
  final resp = await http.get(
    Uri.parse('$kBaseUrl/analytics/pro/best-stream-time'),
    headers: {'Authorization': 'Bearer $token'},
  );
  if (resp.statusCode == 200) return jsonDecode(resp.body) as Map<String, dynamic>;
  throw Exception('Veri alınamadı');
}

Future<List<dynamic>> _fetchConversionBreakdown() async {
  final token = await StorageService.getToken();
  final resp = await http.get(
    Uri.parse('$kBaseUrl/analytics/pro/conversion-breakdown'),
    headers: {'Authorization': 'Bearer $token'},
  );
  if (resp.statusCode == 200) return jsonDecode(resp.body) as List;
  throw Exception('Veri alınamadı');
}

// ── En İyi Yayın Saati ────────────────────────────────────────────────────

class BestStreamTimeScreen extends StatefulWidget {
  final bool isEmbedded;
  const BestStreamTimeScreen({super.key, this.isEmbedded = false});

  @override
  State<BestStreamTimeScreen> createState() => _BestStreamTimeScreenState();
}

class _BestStreamTimeScreenState extends State<BestStreamTimeScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _hasError = false;
  bool _showAllSlots = false;
  static const int _kMax = 5;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _hasError = false; });
    try {
      final d = await _fetchBestStreamTime();
      if (mounted) setState(() { _data = d; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _hasError = true; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final content = _loading
          ? const Center(child: CircularProgressIndicator())
          : _hasError
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.wifi_off_outlined, size: 48, color: AppColors.textSecondary(context)),
                      const SizedBox(height: 12),
                      Text(l.proLoadError, style: TextStyle(color: AppColors.textSecondary(context))),
                      const SizedBox(height: 16),
                      FilledButton(onPressed: _load, child: Text(l.btnRetry)),
                    ],
                  ),
                )
              : _buildContent(context);

    if (widget.isEmbedded) {
      return content;
    }

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        title: Text(l.proToolBestTimeTitle),
        backgroundColor: AppColors.bg(context),
        elevation: 0,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: content,
    );
  }

  Widget _buildContent(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final slots = (_data!['slots'] as List? ?? []);
    final recommendation = _data!['recommendation'] as String? ?? '';

    return ListView(shrinkWrap: widget.isEmbedded, physics: widget.isEmbedded ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.all(16),
      children: [
        if (recommendation.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Text('🎯', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    recommendation,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        if (slots.isEmpty)
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 40),
                Icon(Icons.schedule_outlined, size: 52, color: AppColors.textTertiary(context)),
                const SizedBox(height: 12),
                Text(l.bestTimeNoData, style: TextStyle(color: AppColors.textSecondary(context), fontSize: 15)),
                const SizedBox(height: 4),
                Text(l.bestTimeNoDataHint, style: TextStyle(color: AppColors.textTertiary(context), fontSize: 13)),
              ],
            ),
          )
        else ...[
          Text(
            l.bestTimeSlotsHeader,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary(context)),
          ),
          const SizedBox(height: 12),
          ...(_showAllSlots ? slots : slots.take(_kMax).toList()).asMap().entries.map((e) {
            final i = e.key;
            final s = e.value as Map<String, dynamic>;
            final conv = s['conversion_rate'] as num? ?? 0;
            final wins = s['total_wins'] as int? ?? 0;
            final count = s['stream_count'] as int? ?? 0;
            final isTop = i == 0;
            
            String dayStr = s['day'] as String? ?? '';
            String hourRangeStr = s['hour_range'] as String? ?? '';
            
            if (s.containsKey('utc_day_of_week') && s.containsKey('utc_hour_start')) {
              final utcDow = s['utc_day_of_week'] as int;
              final utcHour = s['utc_hour_start'] as int;
              final dtUtcStart = DateTime.utc(2023, 1, 1 + utcDow, utcHour);
              final dtUtcEnd = dtUtcStart.add(const Duration(hours: 3));
              
              final localStart = dtUtcStart.toLocal();
              final localEnd = dtUtcEnd.toLocal();
              
              dayStr = DateFormat('EEEE', Localizations.localeOf(context).languageCode).format(localStart);
              final timeFormat = DateFormat.Hm(Localizations.localeOf(context).languageCode);
              hourRangeStr = '${timeFormat.format(localStart)} - ${timeFormat.format(localEnd)}';
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isTop ? const Color(0xFF6366F1).withValues(alpha: 0.1) : AppColors.card(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isTop ? const Color(0xFF6366F1) : AppColors.border(context),
                  width: isTop ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dayStr,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isTop ? const Color(0xFF6366F1) : AppColors.textPrimary(context),
                        ),
                      ),
                      Text(
                        hourRangeStr,
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context)),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '%${conv.toStringAsFixed(1)}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF10B981)),
                      ),
                      Text(
                        l.bestTimeSlotStats(wins, count),
                        style: TextStyle(fontSize: 11, color: AppColors.textSecondary(context)),
                      ),
                    ],
                  ),
                  if (isTop) const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Text('🏆', style: TextStyle(fontSize: 18)),
                  ),
                ],
              ),
            );
          }),
          if (slots.length > _kMax)
            GestureDetector(
              onTap: () => setState(() => _showAllSlots = !_showAllSlots),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _showAllSlots ? l.proShowLess : l.proShowAll(slots.length - _kMax),
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary(context)),
                    ),
                    const SizedBox(width: 4),
                    Icon(_showAllSlots ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        size: 16, color: AppColors.textSecondary(context)),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}

// ── Dönüşüm Analizi ────────────────────────────────────────────────────────

class ConversionBreakdownScreen extends StatefulWidget {
  final bool isEmbedded;
  const ConversionBreakdownScreen({super.key, this.isEmbedded = false});

  @override
  State<ConversionBreakdownScreen> createState() => _ConversionBreakdownScreenState();
}

class _ConversionBreakdownScreenState extends State<ConversionBreakdownScreen> {
  List<dynamic> _data = [];
  bool _loading = true;
  bool _hasError = false;
  bool _showAll = false;
  static const int _kMax = 5;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _hasError = false; });
    try {
      final d = await _fetchConversionBreakdown();
      if (mounted) setState(() { _data = d; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _hasError = true; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final content = _loading
          ? const Center(child: CircularProgressIndicator())
          : _hasError
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.wifi_off_outlined, size: 48, color: AppColors.textSecondary(context)),
                      const SizedBox(height: 12),
                      Text(l.proLoadError, style: TextStyle(color: AppColors.textSecondary(context))),
                      const SizedBox(height: 16),
                      FilledButton(onPressed: _load, child: Text(l.btnRetry)),
                    ],
                  ),
                )
              : _buildContent(context, l);

    if (widget.isEmbedded) {
      return content;
    }

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        title: Text(l.proToolConversionTitle),
        backgroundColor: AppColors.bg(context),
        elevation: 0,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: content,
    );
  }

  Widget _buildContent(BuildContext context, AppLocalizations l) {
    if (_data.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.pie_chart_outline, size: 52, color: AppColors.textTertiary(context)),
            const SizedBox(height: 12),
            Text(l.conversionNoData, style: TextStyle(color: AppColors.textSecondary(context), fontSize: 15)),
            const SizedBox(height: 4),
            Text(l.conversionNoDataHint, style: TextStyle(color: AppColors.textTertiary(context), fontSize: 12)),
          ],
        ),
      );
    }

    final visible = _showAll ? _data : _data.take(_kMax).toList();
    final maxConv = (_data.map((r) => (r['conversion_rate'] as num? ?? 0).toDouble()).reduce((a, b) => a > b ? a : b)).toDouble();

    return ListView(shrinkWrap: widget.isEmbedded, physics: widget.isEmbedded ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.all(16),
      children: [
        Text(l.conversionSectionHeader,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary(context))),
        const SizedBox(height: 4),
        Text(l.conversionCategoryCount(_data.length),
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context))),
        const SizedBox(height: 16),
        ...visible.map((row) {
          final r = row as Map<String, dynamic>;
          final conv = (r['conversion_rate'] as num? ?? 0).toDouble();
          final barWidth = maxConv > 0 ? conv / maxConv : 0.0;
          final won = r['won_auctions'] as int? ?? 0;
          final total = r['total_auctions'] as int? ?? 0;
          final avgPrice = (r['avg_final_price'] as num? ?? 0).toDouble();

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.card(context),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4)],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(r['label'] as String? ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary(context))),
                    const Spacer(),
                    Text('%${conv.toStringAsFixed(1)}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: conv >= 50 ? const Color(0xFF10B981) : conv >= 25 ? kPrimary : const Color(0xFFF59E0B),
                        )),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: barWidth,
                    backgroundColor: AppColors.border(context),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      conv >= 50 ? const Color(0xFF10B981) : conv >= 25 ? kPrimary : const Color(0xFFF59E0B),
                    ),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(l.conversionCategorySales(won, total), style: TextStyle(fontSize: 11, color: AppColors.textSecondary(context))),
                    const Spacer(),
                    if (avgPrice > 0)
                      Text(l.conversionAvgPrice(NumberFormat('#,##0', 'tr_TR').format(avgPrice)),
                          style: TextStyle(fontSize: 11, color: AppColors.textSecondary(context))),
                  ],
                ),
              ],
            ),
          );
        }),
        if (_data.length > _kMax)
          GestureDetector(
            onTap: () => setState(() => _showAll = !_showAll),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _showAll ? l.proShowLess : l.proShowAll(_data.length - _kMax),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary(context)),
                  ),
                  const SizedBox(width: 4),
                  Icon(_showAll ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      size: 16, color: AppColors.textSecondary(context)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
