import 'dart:async';
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter/material.dart";
import "../services/localization_service.dart";
import '../config/api.dart';
import '../config/app_colors.dart';
import '../ui_library/components/filters/teq_filter_bar.dart';
import '../ui_library/components/overlays/teq_toast.dart';
import 'viewmodels/retargeting_view_model.dart';

class RetargetingScreen extends ConsumerStatefulWidget {
  final int initialIndex;
  final bool isEmbedded;
  final int? listingId;

  const RetargetingScreen({super.key, this.initialIndex = 0, this.isEmbedded = false, this.listingId});

  @override
  ConsumerState<RetargetingScreen> createState() => _RetargetingScreenState();
}

class _RetargetingScreenState extends ConsumerState<RetargetingScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(retargetingProvider.notifier).init(widget.listingId);
    });
  }

  List<Map<String, dynamic>> _filteredReportListings(RetargetingState state) {
    var result = state.reportListings;
    if (state.reportFilter.searchQuery != null && state.reportFilter.searchQuery!.isNotEmpty) {
      final q = state.reportFilter.searchQuery!.toLowerCase();
      result = result.where((l) =>
        (l['title'] as String? ?? '').toLowerCase().contains(q)
      ).toList();
    }
    if (state.reportFilter.dateFrom != null && state.reportFilter.dateTo != null) {
      final start = state.reportFilter.dateFrom!;
      final end = state.reportFilter.dateTo!.add(const Duration(days: 1));
      result = result.where((item) {
        final raw = item['created_at'] as String?;
        if (raw == null) return false;
        final dt = DateTime.tryParse(raw)?.toLocal();
        return dt != null && !dt.isBefore(start) && dt.isBefore(end);
      }).toList();
    }
    if (state.reportFilter.category != null && state.reportFilter.category!.isNotEmpty) {
      result = result.where((l) => l['category'] == state.reportFilter.category).toList();
    }
    if (state.reportFilter.subcategory != null && state.reportFilter.subcategory!.isNotEmpty) {
      result = result.where((l) => l['subcategory'] == state.reportFilter.subcategory).toList();
    }
    return result;
  }

  List<Map<String, dynamic>> _filteredCampaignListings(RetargetingState state) {
    var result = state.reportListings;
    if (state.campaignFilter.searchQuery != null && state.campaignFilter.searchQuery!.isNotEmpty) {
      final q = state.campaignFilter.searchQuery!.toLowerCase();
      result = result.where((l) =>
        (l['title'] as String? ?? '').toLowerCase().contains(q)
      ).toList();
    }
    if (state.campaignFilter.category != null && state.campaignFilter.category!.isNotEmpty) {
      result = result.where((l) => l['category'] == state.campaignFilter.category).toList();
    }
    if (state.campaignFilter.subcategory != null && state.campaignFilter.subcategory!.isNotEmpty) {
      result = result.where((l) => l['subcategory'] == state.campaignFilter.subcategory).toList();
    }
    if (state.campaignFilter.dateFrom != null && state.campaignFilter.dateTo != null) {
      final start = state.campaignFilter.dateFrom!;
      final end = state.campaignFilter.dateTo!.add(const Duration(days: 1));
      result = result.where((item) {
        final raw = item['created_at'] as String?;
        if (raw == null) return false;
        final dt = DateTime.tryParse(raw)?.toLocal();
        return dt != null && !dt.isBefore(start) && dt.isBefore(end);
      }).toList();
    }
    return result;
  }

  String _formatCooldown(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Widget _buildListingCarousel(RetargetingState state, RetargetingViewModel viewModel) {
    final loc = ref.read(localizationProvider);
    final filtered = _filteredReportListings(state);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 8),
          child: TeqFilterBar(
            filter: state.reportFilter,
            onChanged: (f) => viewModel.updateReportFilter(f),
            showExtraFields: false,
            showCity: false,
            showCondition: false,
            showSort: false,
            showPriceRange: false,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 112,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: filtered.length + 1,
            itemBuilder: (ctx, i) {
              if (i == 0) {
                final sel = state.selectedReportListingId == null;
                return GestureDetector(
                  onTap: () => viewModel.selectReportListing(null),
                  child: Container(
                    width: 88,
                    margin: const EdgeInsetsDirectional.only(end: 10),
                    decoration: BoxDecoration(
                      color: sel ? const Color(0xFF14B8A6).withValues(alpha: 0.12) : AppColors.card(context),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: sel ? const Color(0xFF14B8A6) : AppColors.border(context), width: sel ? 2 : 1),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.apps_rounded, size: 26, color: sel ? const Color(0xFF14B8A6) : AppColors.textSecondary(context)),
                        const SizedBox(height: 6),
                        Text(loc.t("reportAll"),
                          style: TextStyle(color: sel ? const Color(0xFF14B8A6) : AppColors.textSecondary(context),
                            fontWeight: sel ? FontWeight.bold : FontWeight.normal, fontSize: 13)),
                      ],
                    ),
                  ),
                );
              }
              final listing = filtered[i - 1];
              final lid = listing['id'] as int;
              final sel = state.selectedReportListingId == lid;
              final imageUrls = listing['image_urls'] as List? ?? [];
              final imageUrl = imageUrls.isNotEmpty ? imgUrl(imageUrls.first as String) : null;
              final title = listing['title'] as String? ?? '';
              return GestureDetector(
                onTap: () => viewModel.selectReportListing(lid),
                child: Container(
                  width: 128,
                  margin: const EdgeInsetsDirectional.only(end: 10),
                  decoration: BoxDecoration(
                    color: AppColors.card(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: sel ? const Color(0xFF14B8A6) : AppColors.border(context), width: sel ? 2 : 1),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        imageUrl != null
                          ? Image.network(imageUrl, fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(color: AppColors.border(context)))
                          : Container(color: AppColors.border(context),
                              child: Icon(Icons.image_not_supported_outlined, color: AppColors.textSecondary(context))),
                        Positioned(
                          bottom: 0, left: 0, right: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter,
                                colors: [Colors.black.withValues(alpha: 0.80), Colors.transparent]),
                            ),
                            child: Text(title,
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                        if (sel)
                          Positioned(top: 6, right: 6,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(color: Color(0xFF14B8A6), shape: BoxShape.circle),
                              child: const Icon(Icons.check, color: Colors.white, size: 12),
                            )),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildReportContent(Map<String, dynamic> data) {
    final loc = ref.read(localizationProvider);
    final target = data['total_target'] as int? ?? 0;
    final sent = data['total_sent'] as int? ?? 0;
    final clicks = data['total_clicks'] as int? ?? 0;
    final spent = data['total_spent_tuci'] as int? ?? 0;
    final costPerClick = clicks > 0 ? (spent / clicks).round() : 0;
    final clickRate = sent > 0 ? ((clicks / sent) * 100).toStringAsFixed(1) : '0.0';
    final campaigns = (data['campaigns'] as List?)?.cast<Map<String, dynamic>>();

    if (target == 0 && (campaigns == null || campaigns.isEmpty)) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(child: Text(loc.t("reportNoNotificationYet"), style: TextStyle(color: AppColors.textSecondary(context)))),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFunnelCard(loc.t("reportConversionFunnel"), [
            {'label': '📢 ${loc.t("reportTargetAudience")}', 'value': '$target'},
            {'label': '📩 ${loc.t("reportSuccessfullyDelivered")}', 'value': '$sent'},
            {'label': '👆 ${loc.t("reportClickOpen")}', 'value': '$clicks  (%$clickRate)'},
          ]),
          const SizedBox(height: 16),
          _buildROICard(loc.t("reportROI"), '$spent TUCi', '$costPerClick TUCi / ${loc.t("adReportMetricClicks")}'),
          if (campaigns != null && campaigns.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('Gönderim Geçmişi',
              style: TextStyle(color: AppColors.textPrimary(context), fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            ...campaigns.map((c) => _buildCampaignCard(c)),
          ],
        ],
      ),
    );
  }

  Widget _buildCampaignCard(Map<String, dynamic> campaign) {
    final loc = ref.read(localizationProvider);
    final targetCount = campaign['target_count'] as int? ?? 0;
    final sentCount   = campaign['sent_count']   as int? ?? 0;
    final clickCount  = campaign['click_count']  as int? ?? 0;
    final spentTuci   = campaign['spent_tuci']   as int? ?? 0;
    final freeCredits = campaign['spent_free_credits'] as int? ?? 0;
    final sentAt = DateTime.tryParse(campaign['sent_at'] as String? ?? '')?.toLocal();
    final clickRate = sentCount > 0 ? ((clickCount / sentCount) * 100).toStringAsFixed(1) : '0.0';
    final dateStr = sentAt != null
        ? '${sentAt.day.toString().padLeft(2, '0')}.${sentAt.month.toString().padLeft(2, '0')}.${sentAt.year}  '
          '${sentAt.hour.toString().padLeft(2, '0')}:${sentAt.minute.toString().padLeft(2, '0')}'
        : '--';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.calendar_today, size: 13, color: Color(0xFF14B8A6)),
            const SizedBox(width: 6),
            Text(dateStr, style: const TextStyle(color: Color(0xFF14B8A6), fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _statChip('📢', '$targetCount', loc.t("reportTargetAudience"))),
            Expanded(child: _statChip('📩', '$sentCount', loc.t("reportSuccessfullyDelivered"))),
            Expanded(child: _statChip('👆', '$clickCount (%$clickRate)', loc.t("reportClickOpen"))),
          ]),
          if (spentTuci > 0 || freeCredits > 0) ...[
            const SizedBox(height: 8),
            Row(children: [
              if (freeCredits > 0)
                Text('$freeCredits ${loc.t("reportFreeCreditsUsed")}',
                  style: TextStyle(color: AppColors.textSecondary(context), fontSize: 11)),
              if (freeCredits > 0 && spentTuci > 0)
                Text('  •  ', style: TextStyle(color: AppColors.textSecondary(context), fontSize: 11)),
              if (spentTuci > 0)
                Text('$spentTuci TUCi ${loc.t("reportTotalSpent")}',
                  style: TextStyle(color: AppColors.textSecondary(context), fontSize: 11)),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _statChip(String emoji, String value, String label) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 2),
        Text(value,
          style: TextStyle(color: AppColors.textPrimary(context), fontWeight: FontWeight.bold, fontSize: 12),
          textAlign: TextAlign.center),
        const SizedBox(height: 2),
        Text(label,
          style: TextStyle(color: AppColors.textSecondary(context), fontSize: 9),
          textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
      ],
    );
  }

  Future<void> _sendBlast(RetargetingState state, RetargetingViewModel viewModel) async {
    final loc = ref.read(localizationProvider);
    final listing = state.selectedListing;
    final audience = state.audienceData;
    if (listing == null || audience == null) return;
    final reachable      = audience['reachable_audience']     as int? ?? 0;
    final creditsLeft    = audience['blast_credits_remaining'] as int? ?? 0;
    final perBlastCap    = audience['per_blast_cap']          as int? ?? 10;
    final tuciBalance    = audience['tuci_balance']            as int? ?? 0;
    if (reachable == 0) return;

    final actualCount = reachable < perBlastCap ? reachable : perBlastCap;
    final freeUsed    = creditsLeft < actualCount ? creditsLeft : actualCount;
    final paidCount   = actualCount - freeUsed;
    final tuciCost    = paidCount * 10;

    if (tuciCost > 0 && tuciBalance < tuciCost) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.card(context),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(loc.t("retargetingDialogTitle"),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary(context))),
          content: Text(
            loc.t("retargetingDialogBodyInsufficient", {"cost": tuciCost.toString(), "balance": tuciBalance.toString()}),
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary(context), height: 1.5),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(loc.t("btnDismiss"), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
      return;
    }

    final String dialogBody;
    if (freeUsed > 0 && paidCount == 0) {
      dialogBody = loc.t("retargetingDialogBodyFree", {"count": actualCount.toString(), "credits": freeUsed.toString()});
    } else if (freeUsed > 0 && paidCount > 0) {
      dialogBody = loc.t("retargetingDialogBodyKarma", {"count": actualCount.toString(), "free": freeUsed.toString(), "cost": tuciCost.toString()});
    } else {
      dialogBody = loc.t("retargetingDialogBodyPaid", {"count": actualCount.toString(), "cost": tuciCost.toString()});
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          loc.t("retargetingDialogTitle"),
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary(context)),
        ),
        content: Text(
          dialogBody,
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary(context), height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.t("btnDismiss"), style: TextStyle(color: AppColors.textSecondary(context))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(loc.t("btnSend"), style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final result = await viewModel.sendBlast(actualCount, tuciCost);
    if (!mounted) return;

    if (result != null && result['error'] == null) {
      TeqToast.success(loc.t("retargetingBlastSuccess"));
    } else {
      final errMsg = result?['error'] as String? ?? 'Bir sorun oluştu, lütfen tekrar dene.';
      TeqToast.error(errMsg);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(localizationProvider);
    final state = ref.watch(retargetingProvider);
    final viewModel = ref.read(retargetingProvider.notifier);

    final Widget reportTab = ListView(
      shrinkWrap: widget.isEmbedded,
      physics: widget.isEmbedded ? const NeverScrollableScrollPhysics() : null,
      padding: EdgeInsets.zero,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 4),
          child: Text(loc.t("reportMassNotificationTitle"),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 12),
          child: Text(loc.t("reportMassNotificationDesc"),
            style: TextStyle(color: AppColors.textSecondary(context))),
        ),
        _buildListingCarousel(state, viewModel),
        const SizedBox(height: 16),
        state.reportData.when(
          data: (data) => _buildReportContent(data),
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(16),
            child: Text('${loc.t("reportLoadError")}$e',
              style: TextStyle(color: AppColors.textSecondary(context))),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );

    final Widget retargetingTab = ListView(
      shrinkWrap: widget.isEmbedded, 
      physics: widget.isEmbedded ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 40),
      children: [
        _infoCard(),
        const SizedBox(height: 16),
        _buildCampaignListingCarousel(state, viewModel),
        const SizedBox(height: 20),
        if (state.loadingAudience)
          const _AudienceSkeleton()
        else if (state.audienceData != null)
          _audienceCard(state, viewModel),
      ],
    );

    if (widget.isEmbedded) {
      return DefaultTabController(
        length: 2,
        initialIndex: widget.initialIndex,
        child: Column(
          children: [
            const TabBar(
              indicatorColor: Color(0xFF14B8A6),
              labelColor: Color(0xFF14B8A6),
              unselectedLabelColor: Colors.grey,
              tabs: [
                Tab(icon: Icon(Icons.touch_app), text: 'Retargeting'),
                Tab(icon: Icon(Icons.auto_graph), text: 'Raporlar'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  retargetingTab,
                  reportTab,
                ],
              ),
            ),
          ],
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialIndex,
      child: Scaffold(
        backgroundColor: AppColors.bg(context),
        appBar: AppBar(
          title: Text(loc.t("centerNotificationAudience")),
          backgroundColor: AppColors.bg(context),
          elevation: 0,
          bottom: TabBar(
            indicatorColor: const Color(0xFF14B8A6),
            labelColor: const Color(0xFF14B8A6),
            unselectedLabelColor: Colors.grey,
            tabs: [
              const Tab(icon: Icon(Icons.touch_app), text: 'Retargeting'),
              Tab(icon: const Icon(Icons.auto_graph), text: loc.t("tabReports")),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            retargetingTab,
            reportTab,
          ],
        ),
      ),
    );
  }

  Widget _buildFunnelCard(String title, List<Map<String, String>> steps) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: AppColors.textPrimary(context), fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 16),
          ...steps.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(s['label']!, style: TextStyle(color: AppColors.textSecondary(context))),
                    Text(s['value']!, style: TextStyle(color: AppColors.textPrimary(context), fontWeight: FontWeight.w600)),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildROICard(String title, String totalSpend, String costPerClick) {
    final loc = ref.read(localizationProvider);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF14B8A6).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF14B8A6).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Color(0xFF14B8A6), fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(loc.t("reportTotalSpent"), style: const TextStyle(color: Colors.white70)),
              Text(totalSpend, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(loc.t("reportCostPerClick"), style: const TextStyle(color: Colors.white70)),
              Text(costPerClick, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoCard() {
    final loc = ref.read(localizationProvider);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF6366F1).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18, color: Color(0xFF6366F1)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              loc.t("retargetingInfoText"),
              style: TextStyle(fontSize: 12, color: AppColors.textPrimary(context), height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _audienceCard(RetargetingState state, RetargetingViewModel viewModel) {
    final loc = ref.read(localizationProvider);
    final audience = state.audienceData!;
    final error = audience['error'] as String?;

    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Text(
            error == 'pro_required'
                ? 'Bu özellik yalnızca PRO kullanıcılara açıktır.'
                : 'Veri yüklenemedi.',
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary(context)),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final totalViewers  = audience['total_viewers_30d']      as int? ?? 0;
    final alreadyBought = audience['already_bought']          as int? ?? 0;
    final reachable     = audience['reachable_audience']      as int? ?? 0;
    final cost          = audience['estimated_cost_tuci']     as int? ?? 0;
    final creditsLeft   = audience['blast_credits_remaining'] as int? ?? 0;
    final perBlastCap   = audience['per_blast_cap']           as int? ?? 10;
    final actualCount   = reachable < perBlastCap ? reachable : perBlastCap;
    final freeUsed      = creditsLeft < actualCount ? creditsLeft : actualCount;
    final paidCount     = actualCount - freeUsed;
    final isFree        = paidCount == 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
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
                    width: 34, height: 34,
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(Icons.people_outline, size: 18, color: Color(0xFF6366F1)),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    loc.t("retargetingLast30Days"),
                    style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _AudienceStat(
                    value: '$totalViewers',
                    label: loc.t("retargetingViewerLabel"),
                    color: AppColors.textPrimary(context),
                  ),
                  const SizedBox(width: 8),
                  _AudienceStat(
                    value: '$alreadyBought',
                    label: loc.t("retargetingBoughtLabel"),
                    color: const Color(0xFF22C55E),
                  ),
                  const SizedBox(width: 8),
                  _AudienceStat(
                    value: '$reachable',
                    label: loc.t("retargetingReachableLabel"),
                    color: const Color(0xFF6366F1),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (reachable == 0) ...[
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      children: [
                        Icon(Icons.search_off_outlined, size: 40, color: AppColors.textSecondary(context)),
                        const SizedBox(height: 10),
                        Text(
                          loc.t("retargetingNoAudience"),
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary(context)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          loc.t("retargetingNoAudienceDesc"),
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context), height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            loc.t("retargetingEstimatedCost"),
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context)),
                          ),
                          const SizedBox(height: 4),
                          if (isFree)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  loc.t("retargetingCostFree"),
                                  style: const TextStyle(
                                    fontSize: 28, fontWeight: FontWeight.w900,
                                    color: Color(0xFF22C55E),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF22C55E).withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: const Color(0xFF22C55E).withValues(alpha: 0.3)),
                                    ),
                                    child: Text(
                                      loc.t("retargetingCreditsLeft", {"count": creditsLeft.toString()}),
                                      style: const TextStyle(
                                        fontSize: 11, fontWeight: FontWeight.w700,
                                        color: Color(0xFF22C55E),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          else
                            RichText(
                              text: TextSpan(
                                children: [
                                  TextSpan(
                                    text: '$cost ',
                                    style: TextStyle(
                                      fontSize: 28, fontWeight: FontWeight.w900,
                                      color: AppColors.textPrimary(context),
                                    ),
                                  ),
                                  TextSpan(
                                    text: 'TUCi',
                                    style: TextStyle(
                                      fontSize: 14, fontWeight: FontWeight.w700,
                                      color: AppColors.textSecondary(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 2),
                          Text(
                            isFree
                                ? loc.t("retargetingFreeSubtitle", {"count": actualCount.toString()})
                                : loc.t("retargetingPaidSubtitle", {"count": actualCount.toString()}),
                            style: TextStyle(fontSize: 11, color: AppColors.textSecondary(context)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: (state.sent || state.blastCooldownSeconds > 0)
                      ? state.sent
                          ? _sentCard(loc, state)
                          : _cooldownCard(loc, state)
                      : Column(
                          children: [
                            ElevatedButton.icon(
                              onPressed: state.sending ? null : () => _sendBlast(state, viewModel),
                              icon: state.sending
                                  ? const SizedBox(
                                      width: 16, height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.send_outlined, size: 18),
                              label: Text(
                                state.sending ? loc.t("retargetingSending") : loc.t("retargetingSendBtnLabel", {"count": reachable.toString()}),
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF6366F1),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                minimumSize: const Size(double.infinity, 0),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  isFree ? Icons.stars_rounded : Icons.account_balance_wallet_outlined,
                                  size: 13,
                                  color: isFree ? const Color(0xFF22C55E) : AppColors.textSecondary(context),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  isFree
                                      ? loc.t("retargetingCreditsBadge", {"count": creditsLeft.toString()})
                                      : loc.t("retargetingCostBadge", {"cost": cost.toString()}),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isFree ? const Color(0xFF22C55E) : AppColors.textSecondary(context),
                                    fontWeight: isFree ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 10),
                Text(
                  loc.t("retargetingFootnote"),
                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary(context), height: 1.4),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _sentCard(TranslationPack loc, RetargetingState state) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF22C55E).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF22C55E).withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle, color: Color(0xFF22C55E), size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  loc.t("retargetingBlastSent", {"count": state.sentCount.toString()}),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF22C55E)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            loc.t("retargetingCooldownLabel"),
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary(context)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            _formatCooldown(state.blastCooldownSeconds),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF22C55E), fontFeatures: [FontFeature.tabularFigures()]),
          ),
        ],
      ),
    );
  }

  Widget _cooldownCard(TranslationPack loc, RetargetingState state) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.timer_outlined, color: Color(0xFFF59E0B), size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  loc.t("retargetingBlastCooldown"),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFF59E0B)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            loc.t("retargetingCooldownLabel"),
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary(context)),
          ),
          const SizedBox(height: 4),
          Text(
            _formatCooldown(state.blastCooldownSeconds),
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Color(0xFFF59E0B), fontFeatures: [FontFeature.tabularFigures()]),
          ),
        ],
      ),
    );
  }

  Widget _buildCampaignListingCarousel(RetargetingState state, RetargetingViewModel viewModel) {
    if (state.reportListings.isEmpty) return _emptyState();
    final filtered = _filteredCampaignListings(state);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 8),
          child: TeqFilterBar(
            filter: state.campaignFilter,
            onChanged: (f) => viewModel.updateCampaignFilter(f),
            showExtraFields: false,
            showCity: false,
            showCondition: false,
            showSort: false,
            showPriceRange: false,
          ),
        ),
        SizedBox(
          height: 112,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: filtered.isEmpty ? 1 : filtered.length,
            itemBuilder: (ctx, i) {
              if (filtered.isEmpty) {
                return Center(child: Text('—', style: TextStyle(color: AppColors.textSecondary(context))));
              }
              final item = filtered[i];
              final isSelected = state.selectedListing != null && item['id'] == state.selectedListing!['id'];
              final imageUrls = item['image_urls'] as List? ?? [];
              final rawImg = imageUrls.isNotEmpty ? imageUrls.first as String? : item['image_url'] as String?;
              final imageUrl = rawImg != null ? imgUrl(rawImg) : null;
              return GestureDetector(
                onTap: () => viewModel.selectCampaignListing(item),
                child: Container(
                  width: 128,
                  margin: const EdgeInsetsDirectional.only(end: 10),
                  decoration: BoxDecoration(
                    color: AppColors.card(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? const Color(0xFF14B8A6) : AppColors.border(context),
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        imageUrl != null
                            ? Image.network(imageUrl, fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Container(color: AppColors.border(context)))
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
                              decoration: const BoxDecoration(color: Color(0xFF14B8A6), shape: BoxShape.circle),
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
        ),
      ],
    );
  }

  Widget _emptyState() {
    final loc = ref.read(localizationProvider);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined, size: 56, color: AppColors.textSecondary(context)),
          const SizedBox(height: 12),
          Text(
            loc.t("retargetingNoListings"),
            style: TextStyle(fontSize: 15, color: AppColors.textSecondary(context)),
          ),
          const SizedBox(height: 6),
          Text(
            loc.t("retargetingNoListingsDesc"),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context)),
          ),
        ],
      ),
    );
  }
}
class _AudienceSkeleton extends ConsumerWidget {
  const _AudienceSkeleton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final base = AppColors.border(context);
    box(double h, {double? w, double r = 8}) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(r)),
        );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: base),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          box(14, w: 120),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: box(72, r: 10)), const SizedBox(width: 8),
            Expanded(child: box(72, r: 10)), const SizedBox(width: 8),
            Expanded(child: box(72, r: 10)),
          ]),
          const SizedBox(height: 16),
          box(50, r: 10),
        ],
      ),
    );
  }
}

// ── Kitle İstatistik Kutusu ───────────────────────────────────────────────────

class _AudienceStat extends ConsumerWidget {
  final String value;
  final String label;
  final Color color;

  const _AudienceStat({required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color),
            ),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary(context)),
            ),
          ],
        ),
      ),
    );
  }
}
