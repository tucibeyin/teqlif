import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import '../config/app_colors.dart';
import '../l10n/app_localizations.dart';
import '../services/analytics_service.dart';
import '../services/storage_service.dart';

class RetargetingScreen extends StatefulWidget {
  final int initialIndex;
  final bool isEmbedded;
  const RetargetingScreen({super.key, this.initialIndex = 0, this.isEmbedded = false});

  @override
  State<RetargetingScreen> createState() => _RetargetingScreenState();
}

class _RetargetingScreenState extends State<RetargetingScreen> {
  List<Map<String, dynamic>> _listings = [];
  Map<String, dynamic>? _selectedListing;
  Map<String, dynamic>? _audienceData;
  bool _loadingListings = true;
  bool _loadingAudience = false;
  bool _sending = false;
  bool _sent = false;
  int _sentCount = 0;

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
            _loadAudience();
          }
        });
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingListings = false);
  }

  Future<void> _loadAudience() async {
    final listing = _selectedListing;
    if (listing == null) return;
    setState(() {
      _loadingAudience = true;
      _audienceData = null;
      _sent = false;
    });
    final data = await AnalyticsService.retargetingAudience(listing['id'] as int);
    if (mounted) {
      setState(() {
        _audienceData = data;
        _loadingAudience = false;
      });
    }
  }

  Future<void> _sendBlast() async {
    final l = AppLocalizations.of(context)!;
    final listing = _selectedListing;
    final audience = _audienceData;
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

    // Senaryo 4: Yetersiz bakiye
    if (tuciCost > 0 && tuciBalance < tuciCost) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.card(context),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(l.retargetingDialogTitle,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary(context))),
          content: Text(
            l.retargetingDialogBodyInsufficient(tuciCost, tuciBalance),
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
              child: Text(l.btnDismiss, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
      return;
    }

    // Senaryo 1/2/3: Onay dialogu
    final String dialogBody;
    if (freeUsed > 0 && paidCount == 0) {
      dialogBody = l.retargetingDialogBodyFree(actualCount, freeUsed);
    } else if (freeUsed > 0 && paidCount > 0) {
      dialogBody = l.retargetingDialogBodyKarma(actualCount, freeUsed, tuciCost);
    } else {
      dialogBody = l.retargetingDialogBodyPaid(actualCount, tuciCost);
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          l.retargetingDialogTitle,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary(context)),
        ),
        content: Text(
          dialogBody,
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary(context), height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.btnDismiss, style: TextStyle(color: AppColors.textSecondary(context))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(l.btnSend, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _sending = true);
    final result = await AnalyticsService.sendRetargeting(
      listingId: listing['id'] as int,
      estimatedAudience: actualCount,
      estimatedCost: tuciCost,
      recipientCount: actualCount,
    );
    if (!mounted) return;
    setState(() => _sending = false);

    if (result != null && result['error'] == null) {
      final sent = result['sent'] as int? ?? actualCount;
      setState(() { _sent = true; _sentCount = sent; });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.retargetingBlastSuccess),
          backgroundColor: const Color(0xFF22C55E),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } else {
      final errMsg = result?['error'] as String? ?? 'Bir sorun oluştu, lütfen tekrar dene.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errMsg),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Bildirim Raporu Sekmesi (Gerçek Veri)
    final Widget reportTab = FutureBuilder<Map<String, dynamic>>(
      future: AnalyticsService.getMassNotificationReport(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text('${AppLocalizations.of(context)!.reportLoadError}${snapshot.error}', 
              style: TextStyle(color: AppColors.textSecondary(context)))
          );
        }
        final data = snapshot.data ?? {};
        final target = data['total_target'] as int? ?? 0;
        final sent = data['total_sent'] as int? ?? 0;
        final clicks = data['total_clicks'] as int? ?? 0;
        final spent = data['total_spent_tuci'] as int? ?? 0;
        final costPerClick = clicks > 0 ? (spent / clicks).round() : 0;
        final clickRate = sent > 0 ? ((clicks / sent) * 100).toStringAsFixed(1) : '0.0';

        return ListView(shrinkWrap: widget.isEmbedded, physics: widget.isEmbedded ? const NeverScrollableScrollPhysics() : null,
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              AppLocalizations.of(context)!.reportMassNotificationTitle,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.reportMassNotificationDesc,
              style: TextStyle(color: AppColors.textSecondary(context)),
            ),
            const SizedBox(height: 24),
            if (target == 0)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32.0),
                  child: Text(AppLocalizations.of(context)!.reportNoNotificationYet,
                    style: TextStyle(color: AppColors.textSecondary(context))),
                ),
              )
            else ...[
              _buildFunnelCard(AppLocalizations.of(context)!.reportConversionFunnel, [
                {'label': '📢 ${AppLocalizations.of(context)!.reportTargetAudience}', 'value': '$target'},
                {'label': '📩 ${AppLocalizations.of(context)!.reportSuccessfullyDelivered}', 'value': '$sent'},
                {'label': '👆 ${AppLocalizations.of(context)!.reportClickOpen}', 'value': '$clicks  (%$clickRate)'},
              ]),
              const SizedBox(height: 16),
              _buildROICard(AppLocalizations.of(context)!.reportROI, '$spent TUCi', '$costPerClick TUCi / Tıklama'),
            ],
          ],
        );
      },
    );

    // Mevcut Retargeting Sekmesi
    final Widget retargetingTab = _loadingListings
        ? const Center(child: CircularProgressIndicator())
        : _listings.isEmpty
            ? _emptyState()
            : ListView(shrinkWrap: widget.isEmbedded, physics: widget.isEmbedded ? const NeverScrollableScrollPhysics() : null,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                children: [
                  _infoCard(),
                  const SizedBox(height: 16),
                  _ListingPicker(
                    listings: _listings,
                    selected: _selectedListing!,
                    onChanged: (listing) {
                      setState(() => _selectedListing = listing);
                      _loadAudience();
                    },
                  ),
                  const SizedBox(height: 20),
                  if (_loadingAudience)
                    const _AudienceSkeleton()
                  else if (_audienceData != null)
                    _audienceCard(),
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
          title: Text(AppLocalizations.of(context)!.centerNotificationAudience),
          backgroundColor: AppColors.bg(context),
          elevation: 0,
          bottom: const TabBar(
            indicatorColor: Color(0xFF14B8A6),
            labelColor: Color(0xFF14B8A6),
            unselectedLabelColor: Colors.grey,
            tabs: [
              Tab(icon: Icon(Icons.touch_app), text: 'Retargeting'),
              Tab(icon: Icon(Icons.auto_graph), text: 'Raporlar'),
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
              Text(AppLocalizations.of(context)!.reportTotalSpent, style: TextStyle(color: Colors.white70)),
              Text(totalSpend, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(AppLocalizations.of(context)!.reportCostPerClick, style: TextStyle(color: Colors.white70)),
              Text(costPerClick, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoCard() {
    final l = AppLocalizations.of(context)!;
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
              l.retargetingInfoText,
              style: TextStyle(fontSize: 12, color: AppColors.textPrimary(context), height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _audienceCard() {
    final l = AppLocalizations.of(context)!;
    final audience = _audienceData!;
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
        // Kitap istatistikleri
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
                    l.retargetingLast30Days,
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
                    label: l.retargetingViewerLabel,
                    color: AppColors.textPrimary(context),
                  ),
                  const SizedBox(width: 8),
                  _AudienceStat(
                    value: '$alreadyBought',
                    label: l.retargetingBoughtLabel,
                    color: const Color(0xFF22C55E),
                  ),
                  const SizedBox(width: 8),
                  _AudienceStat(
                    value: '$reachable',
                    label: l.retargetingReachableLabel,
                    color: const Color(0xFF6366F1),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Maliyet & gönder
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
                          l.retargetingNoAudience,
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary(context)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l.retargetingNoAudienceDesc,
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
                            l.retargetingEstimatedCost,
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context)),
                          ),
                          const SizedBox(height: 4),
                          if (isFree)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  l.retargetingCostFree,
                                  style: TextStyle(
                                    fontSize: 28, fontWeight: FontWeight.w900,
                                    color: const Color(0xFF22C55E),
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
                                      l.retargetingCreditsLeft(creditsLeft),
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
                                ? l.retargetingFreeSubtitle(actualCount)
                                : l.retargetingPaidSubtitle(actualCount),
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
                  child: _sent
                      ? Container(
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
                                  Text(
                                    AppLocalizations.of(context)!.retargetingBlastSent(_sentCount),
                                    style: const TextStyle(
                                      fontSize: 14, fontWeight: FontWeight.w700,
                                      color: Color(0xFF22C55E),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                AppLocalizations.of(context)!.retargetingBlastCooldown,
                                style: TextStyle(fontSize: 11, color: AppColors.textSecondary(context)),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      : Column(
                          children: [
                            ElevatedButton.icon(
                              onPressed: _sending ? null : _sendBlast,
                              icon: _sending
                                  ? const SizedBox(
                                      width: 16, height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.send_outlined, size: 18),
                              label: Text(
                                _sending ? l.retargetingSending : l.retargetingSendBtnLabel(reachable),
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
                                      ? l.retargetingCreditsBadge(creditsLeft)
                                      : l.retargetingCostBadge(cost),
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
                  l.retargetingFootnote,
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

  Widget _emptyState() {
    final l = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined, size: 56, color: AppColors.textSecondary(context)),
          const SizedBox(height: 12),
          Text(
            l.retargetingNoListings,
            style: TextStyle(fontSize: 15, color: AppColors.textSecondary(context)),
          ),
          const SizedBox(height: 6),
          Text(
            l.retargetingNoListingsDesc,
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

  const _ListingPicker({required this.listings, required this.selected, required this.onChanged});

  static const double _itemH = 62;
  static const int _maxVisible = 5;

  @override
  Widget build(BuildContext context) {
    final visibleCount = listings.length.clamp(1, _maxVisible);
    return Container(
      height: visibleCount * _itemH,
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ListView.separated(
          physics: const ClampingScrollPhysics(),
          itemCount: listings.length,
          separatorBuilder: (ctx2, i2) => Divider(height: 1, thickness: 1, color: AppColors.border(ctx2)),
          itemBuilder: (ctx, i) {
            final l = listings[i];
            final isSelected = l['id'] == selected['id'];
            final price = l['price'];
            return InkWell(
              onTap: () => onChanged(l),
              child: Container(
                height: _itemH,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                color: isSelected ? const Color(0xFF6366F1).withValues(alpha: 0.08) : Colors.transparent,
                child: Row(
                  children: [
                    Icon(
                      isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      size: 18,
                      color: isSelected ? const Color(0xFF6366F1) : AppColors.textSecondary(ctx),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        l['title'] as String? ?? '—',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          color: AppColors.textPrimary(ctx),
                        ),
                      ),
                    ),
                    if (price != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        '${NumberFormat('#,##0', 'tr_TR').format((price as num).toDouble())} ₺',
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary(ctx)),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ── Audience Skeleton ─────────────────────────────────────────────────────────

class _AudienceSkeleton extends StatelessWidget {
  const _AudienceSkeleton();

  @override
  Widget build(BuildContext context) {
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

class _AudienceStat extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _AudienceStat({required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
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
