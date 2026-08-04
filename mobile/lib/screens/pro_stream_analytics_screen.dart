import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter/material.dart";
import "../services/localization_service.dart";
import 'package:intl/intl.dart';
import '../config/app_colors.dart';
import '../config/theme.dart';
import 'viewmodels/pro_stream_analytics_view_model.dart';

// ── En İyi Yayın Saati ────────────────────────────────────────────────────

class BestStreamTimeScreen extends ConsumerStatefulWidget {
  final bool isEmbedded;
  const BestStreamTimeScreen({super.key, this.isEmbedded = false});

  @override
  ConsumerState<BestStreamTimeScreen> createState() => _BestStreamTimeScreenState();
}

class _BestStreamTimeScreenState extends ConsumerState<BestStreamTimeScreen> {
  static const int _kMax = 5;

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(localizationProvider);
    final state = ref.watch(bestStreamTimeProvider);
    final viewModel = ref.read(bestStreamTimeProvider.notifier);

    final content = state.loading
          ? const Center(child: CircularProgressIndicator())
          : state.hasError
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.wifi_off_outlined, size: 48, color: AppColors.textSecondary(context)),
                      const SizedBox(height: 12),
                      Text(loc.t("proLoadError"), style: TextStyle(color: AppColors.textSecondary(context))),
                      const SizedBox(height: 16),
                      FilledButton(onPressed: () => viewModel.load(), child: Text(loc.t("btnRetry"))),
                    ],
                  ),
                )
              : _buildContent(context, state, viewModel);

    if (widget.isEmbedded) {
      return content;
    }

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        title: Text(loc.t("proToolBestTimeTitle")),
        backgroundColor: AppColors.bg(context),
        elevation: 0,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: () => viewModel.load())],
      ),
      body: content,
    );
  }

  Widget _buildContent(BuildContext context, BestStreamTimeState state, BestStreamTimeViewModel viewModel) {
    final loc = ref.read(localizationProvider);
    final slots = (state.data!['slots'] as List? ?? []);
    final recommendation = state.data!['recommendation'] as String? ?? '';

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
                Text(loc.t("bestTimeNoData"), style: TextStyle(color: AppColors.textSecondary(context), fontSize: 15)),
                const SizedBox(height: 4),
                Text(loc.t("bestTimeNoDataHint"), style: TextStyle(color: AppColors.textTertiary(context), fontSize: 13)),
              ],
            ),
          )
        else ...[
          Text(
            loc.t("bestTimeSlotsHeader"),
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary(context)),
          ),
          const SizedBox(height: 12),
          ...(state.showAllSlots ? slots : slots.take(_kMax).toList()).asMap().entries.map((e) {
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
                        loc.t("bestTimeSlotStats", {"wins": wins.toString(), "count": count.toString()}),
                        style: TextStyle(fontSize: 11, color: AppColors.textSecondary(context)),
                      ),
                    ],
                  ),
                  if (isTop) const Padding(
                    padding: EdgeInsetsDirectional.only(start: 8),
                    child: Text('🏆', style: TextStyle(fontSize: 18)),
                  ),
                ],
              ),
            );
          }),
          if (slots.length > _kMax)
            GestureDetector(
              onTap: () => viewModel.toggleShowAllSlots(),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      state.showAllSlots ? loc.t("proShowLess") : loc.t("proShowAll", {"count": (slots.length - _kMax).toString()}),
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary(context)),
                    ),
                    const SizedBox(width: 4),
                    Icon(state.showAllSlots ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
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

class ConversionBreakdownScreen extends ConsumerStatefulWidget {
  final bool isEmbedded;
  const ConversionBreakdownScreen({super.key, this.isEmbedded = false});

  @override
  ConsumerState<ConversionBreakdownScreen> createState() => _ConversionBreakdownScreenState();
}

class _ConversionBreakdownScreenState extends ConsumerState<ConversionBreakdownScreen> {
  static const int _kMax = 5;

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(localizationProvider);
    final state = ref.watch(conversionBreakdownProvider);
    final viewModel = ref.read(conversionBreakdownProvider.notifier);

    final content = state.loading
          ? const Center(child: CircularProgressIndicator())
          : state.hasError
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.wifi_off_outlined, size: 48, color: AppColors.textSecondary(context)),
                      const SizedBox(height: 12),
                      Text(loc.t("proLoadError"), style: TextStyle(color: AppColors.textSecondary(context))),
                      const SizedBox(height: 16),
                      FilledButton(onPressed: () => viewModel.load(), child: Text(loc.t("btnRetry"))),
                    ],
                  ),
                )
              : _buildContent(context, loc, state, viewModel);

    if (widget.isEmbedded) {
      return content;
    }

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        title: Text(loc.t("proToolConversionTitle")),
        backgroundColor: AppColors.bg(context),
        elevation: 0,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: () => viewModel.load())],
      ),
      body: content,
    );
  }

  Widget _buildContent(BuildContext context, TranslationPack loc, ConversionBreakdownState state, ConversionBreakdownViewModel viewModel) {
    if (state.data.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.pie_chart_outline, size: 52, color: AppColors.textTertiary(context)),
            const SizedBox(height: 12),
            Text(loc.t("conversionNoData"), style: TextStyle(color: AppColors.textSecondary(context), fontSize: 15)),
            const SizedBox(height: 4),
            Text(loc.t("conversionNoDataHint"), style: TextStyle(color: AppColors.textTertiary(context), fontSize: 12)),
          ],
        ),
      );
    }

    final visible = state.showAll ? state.data : state.data.take(_kMax).toList();
    final maxConv = (state.data.map((r) => (r['conversion_rate'] as num? ?? 0).toDouble()).reduce((a, b) => a > b ? a : b)).toDouble();

    return ListView(shrinkWrap: widget.isEmbedded, physics: widget.isEmbedded ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.all(16),
      children: [
        Text(loc.t("conversionSectionHeader"),
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary(context))),
        const SizedBox(height: 4),
        Text(loc.t("conversionCategoryCount", {"count": state.data.length.toString()}),
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
                    Text(loc.t("conversionCategorySales", {"won": won.toString(), "total": total.toString()}), style: TextStyle(fontSize: 11, color: AppColors.textSecondary(context))),
                    const Spacer(),
                    if (avgPrice > 0)
                      Text(loc.t("conversionAvgPrice", {"price": NumberFormat('#,##0', 'tr_TR').format(avgPrice)}),
                          style: TextStyle(fontSize: 11, color: AppColors.textSecondary(context))),
                  ],
                ),
              ],
            ),
          );
        }),
        if (state.data.length > _kMax)
          GestureDetector(
            onTap: () => viewModel.toggleShowAll(),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    state.showAll ? loc.t("proShowLess") : loc.t("proShowAll", {"count": (state.data.length - _kMax).toString()}),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary(context)),
                  ),
                  const SizedBox(width: 4),
                  Icon(state.showAll ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      size: 16, color: AppColors.textSecondary(context)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
