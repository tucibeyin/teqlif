import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter/material.dart";
import "../services/localization_service.dart";
import '../ui_library/components/buttons/teq_button.dart';

import 'package:url_launcher/url_launcher.dart';
import '../config/app_colors.dart';
import '../ui_library/components/filters/teq_filter_bar.dart';
import 'viewmodels/listing_analytics_view_model.dart';

class ListingAnalyticsScreen extends ConsumerStatefulWidget {
  final bool isPremium;
  final bool isEmbedded;
  const ListingAnalyticsScreen({
    super.key,
    required this.isPremium,
    this.isEmbedded = false,
  });

  @override
  ConsumerState<ListingAnalyticsScreen> createState() => _ListingAnalyticsScreenState();
}

class _ListingAnalyticsScreenState extends ConsumerState<ListingAnalyticsScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.isPremium) {
      Future.microtask(() => ref.read(listingAnalyticsProvider.notifier).load());
    }
  }

  List<ListingMetric> _filteredListings(ListingAnalyticsState state) {
    var res = state.listings;
    if (state.filter.searchQuery != null && state.filter.searchQuery!.isNotEmpty) {
      final q = state.filter.searchQuery!.toLowerCase();
      res = res.where((m) => m.title.toLowerCase().contains(q)).toList();
    }
    return res;
  }

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(localizationProvider);
    final state = ref.watch(listingAnalyticsProvider);
    final viewModel = ref.read(listingAnalyticsProvider.notifier);
    
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
        title: Text(loc.t("proToolListingsTitle")),
        backgroundColor: AppColors.bg(context),
        elevation: 0,
      ),
      body: bodyContent,
    );
  }

  Widget _buildError(TranslationPack loc, ListingAnalyticsViewModel viewModel) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.wifi_off_outlined,
            size: 48,
            color: AppColors.textSecondary(context),
          ),
          const SizedBox(height: 12),
          Text(
            loc.t("proLoadFailed"),
            style: TextStyle(color: AppColors.textSecondary(context)),
          ),
          const SizedBox(height: 16),
          TeqButton.text(onPressed: () => viewModel.load(), text: loc.t("btnRetry"), isExpanded: false),
        ],
      ),
    );
  }

  Widget _buildContent(TranslationPack loc, ListingAnalyticsState state, ListingAnalyticsViewModel viewModel) {
    final selectedItem = state.selectedListingId == null
        ? null
        : state.listings.where((m) => m.id == state.selectedListingId).firstOrNull;

    final displayImp = selectedItem != null
        ? selectedItem.impressions
        : (state.videoImp + state.photoImp);
    final displayCtr = selectedItem != null
        ? selectedItem.ctr
        : (state.videoImp + state.photoImp > 0
              ? ((state.videoCtr * state.videoImp + state.photoCtr * state.photoImp) /
                    (state.videoImp + state.photoImp))
              : 0.0);
              
    final filtered = _filteredListings(state);

    return RefreshIndicator(
      onRefresh: () => viewModel.load(),
      child: ListView(
        shrinkWrap: widget.isEmbedded,
        physics: widget.isEmbedded
            ? const NeverScrollableScrollPhysics()
            : const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 40),
        children: [
          TeqFilterBar(
            filter: state.filter,
            onChanged: (f) {
              viewModel.updateFilter(f);
            },
            showExtraFields: false,
            showCity: false,
            showCondition: false,
            showSort: false,
            showPriceRange: false,
          ),
          const SizedBox(height: 10),

          if (state.listings.isNotEmpty) ...[
            // Horizontal Carousel for Selection
            SizedBox(
              height: 100,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: filtered.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    final isSelected = state.selectedListingId == null;
                    return GestureDetector(
                      onTap: () => viewModel.selectListing(null),
                      child: Container(
                        width: 90,
                        margin: const EdgeInsetsDirectional.only(end: 12),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF6366F1).withValues(alpha: 0.1)
                              : AppColors.card(context),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF6366F1)
                                : AppColors.border(context),
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.dashboard_outlined,
                              color: isSelected
                                  ? const Color(0xFF6366F1)
                                  : AppColors.textSecondary(context),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              loc.t("liveAllCategory"), // "Tümü" / "All"
                              style: TextStyle(
                                color: isSelected
                                    ? const Color(0xFF6366F1)
                                    : AppColors.textPrimary(context),
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.w600,
                                fontSize: 13,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final metric = filtered[index - 1];
                  final isSelected = state.selectedListingId == metric.id;
                  return GestureDetector(
                    onTap: () => viewModel.selectListing(metric.id),
                    child: Container(
                      width: 120,
                      margin: const EdgeInsetsDirectional.only(end: 12),
                      decoration: BoxDecoration(
                        color: AppColors.card(context),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF6366F1)
                              : AppColors.border(context),
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (metric.imageUrl != null)
                            CachedNetworkImage(
                              imageUrl: metric.imageUrl!,
                              fit: BoxFit.cover,
                              errorWidget: (_, _, _) => Container(
                                color: AppColors.surfaceVariant(context),
                              ),
                            )
                          else
                            Container(color: AppColors.surfaceVariant(context)),
                          Positioned(
                            left: 0, right: 0, bottom: 0,
                            child: Container(
                              padding: const EdgeInsetsDirectional.fromSTEB(8, 20, 8, 8),
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Colors.transparent, Colors.black87],
                                ),
                              ),
                              child: Text(
                                metric.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          if (metric.isVideo)
                            Positioned(
                              top: 6, right: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Icon(Icons.play_arrow, size: 12, color: Colors.white),
                              ),
                            ),
                          if (isSelected)
                            Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border.all(color: const Color(0xFF6366F1), width: 2),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),

            // Metrics Display Area
            Row(
              children: [
                _SummaryTile(
                  label: loc.t("listingTotalViews"),
                  value: '+${_fmt(displayImp)}',
                  icon: Icons.visibility_outlined,
                  color: const Color(0xFF6366F1),
                ),
                const SizedBox(width: 10),
                _SummaryTile(
                  label: loc.t("listingAvgCtr"),
                  value: '%${displayCtr.toStringAsFixed(1)}',
                  icon: Icons.ads_click_outlined,
                  color: const Color(0xFF10B981),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (selectedItem == null && state.videoImp > 0 && state.photoImp > 0)
              _ComparisonCard(videoCtr: state.videoCtr, photoCtr: state.photoCtr, loc: loc),

            if (selectedItem != null) ...[
              const SizedBox(height: 16),
              if (selectedItem.isVideo && selectedItem.completionPct != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.card(context),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border(context)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEC4899).withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.av_timer,
                          color: Color(0xFFEC4899),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              loc.t("listingVideoComplete"),
                              style: TextStyle(
                                color: AppColors.textSecondary(context),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '%${selectedItem.completionPct!.toStringAsFixed(1)}',
                              style: TextStyle(
                                color: AppColors.textPrimary(context),
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              if (!selectedItem.isVideo && selectedItem.avgPhotoDepth != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.card(context),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border(context)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.collections,
                          color: Color(0xFFF59E0B),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              loc.t("listingGalleryLabel"),
                              style: TextStyle(
                                color: AppColors.textSecondary(context),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              selectedItem.avgPhotoDepth! > 1.5
                                  ? loc.t("listingGalleryDeep", {'n': selectedItem.avgPhotoDepth!.toStringAsFixed(1)})
                                  : loc.t("listingGalleryShallow"),
                              style: TextStyle(
                                color: AppColors.textPrimary(context),
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],

          if (state.listings.isEmpty)
            _EmptyState(
              icon: Icons.bar_chart_outlined,
              title: loc.t("listingNoDataTitle"),
              subtitle: loc.t("listingNoDataDesc"),
            ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 32,
                ),
                decoration: BoxDecoration(
                  color: AppColors.card(context),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: AppColors.isDark(context) ? 0.5 : 0.12,
                      ),
                      blurRadius: 24,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.bar_chart_outlined,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      loc.t("proUpgradeTitle"),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      loc.t("listingPaywallDesc"),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary(context),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ElevatedButton(
                          onPressed: () => launchUrl(
                            Uri.parse('https://www.teqlif.com/pro-plan.html'),
                            mode: LaunchMode.inAppWebView,
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            loc.t("proUpgradeBtn"),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: Colors.white,
                            ),
                          ),
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

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)} bin';
    return '$n';
  }
}


// ── Reusable Widgets ──────────────────────────────────────────────────────────

class _SummaryTile extends ConsumerWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _SummaryTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComparisonCard extends ConsumerWidget {
  final double videoCtr;
  final double photoCtr;
  final TranslationPack loc;
  const _ComparisonCard({
    required this.videoCtr,
    required this.photoCtr,
    required this.loc,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String message;
    if (videoCtr == 0 && photoCtr == 0) return const SizedBox.shrink();
    if (photoCtr > 0 && videoCtr > photoCtr * 1.1) {
      final x = (videoCtr / photoCtr).toStringAsFixed(1);
      message = loc.t("listingVideoBeatsPhoto", {"x": x});
    } else if (videoCtr > 0 && photoCtr > videoCtr * 1.1) {
      final x = (photoCtr / videoCtr).toStringAsFixed(1);
      message = loc.t("listingPhotoBeatsVideo", {"x": x});
    } else {
      message = loc.t("listingMediaEqual");
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF6366F1).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF6366F1).withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6366F1),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _SegChip(emoji: '🎬', label: loc.t("listingVideoLabel"), ctr: videoCtr),
              const SizedBox(width: 8),
              _SegChip(emoji: '📸', label: loc.t("listingPhotoLabel"), ctr: photoCtr),
            ],
          ),
        ],
      ),
    );
  }
}

class _SegChip extends ConsumerWidget {
  final String emoji;
  final String label;
  final double ctr;
  const _SegChip({required this.emoji, required this.label, required this.ctr});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$emoji $label  %${ctr.toStringAsFixed(1)}',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary(context),
        ),
      ),
    );
  }
}



class _EmptyState extends ConsumerWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(top: 48),
      child: Column(
        children: [
          Icon(icon, size: 52, color: AppColors.textSecondary(context)),
          const SizedBox(height: 14),
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary(context),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
