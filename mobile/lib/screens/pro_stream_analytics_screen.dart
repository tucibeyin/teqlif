import 'dart:convert';
import 'package:flutter/material.dart';
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
  const BestStreamTimeScreen({super.key});

  @override
  State<BestStreamTimeScreen> createState() => _BestStreamTimeScreenState();
}

class _BestStreamTimeScreenState extends State<BestStreamTimeScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await _fetchBestStreamTime();
      if (mounted) setState(() { _data = d; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.proToolBestTimeTitle),
        backgroundColor: AppColors.bg(context),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Hata: $_error', style: const TextStyle(color: Colors.red)))
              : _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final slots = (_data!['slots'] as List? ?? []);
    final recommendation = _data!['recommendation'] as String? ?? '';

    return ListView(
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
                const Icon(Icons.schedule_outlined, size: 52, color: Color(0xFFD1D5DB)),
                const SizedBox(height: 12),
                Text(AppLocalizations.of(context)!.bestTimeNoData, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 15)),
                const SizedBox(height: 4),
                Text(AppLocalizations.of(context)!.bestTimeNoDataHint, style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13)),
              ],
            ),
          )
        else ...[
          Text(
            AppLocalizations.of(context)!.bestTimeSlotsHeader,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary(context)),
          ),
          const SizedBox(height: 12),
          ...slots.asMap().entries.map((e) {
            final i = e.key;
            final s = e.value as Map<String, dynamic>;
            final conv = s['conversion_rate'] as num? ?? 0;
            final wins = s['total_wins'] as int? ?? 0;
            final count = s['stream_count'] as int? ?? 0;
            final isTop = i == 0;
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
                        s['day'] as String? ?? '',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isTop ? const Color(0xFF6366F1) : AppColors.textPrimary(context),
                        ),
                      ),
                      Text(
                        s['hour_range'] as String? ?? '',
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
                        AppLocalizations.of(context)!.bestTimeSlotStats(wins, count),
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
        ],
      ],
    );
  }
}

// ── Dönüşüm Analizi ────────────────────────────────────────────────────────

class ConversionBreakdownScreen extends StatefulWidget {
  const ConversionBreakdownScreen({super.key});

  @override
  State<ConversionBreakdownScreen> createState() => _ConversionBreakdownScreenState();
}

class _ConversionBreakdownScreenState extends State<ConversionBreakdownScreen> {
  List<dynamic> _data = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await _fetchConversionBreakdown();
      if (mounted) setState(() { _data = d; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.proToolConversionTitle),
        backgroundColor: AppColors.bg(context),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Hata: $_error', style: const TextStyle(color: Colors.red)))
              : _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_data.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.pie_chart_outline, size: 52, color: Color(0xFFD1D5DB)),
            const SizedBox(height: 12),
            Text(AppLocalizations.of(context)!.conversionNoData, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 15)),
            const SizedBox(height: 4),
            Text(AppLocalizations.of(context)!.conversionNoDataHint, style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12)),
          ],
        ),
      );
    }

    final maxConv = (_data.map((r) => (r['conversion_rate'] as num? ?? 0).toDouble()).reduce((a, b) => a > b ? a : b)).toDouble();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(AppLocalizations.of(context)!.conversionSectionHeader,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary(context))),
        const SizedBox(height: 4),
        Text(AppLocalizations.of(context)!.conversionCategoryCount(_data.length),
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context))),
        const SizedBox(height: 16),
        ..._data.map((row) {
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
                    Text(AppLocalizations.of(context)!.conversionCategorySales(won, total), style: TextStyle(fontSize: 11, color: AppColors.textSecondary(context))),
                    const Spacer(),
                    if (avgPrice > 0)
                      Text(AppLocalizations.of(context)!.conversionAvgPrice(avgPrice.toStringAsFixed(0)),
                          style: TextStyle(fontSize: 11, color: AppColors.textSecondary(context))),
                  ],
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
