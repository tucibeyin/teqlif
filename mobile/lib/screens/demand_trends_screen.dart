import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter/material.dart";
import "../services/localization_service.dart";
import '../ui_library/components/cards/teq_card.dart';

import '../config/app_colors.dart';
import '../config/theme.dart';
import '../models/listing_filter_state.dart';
import '../services/analytics_service.dart';
import '../ui_library/components/filters/teq_filter_bar.dart';

class DemandTrendsScreen extends ConsumerStatefulWidget {
  const DemandTrendsScreen({super.key});

  @override
  ConsumerState<DemandTrendsScreen> createState() => _DemandTrendsScreenState();
}

class _DemandTrendsScreenState extends ConsumerState<DemandTrendsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _trends = [];
  ListingFilterState _filter = const ListingFilterState();

  @override
  void initState() {
    super.initState();
    _load();
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

  List<Map<String, dynamic>> get _filteredTrends {
    if (_filter.category == null) return _trends;
    return _trends.where((t) => t['category'] == _filter.category).toList();
  }

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(localizationProvider);
    final filtered = _filteredTrends;
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.t("demandTrendsTitle")),
        centerTitle: false,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : _error != null || _trends.isEmpty
              ? _Empty(loc: loc, onRetry: _load)
              : RefreshIndicator(
                  color: kPrimary,
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        loc.t("demandTrendsSubtitle"),
                        style: TextStyle(fontSize: 13, color: AppColors.textSecondary(context)),
                      ),
                      const SizedBox(height: 10),
                      TeqFilterBar(
                        filter: _filter,
                        onChanged: (f) => setState(() => _filter = f),
                        showSearchBar: false,
                        showSubcategory: false,
                        showCity: false,
                        showCondition: false,
                        showSort: false,
                        showPriceRange: false,
                      ),
                      const SizedBox(height: 12),
                      if (filtered.isEmpty)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 32),
                            child: Text(loc.t("demandTrendsEmptyLabel"),
                                style: TextStyle(color: AppColors.textSecondary(context))),
                          ),
                        )
                      else
                        ...filtered.map((t) => _TrendCard(trend: t, loc: loc)),
                    ],
                  ),
                ),
    );
  }
}

class _Empty extends ConsumerWidget {
  final TranslationPack loc;
  final VoidCallback onRetry;
  const _Empty({required this.loc, required this.onRetry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bar_chart_outlined, size: 56, color: AppColors.textTertiary(context)),
          const SizedBox(height: 12),
          Text(loc.t("demandTrendsEmptyLabel"),
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

class _TrendCard extends ConsumerWidget {
  final Map<String, dynamic> trend;
  final TranslationPack loc;

  const _TrendCard({required this.trend, required this.loc});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final category = trend['category'] as String? ?? '';
    final direction  = trend['direction'] as String? ?? 'stable';
    final pct        = (trend['pct_change_8w'] as num?)?.toStringAsFixed(1) ?? '0';
    final supplyGap  = trend['supply_gap'] as bool? ?? false;
    final weekly     = (trend['weekly'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    final (dirIcon, dirColor, dirLabel) = switch (direction) {
      'up'   => (Icons.trending_up, const Color(0xFF10B981), loc.t("demandTrendsUpLabel")),
      'down' => (Icons.trending_down, const Color(0xFFEF4444), loc.t("demandTrendsDownLabel")),
      _      => (Icons.trending_flat, const Color(0xFF6B7280), loc.t("demandTrendsStableLabel")),
    };

    final maxCount = weekly.isEmpty
        ? 1
        : weekly.map((w) => (w['count'] as num?)?.toInt() ?? 0).reduce((a, b) => a > b ? a : b);

    return TeqCard(
      margin: const EdgeInsets.only(bottom: 12),

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
                  loc.t("demandTrendsChangeLabel", {"pct": pct}),
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
                      loc.t("demandTrendsSupplyGapLabel"),
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

class _MiniBarChart extends ConsumerWidget {
  final List<Map<String, dynamic>> weekly;
  final int maxCount;
  final Color dirColor;

  const _MiniBarChart({
    required this.weekly,
    required this.maxCount,
    required this.dirColor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
