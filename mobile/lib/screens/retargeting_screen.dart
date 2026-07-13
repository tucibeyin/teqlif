import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../config/theme.dart';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import '../config/app_colors.dart';
import '../l10n/app_localizations.dart';
import '../services/analytics_service.dart';
import '../services/cache_service.dart';
import '../services/category_service.dart';
import '../services/storage_service.dart';

class RetargetingScreen extends StatefulWidget {
  final int initialIndex;
  final bool isEmbedded;
  final int? listingId;

  const RetargetingScreen({super.key, this.initialIndex = 0, this.isEmbedded = false, this.listingId});

  @override
  State<RetargetingScreen> createState() => _RetargetingScreenState();
}

class _RetargetingScreenState extends State<RetargetingScreen> {
  Map<String, dynamic>? _selectedListing;
  Map<String, dynamic>? _audienceData;
  bool _loadingAudience = false;
  bool _sending = false;
  bool _sent = false;
  int _sentCount = 0;
  int _blastCooldownSeconds = 0;
  Timer? _countdownTimer;

  // Rapor sekmesi state
  int? _selectedReportListingId;
  List<Map<String, dynamic>> _reportListings = [];
  Future<Map<String, dynamic>>? _reportFuture;
  final TextEditingController _reportSearchCtrl = TextEditingController();
  String _reportQuery = '';
  DateTimeRange? _dateRange;
  String? _reportCategoryFilter;

  // Retargeting sekmesi filtreler
  final TextEditingController _retargetSearchCtrl = TextEditingController();
  String _retargetQuery = '';
  String? _retargetCategoryFilter;
  DateTimeRange? _retargetDateRange;

  // Ortak kategori listesi
  List<(String, String)>? _categories;

  List<Map<String, dynamic>> get _filteredReportListings {
    var result = _reportListings;
    if (_reportQuery.isNotEmpty) {
      result = result.where((l) =>
        (l['title'] as String? ?? '').toLowerCase().contains(_reportQuery.toLowerCase())
      ).toList();
    }
    if (_dateRange != null) {
      final start = _dateRange!.start;
      final end = _dateRange!.end.add(const Duration(days: 1));
      result = result.where((item) {
        final raw = item['created_at'] as String?;
        if (raw == null) return false;
        final dt = DateTime.tryParse(raw)?.toLocal();
        return dt != null && !dt.isBefore(start) && dt.isBefore(end);
      }).toList();
    }
    if (_reportCategoryFilter != null) {
      result = result.where((l) => l['category'] == _reportCategoryFilter).toList();
    }
    return result;
  }

  List<Map<String, dynamic>> get _filteredCampaignListings {
    var result = _reportListings;
    if (_retargetQuery.isNotEmpty) {
      final q = _retargetQuery.toLowerCase();
      result = result.where((l) =>
        (l['title'] as String? ?? '').toLowerCase().contains(q)
      ).toList();
    }
    if (_retargetCategoryFilter != null) {
      result = result.where((l) => l['category'] == _retargetCategoryFilter).toList();
    }
    if (_retargetDateRange != null) {
      final start = _retargetDateRange!.start;
      final end = _retargetDateRange!.end.add(const Duration(days: 1));
      result = result.where((item) {
        final raw = item['created_at'] as String?;
        if (raw == null) return false;
        final dt = DateTime.tryParse(raw)?.toLocal();
        return dt != null && !dt.isBefore(start) && dt.isBefore(end);
      }).toList();
    }
    return result;
  }

  @override
  void initState() {
    super.initState();
    _selectedReportListingId = widget.listingId;
    _reportFuture = AnalyticsService.getMassNotificationReport(listingId: _selectedReportListingId);
    _loadReportListings();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_categories == null) {
      CategoryService.getCategories(locale: Localizations.localeOf(context).languageCode)
          .then((cats) { if (mounted) setState(() => _categories = cats); });
    }
  }

  Future<void> _loadReportListings() async {
    final listings = await _fetchListingsPage(0);
    if (mounted) {
      setState(() => _reportListings = listings);
      if (_selectedListing == null && listings.isNotEmpty) {
        setState(() => _selectedListing = listings.first);
        _loadAudience();
      }
    }
  }

  void _selectReportListing(int? listingId) {
    setState(() {
      _selectedReportListingId = listingId;
      _reportFuture = AnalyticsService.getMassNotificationReport(listingId: listingId);
    });
  }

  Future<List<Map<String, dynamic>>> _fetchListingsPage(int offset) async {
    final token = await StorageService.getToken();
    if (token == null) return [];
    final resp = await http.get(
      Uri.parse('$kBaseUrl/listings/my?limit=20&offset=$offset&active=true'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (resp.statusCode == 200) {
      return (jsonDecode(resp.body) as List).cast<Map<String, dynamic>>();
    }
    return [];
  }

  Future<void> _loadAudience() async {
    final listing = _selectedListing;
    if (listing == null) return;
    setState(() {
      _loadingAudience = true;
      _audienceData = null;
      _sent = false;
      _blastCooldownSeconds = 0;
    });
    final listingId = listing['id'] as int;
    final results = await Future.wait([
      AnalyticsService.retargetingAudience(listingId),
      AnalyticsService.getNotificationCooldown(listingId),
    ]);
    if (mounted) {
      final cooldown = (results[1] as int?) ?? 0;
      setState(() {
        _audienceData = results[0] as Map<String, dynamic>?;
        _blastCooldownSeconds = cooldown;
        _loadingAudience = false;
      });
      if (cooldown > 0) _startCountdown();
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) { _countdownTimer?.cancel(); return; }
      setState(() {
        if (_blastCooldownSeconds > 0) {
          _blastCooldownSeconds--;
        } else {
          _countdownTimer?.cancel();
          _sent = false;
        }
      });
    });
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

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _reportSearchCtrl.dispose();
    _retargetSearchCtrl.dispose();
    super.dispose();
  }

  // ── Rapor: İlan Kartu Karuseli ───────────────────────────────────────────
  String _fmtDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';

  Widget _buildListingCarousel() {
    final l = AppLocalizations.of(context)!;
    final filtered = _filteredReportListings;
    final hasRange = _dateRange != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            controller: _reportSearchCtrl,
            decoration: InputDecoration(
              hintText: l.searchHintTextListing,
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _reportQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _reportSearchCtrl.clear();
                        setState(() => _reportQuery = '');
                      },
                    )
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onChanged: (v) => setState(() => _reportQuery = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: InkWell(
            onTap: () async {
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
                initialDateRange: _dateRange,
                locale: Localizations.localeOf(context),
              );
              if (picked != null) setState(() => _dateRange = picked);
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: hasRange ? const Color(0xFF14B8A6) : AppColors.border(context)),
                borderRadius: BorderRadius.circular(8),
                color: hasRange ? const Color(0xFF14B8A6).withValues(alpha: 0.08) : null,
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today_outlined, size: 16,
                      color: hasRange ? const Color(0xFF14B8A6) : AppColors.textSecondary(context)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      hasRange
                          ? '${_fmtDate(_dateRange!.start)} – ${_fmtDate(_dateRange!.end)}'
                          : l.filterSelectDate,
                      style: TextStyle(fontSize: 13,
                          color: hasRange ? const Color(0xFF14B8A6) : AppColors.textSecondary(context)),
                    ),
                  ),
                  if (hasRange)
                    GestureDetector(
                      onTap: () => setState(() => _dateRange = null),
                      child: const Icon(Icons.close, size: 16, color: Color(0xFF14B8A6)),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (_categories != null && _categories!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _catChip(l.filterAll, _reportCategoryFilter == null,
                      () => setState(() => _reportCategoryFilter = null)),
                  ..._categories!.map((c) => _catChip(c.$2, _reportCategoryFilter == c.$1,
                      () => setState(() => _reportCategoryFilter = _reportCategoryFilter == c.$1 ? null : c.$1))),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        SizedBox(
          height: 112,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: filtered.length + 1,
            itemBuilder: (ctx, i) {
              if (i == 0) {
            final sel = _selectedReportListingId == null;
            return GestureDetector(
              onTap: () => _selectReportListing(null),
              child: Container(
                width: 88,
                margin: const EdgeInsets.only(right: 10),
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
                    Text(AppLocalizations.of(context)!.reportAll,
                      style: TextStyle(color: sel ? const Color(0xFF14B8A6) : AppColors.textSecondary(context),
                        fontWeight: sel ? FontWeight.bold : FontWeight.normal, fontSize: 13)),
                  ],
                ),
              ),
            );
          }
          final listing = filtered[i - 1];
          final lid = listing['id'] as int;
          final sel = _selectedReportListingId == lid;
          final imageUrls = listing['image_urls'] as List? ?? [];
          final imageUrl = imageUrls.isNotEmpty ? imgUrl(imageUrls.first as String) : null;
          final title = listing['title'] as String? ?? '';
          return GestureDetector(
            onTap: () => _selectReportListing(lid),
            child: Container(
              width: 128,
              margin: const EdgeInsets.only(right: 10),
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

  // ── Rapor: İçerik (özet + kampanya geçmişi) ──────────────────────────────
  Widget _buildReportContent(Map<String, dynamic> data) {
    final l = AppLocalizations.of(context)!;
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
        child: Center(child: Text(l.reportNoNotificationYet, style: TextStyle(color: AppColors.textSecondary(context)))),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFunnelCard(l.reportConversionFunnel, [
            {'label': '📢 ${l.reportTargetAudience}', 'value': '$target'},
            {'label': '📩 ${l.reportSuccessfullyDelivered}', 'value': '$sent'},
            {'label': '👆 ${l.reportClickOpen}', 'value': '$clicks  (%$clickRate)'},
          ]),
          const SizedBox(height: 16),
          _buildROICard(l.reportROI, '$spent TUCi', '$costPerClick TUCi / ${l.adReportMetricClicks}'),
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
    final l = AppLocalizations.of(context)!;
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
            Expanded(child: _statChip('📢', '$targetCount', l.reportTargetAudience)),
            Expanded(child: _statChip('📩', '$sentCount', l.reportSuccessfullyDelivered)),
            Expanded(child: _statChip('👆', '$clickCount (%$clickRate)', l.reportClickOpen)),
          ]),
          if (spentTuci > 0 || freeCredits > 0) ...[
            const SizedBox(height: 8),
            Row(children: [
              if (freeCredits > 0)
                Text('$freeCredits ${l.reportFreeCreditsUsed}',
                  style: TextStyle(color: AppColors.textSecondary(context), fontSize: 11)),
              if (freeCredits > 0 && spentTuci > 0)
                Text('  •  ', style: TextStyle(color: AppColors.textSecondary(context), fontSize: 11)),
              if (spentTuci > 0)
                Text('$spentTuci TUCi ${l.reportTotalSpent}',
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
      CacheService.clearData('user_wallet_data');
      final sent = result['sent'] as int? ?? actualCount;
      setState(() { _sent = true; _sentCount = sent; _blastCooldownSeconds = 86400; });
      _startCountdown();
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
    // Bildirim Raporu Sekmesi
    final Widget reportTab = FutureBuilder<Map<String, dynamic>>(
      future: _reportFuture,
      builder: (context, snapshot) {
        final l = AppLocalizations.of(context)!;
        return ListView(
          shrinkWrap: widget.isEmbedded,
          physics: widget.isEmbedded ? const NeverScrollableScrollPhysics() : null,
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(l.reportMassNotificationTitle,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(l.reportMassNotificationDesc,
                style: TextStyle(color: AppColors.textSecondary(context))),
            ),
            _buildListingCarousel(),
            const SizedBox(height: 16),
            if (snapshot.connectionState == ConnectionState.waiting)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (snapshot.hasError)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('${l.reportLoadError}${snapshot.error}',
                  style: TextStyle(color: AppColors.textSecondary(context))),
              )
            else
              _buildReportContent(snapshot.data ?? {}),
            const SizedBox(height: 32),
          ],
        );
      },
    );

    // Mevcut Retargeting Sekmesi
    final Widget retargetingTab = ListView(shrinkWrap: widget.isEmbedded, physics: widget.isEmbedded ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      children: [
        _infoCard(),
        const SizedBox(height: 16),
        _buildCampaignListingCarousel(),
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
            TabBar(
              indicatorColor: const Color(0xFF14B8A6),
              labelColor: const Color(0xFF14B8A6),
              unselectedLabelColor: Colors.grey,
              tabs: [
                const Tab(icon: Icon(Icons.touch_app), text: 'Retargeting'),
                Tab(icon: const Icon(Icons.auto_graph), text: AppLocalizations.of(context)!.tabReports),
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
          bottom: TabBar(
            indicatorColor: const Color(0xFF14B8A6),
            labelColor: const Color(0xFF14B8A6),
            unselectedLabelColor: Colors.grey,
            tabs: [
              const Tab(icon: Icon(Icons.touch_app), text: 'Retargeting'),
              Tab(icon: const Icon(Icons.auto_graph), text: AppLocalizations.of(context)!.tabReports),
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
                  child: (_sent || _blastCooldownSeconds > 0)
                      ? _sent
                          ? _sentCard(l)
                          : _cooldownCard(l)
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

  Widget _sentCard(AppLocalizations l) {
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
                  l.retargetingBlastSent(_sentCount),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF22C55E)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l.retargetingCooldownLabel,
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary(context)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            _formatCooldown(_blastCooldownSeconds),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF22C55E), fontFeatures: [FontFeature.tabularFigures()]),
          ),
        ],
      ),
    );
  }

  Widget _cooldownCard(AppLocalizations l) {
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
                  l.retargetingBlastCooldown,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFF59E0B)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l.retargetingCooldownLabel,
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary(context)),
          ),
          const SizedBox(height: 4),
          Text(
            _formatCooldown(_blastCooldownSeconds),
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Color(0xFFF59E0B), fontFeatures: [FontFeature.tabularFigures()]),
          ),
        ],
      ),
    );
  }

  Widget _catChip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? kPrimary : AppColors.card(context),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? kPrimary : AppColors.border(context)),
          ),
          child: Text(label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? Colors.white : AppColors.textPrimary(context),
              )),
        ),
      ),
    );
  }

  Widget _buildCampaignListingCarousel() {
    final l = AppLocalizations.of(context)!;
    if (_reportListings.isEmpty) return _emptyState();
    final filtered = _filteredCampaignListings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            controller: _retargetSearchCtrl,
            decoration: InputDecoration(
              hintText: l.searchHintTextListing,
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _retargetQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () { _retargetSearchCtrl.clear(); setState(() => _retargetQuery = ''); },
                    )
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onChanged: (v) => setState(() => _retargetQuery = v.trim()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: InkWell(
            onTap: () async {
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
                initialDateRange: _retargetDateRange,
                locale: Localizations.localeOf(context),
              );
              if (picked != null) setState(() => _retargetDateRange = picked);
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: _retargetDateRange != null ? const Color(0xFF14B8A6) : AppColors.border(context)),
                borderRadius: BorderRadius.circular(8),
                color: _retargetDateRange != null ? const Color(0xFF14B8A6).withValues(alpha: 0.08) : null,
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today_outlined, size: 16,
                      color: _retargetDateRange != null ? const Color(0xFF14B8A6) : AppColors.textSecondary(context)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _retargetDateRange != null
                          ? '${_fmtDate(_retargetDateRange!.start)} – ${_fmtDate(_retargetDateRange!.end)}'
                          : l.filterSelectDate,
                      style: TextStyle(fontSize: 13,
                          color: _retargetDateRange != null ? const Color(0xFF14B8A6) : AppColors.textSecondary(context)),
                    ),
                  ),
                  if (_retargetDateRange != null)
                    GestureDetector(
                      onTap: () => setState(() => _retargetDateRange = null),
                      child: const Icon(Icons.close, size: 16, color: Color(0xFF14B8A6)),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (_categories != null && _categories!.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _catChip(l.filterAll, _retargetCategoryFilter == null,
                      () => setState(() => _retargetCategoryFilter = null)),
                  ..._categories!.map((c) => _catChip(c.$2, _retargetCategoryFilter == c.$1,
                      () => setState(() => _retargetCategoryFilter = _retargetCategoryFilter == c.$1 ? null : c.$1))),
                ],
              ),
            ),
          ),
        ],
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
          final isSelected = _selectedListing != null && item['id'] == _selectedListing!['id'];
          final imageUrls = item['image_urls'] as List? ?? [];
          final rawImg = imageUrls.isNotEmpty ? imageUrls.first as String? : item['image_url'] as String?;
          final imageUrl = rawImg != null ? imgUrl(rawImg) : null;
          return GestureDetector(
            onTap: () {
              if (!isSelected) {
                setState(() => _selectedListing = item);
                _loadAudience();
              }
            },
            child: Container(
              width: 128,
              margin: const EdgeInsets.only(right: 10),
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
