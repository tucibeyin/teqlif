import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../config/theme.dart';
import '../l10n/app_localizations.dart';
import '../services/analytics_service.dart';
import '../services/category_service.dart';

class DemandTrendsScreen extends StatefulWidget {
  const DemandTrendsScreen({super.key});

  @override
  State<DemandTrendsScreen> createState() => _DemandTrendsScreenState();
}

class _DemandTrendsScreenState extends State<DemandTrendsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _trends = [];
  List<(String, String)>? _categories;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_categories == null) {
      CategoryService.getCategories(locale: Localizations.localeOf(context).languageCode)
          .then((cats) { if (mounted) setState(() => _categories = cats); });
    }
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await AnalyticsService.demandTrends(weeks: 8);
      if (!mounted) return;
      if (data == null) {
        setState(() { _error = 'no_data'; _loading = false; });
        return;
      }
      final raw = (data['trends'] as List?) ?? [];
      setState(() {
        _trends = raw.cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() { _error = 'error'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.demandTrendsTitle),
        centerTitle: false,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : _error != null || _trends.isEmpty
              ? _Empty(l: l, onRetry: _load)
              : RefreshIndicator(
                  color: kPrimary,
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        l.demandTrendsSubtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary(context),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ..._trends.map((t) => _TrendCard(trend: t, l: l, categoryLabels: _categories)),
                    ],
                  ),
                ),
    );
  }
}

class _Empty extends StatelessWidget {
  final AppLocalizations l;
  final VoidCallback onRetry;
  const _Empty({required this.l, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bar_chart_outlined, size: 56, color: AppColors.textTertiary(context)),
          const SizedBox(height: 12),
          Text(l.demandTrendsEmptyLabel,
              style: TextStyle(fontSize: 15, color: AppColors.textSecondary(context))),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Yenile'),
          ),
        ],
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  final Map<String, dynamic> trend;
  final AppLocalizations l;
  final List<(String, String)>? categoryLabels;

  const _TrendCard({required this.trend, required this.l, this.categoryLabels});

  @override
  Widget build(BuildContext context) {
    final categoryKey = trend['category'] as String? ?? '';
    final category = categoryLabels?.firstWhere(
          (p) => p.$1 == categoryKey,
          orElse: () => (categoryKey, categoryKey),
        ).$2 ?? categoryKey;
    final direction  = trend['direction'] as String? ?? 'stable';
    final pct        = (trend['pct_change_8w'] as num?)?.toStringAsFixed(1) ?? '0';
    final supplyGap  = trend['supply_gap'] as bool? ?? false;
    final weekly     = (trend['weekly'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    final (dirIcon, dirColor, dirLabel) = switch (direction) {
      'up'   => (Icons.trending_up, const Color(0xFF10B981), l.demandTrendsUpLabel),
      'down' => (Icons.trending_down, const Color(0xFFEF4444), l.demandTrendsDownLabel),
      _      => (Icons.trending_flat, const Color(0xFF6B7280), l.demandTrendsStableLabel),
    };

    final maxCount = weekly.isEmpty
        ? 1
        : weekly.map((w) => (w['count'] as num?)?.toInt() ?? 0).reduce((a, b) => a > b ? a : b);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    category,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
                Icon(dirIcon, color: dirColor, size: 20),
                const SizedBox(width: 4),
                Text(
                  dirLabel,
                  style: TextStyle(color: dirColor, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  l.demandTrendsChangeLabel(pct),
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context)),
                ),
                if (supplyGap) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      l.demandTrendsSupplyGapLabel,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFFD97706),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (weekly.isNotEmpty) ...[
              const SizedBox(height: 10),
              _MiniBarChart(weekly: weekly, maxCount: maxCount, dirColor: dirColor),
            ],
          ],
        ),
      ),
    );
  }
}

class _MiniBarChart extends StatelessWidget {
  final List<Map<String, dynamic>> weekly;
  final int maxCount;
  final Color dirColor;

  const _MiniBarChart({
    required this.weekly,
    required this.maxCount,
    required this.dirColor,
  });

  @override
  Widget build(BuildContext context) {
    const barHeight = 36.0;
    return SizedBox(
      height: barHeight + 14,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: weekly.map((w) {
          final count = (w['count'] as num?)?.toInt() ?? 0;
          final ratio = maxCount > 0 ? count / maxCount : 0.0;
          final height = (ratio * barHeight).clamp(2.0, barHeight);
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    height: height,
                    decoration: BoxDecoration(
                      color: dirColor.withValues(alpha: 0.75),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
