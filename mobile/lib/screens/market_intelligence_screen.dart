import 'dart:ui';
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter/material.dart";
import "../services/localization_service.dart";
import 'package:url_launcher/url_launcher.dart';
import '../config/app_colors.dart';
import 'viewmodels/market_intelligence_view_model.dart';

class MarketIntelligenceScreen extends ConsumerStatefulWidget {
  final bool isPremium;
  final bool isEmbedded;
  const MarketIntelligenceScreen({super.key, required this.isPremium, this.isEmbedded = false});

  @override
  ConsumerState<MarketIntelligenceScreen> createState() => _MarketIntelligenceScreenState();
}

class _MarketIntelligenceScreenState extends ConsumerState<MarketIntelligenceScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.isPremium) {
      Future.microtask(() => ref.read(marketIntelligenceProvider.notifier).load());
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(localizationProvider);
    final state = ref.watch(marketIntelligenceProvider);
    final viewModel = ref.read(marketIntelligenceProvider.notifier);

    final bodyContent = state.loading
        ? const Center(child: CircularProgressIndicator())
        : (state.hasError && widget.isPremium)
            ? _buildError(loc, viewModel)
            : Stack(
                children: [
                  _buildContent(loc, state, viewModel),
                  if (!widget.isPremium) _buildPaywall(context, loc),
                ],
              );

    if (widget.isEmbedded) {
      return bodyContent;
    }

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        title: Text(loc.t("proToolMarketTitle")),
        backgroundColor: AppColors.bg(context),
        elevation: 0,
      ),
      body: bodyContent,
    );
  }

  Widget _buildError(TranslationPack loc, MarketIntelligenceViewModel viewModel) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off_outlined, size: 48, color: AppColors.textSecondary(context)),
          const SizedBox(height: 12),
          Text(loc.t("proLoadFailed"), style: TextStyle(color: AppColors.textSecondary(context))),
          const SizedBox(height: 16),
          TextButton(onPressed: () => viewModel.load(), child: Text(loc.t("btnRetry"))),
        ],
      ),
    );
  }

  Widget _buildContent(TranslationPack loc, MarketIntelligenceState state, MarketIntelligenceViewModel viewModel) {
    final queries     = (state.demand?['top_queries']          as List? ?? []).cast<Map<String, dynamic>>();
    final catSearch   = (state.demand?['by_category']          as List? ?? []).cast<Map<String, dynamic>>();
    final peakHours   = (state.trends?['peak_hours']           as List? ?? []).cast<Map<String, dynamic>>();
    final trendCats   = (state.trends?['trending_categories']  as List? ?? []).cast<Map<String, dynamic>>();
    final growth      = state.trends?['average_spend_growth']  as double?;

    final maxQCount  = queries.isEmpty  ? 1 : (queries.map((q) => (q['count'] as int? ?? 0)).reduce((a, b) => a > b ? a : b));
    final maxHrCount = peakHours.isEmpty ? 1 : (peakHours.map((h) => (h['count'] as int? ?? 0)).reduce((a, b) => a > b ? a : b));

    return RefreshIndicator(
      onRefresh: () => viewModel.load(),
      child: ListView(shrinkWrap: widget.isEmbedded, physics: widget.isEmbedded ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          if (growth != null)
            _GrowthBanner(growth: growth, loc: loc),
          if (growth != null) const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: Text(
                  loc.t("marketSearchTitle"),
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary(context)),
                ),
              ),
              _SmallDayFilter(days: state.searchDays, loc: loc, onChanged: (d) {
                viewModel.reloadDemand(d);
              }),
            ],
          ),
          const SizedBox(height: 10),

          if (queries.isEmpty)
            _EmptyHint(text: loc.t("marketNoSearchData"))
          else
            SizedBox(
              height: 110,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: queries.take(10).length,
                padding: const EdgeInsets.symmetric(horizontal: 2),
                itemBuilder: (context, i) {
                  final q = queries[i];
                  final count = q['count'] as int? ?? 0;
                  final fill = maxQCount > 0 ? count / maxQCount : 0.0;
                  final rankLabel = i < 3 ? ['🥇', '🥈', '🥉'][i] : '${i + 1}.';
                  return Container(
                    width: 148,
                    margin: const EdgeInsets.only(right: 10),
                    padding: const EdgeInsets.all(12),
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
                            Text(rankLabel,
                                style: TextStyle(
                                    fontSize: i < 3 ? 15 : 11,
                                    color: AppColors.textSecondary(context))),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('$count',
                                  style: const TextStyle(
                                      fontSize: 11, fontWeight: FontWeight.w800,
                                      color: Color(0xFFF59E0B))),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          q['query'] as String? ?? '—',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary(context)),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Spacer(),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: fill,
                            backgroundColor: AppColors.border(context),
                            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFF59E0B)),
                            minHeight: 3,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

          if (catSearch.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              loc.t("marketCategoryTitle"),
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary(context)),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: catSearch.map((c) {
                final cat = c['category'] as String? ?? loc.t("lblOther");
                final cnt = c['count'] as int? ?? 0;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.card(context),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(cat, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary(context))),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('$cnt',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],

          const SizedBox(height: 24),
          Text(
            loc.t("marketPeakHoursTitle"),
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary(context)),
          ),
          const SizedBox(height: 4),
          Text(
            loc.t("marketPeakHoursDesc"),
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context)),
          ),
          const SizedBox(height: 12),

          if (peakHours.isEmpty)
            _EmptyHint(text: loc.t("marketNoActivityData"))
          else
            Container(
              decoration: BoxDecoration(
                color: AppColors.card(context),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: peakHours.asMap().entries.map((e) {
                  final i = e.key;
                  final h = e.value;
                  final count = h['count'] as int? ?? 0;
                  final isLast = i == peakHours.length - 1;
                  final fill = maxHrCount > 0 ? count / maxHrCount : 0.0;
                  final rankEmoji = i == 0 ? '🔥' : (i == 1 ? '⚡' : '⏰');
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            Text(rankEmoji, style: const TextStyle(fontSize: 16)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(h['label'] as String? ?? '',
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                                          color: AppColors.textPrimary(context))),
                                  const SizedBox(height: 5),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: fill,
                                      backgroundColor: AppColors.border(context),
                                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF06B6D4)),
                                      minHeight: 5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!isLast) const Divider(height: 1),
                    ],
                  );
                }).toList(),
              ),
            ),

          if (trendCats.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              loc.t("marketTrendingTitle"),
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary(context)),
            ),
            const SizedBox(height: 4),
            Text(
              loc.t("marketTrendingDesc"),
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context)),
            ),
            const SizedBox(height: 12),
            ...trendCats.asMap().entries.map((e) {
              final cat   = e.value;
              final label = cat['label'] as String? ?? '';
              final grow  = (cat['growth_pct'] as num?)?.toDouble() ?? 0.0;
              final isPos = grow >= 0;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.card(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border(context)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(label,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary(context))),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isPos
                            ? const Color(0xFF22C55E).withValues(alpha: 0.1)
                            : const Color(0xFFEF4444).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${isPos ? '+' : ''}${grow.toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w800,
                          color: isPos ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                        ),
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

  Widget _buildPaywall(BuildContext context, TranslationPack loc) {
    return Positioned.fill(
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            color: AppColors.bg(context).withValues(alpha: 0.6),
            child: Center(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 32),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                decoration: BoxDecoration(
                  color: AppColors.card(context),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 24)],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64, height: 64,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFFFFB800), Color(0xFFFF6B00)]),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.insights_outlined, color: Colors.white, size: 32),
                    ),
                    const SizedBox(height: 20),
                    Text(loc.t("proUpgradeTitle"),
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary(context))),
                    const SizedBox(height: 10),
                    Text(
                      loc.t("marketPaywallDesc"),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: AppColors.textSecondary(context), height: 1.5),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFFFFB800), Color(0xFFFF6B00)]),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ElevatedButton(
                          onPressed: () => launchUrl(Uri.parse('https://www.teqlif.com/pro-plan.html'),
                              mode: LaunchMode.inAppWebView),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(loc.t("proUpgradeBtn"),
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Colors.white)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


// ── Alt Widgetlar ─────────────────────────────────────────────────────────────

class _GrowthBanner extends ConsumerWidget {
  final double growth;
  final TranslationPack loc;
  const _GrowthBanner({required this.growth, required this.loc});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPos = growth >= 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isPos
            ? const Color(0xFF22C55E).withValues(alpha: 0.08)
            : const Color(0xFFEF4444).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPos
              ? const Color(0xFF22C55E).withValues(alpha: 0.25)
              : const Color(0xFFEF4444).withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Text(isPos ? '📈' : '📉', style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isPos
                      ? loc.t("marketGrowthPos", {"pct": growth.toStringAsFixed(1)})
                      : loc.t("marketGrowthNeg", {"pct": growth.toStringAsFixed(1)}),
                  style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700,
                    color: isPos ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  loc.t("marketGrowthSub"),
                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary(context)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallDayFilter extends ConsumerWidget {
  final int days;
  final TranslationPack loc;
  final ValueChanged<int> onChanged;
  const _SmallDayFilter({required this.days, required this.loc, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [7, 30].map((d) {
        final active = days == d;
        return GestureDetector(
          onTap: () { if (days != d) onChanged(d); },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(left: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: active ? const Color(0xFFF59E0B) : AppColors.card(context),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: active ? const Color(0xFFF59E0B) : AppColors.border(context)),
            ),
            child: Text(loc.t("marketDayFilter", {"days": d.toString()}),
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700,
                    color: active ? Colors.white : AppColors.textSecondary(context))),
          ),
        );
      }).toList(),
    );
  }
}

class _EmptyHint extends ConsumerWidget {
  final String text;
  const _EmptyHint({required this.text});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text,
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context)),
          textAlign: TextAlign.center),
    );
  }
}
