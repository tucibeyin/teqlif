import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_colors.dart';
import '../l10n/app_localizations.dart';
import '../services/analytics_service.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';
import 'competitor_radar_screen.dart';
import 'demand_trends_screen.dart';
import 'listing_analytics_screen.dart';
import 'market_intelligence_screen.dart';
import 'pro_insights_screen.dart';
import 'pro_stream_analytics_screen.dart';
import 'retargeting_screen.dart';
import 'live_stream_history_screen.dart';

class ProHubScreen extends StatefulWidget {
  final bool isPremium;

  const ProHubScreen({super.key, required this.isPremium});

  @override
  State<ProHubScreen> createState() => _ProHubScreenState();
}

class _ProHubScreenState extends State<ProHubScreen> {
  Map<String, dynamic>? _credits;
  Map<String, dynamic>? _boostCredits;
  Map<String, dynamic>? _aiCredits;
  Map<String, dynamic>? _reactivationCredits;
  bool _isLoading = true;
  bool _isPremium = false;
  String? _planType;

  @override
  void initState() {
    super.initState();
    _isPremium = widget.isPremium;
    _loadCredits();
    _verifyPremium();
    _loadLocalPlanType();
    AnalyticsService.trackEvent('pro_hub_view', {'is_premium': widget.isPremium});
  }

  Future<void> _loadLocalPlanType() async {
    final info = await StorageService.getUserInfo();
    if (info != null && mounted) {
      setState(() => _planType = info['plan_type'] as String?);
    }
  }

  Future<void> _verifyPremium() async {
    try {
      final user = await AuthService.me();
      if (mounted) {
        if (user.isPremium != _isPremium || user.planType != _planType) {
          setState(() {
            _isPremium = user.isPremium;
            _planType = user.planType;
          });
        }
        // Profil bilgisini locale kaydet ki kalıcı olsun
        await StorageService.saveUserInfo(
          id: user.id,
          email: user.email,
          username: user.username,
          fullName: user.fullName,
          isPremium: user.isPremium,
          planType: user.planType,
          onboardingCompleted: user.onboardingCompleted,
          isVerified: user.isVerified,
          phoneVerified: user.phoneVerified,
        );
      }
    } catch (_) {}
  }

  Future<void> _loadCredits() async {
    if (mounted) setState(() => _isLoading = true);
    final results = await Future.wait([
      AnalyticsService.getBlastCredits(),
      AnalyticsService.getBoostCredits(),
      AnalyticsService.getAiPriceCredits(),
      AnalyticsService.getReactivationCredits(),
    ]);

    if (mounted) {
      setState(() {
        _credits             = results[0];
        _boostCredits        = results[1];
        _aiCredits           = results[2];
        _reactivationCredits = results[3];
        _isLoading           = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final isPremium = _isPremium;
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        title: Text(l.proHubTitle),
        backgroundColor: AppColors.bg(context),
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _loadCredits,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // ── Durum Kartı ────────────────────────────────────────────────────
          if (isPremium) _ProStatusCard(renewalDate: _credits?['renewal_date'] as String?, planType: _planType) else _UpgradeBanner(),
          const SizedBox(height: 24),
          _CreditsSummaryCard(
            blastCredits: _credits,
            boostCredits: _boostCredits,
            aiCredits: _aiCredits,
            reactivationCredits: _reactivationCredits,
            isPremium: isPremium,
            isLoading: _isLoading,
          ),
          const SizedBox(height: 24),
          // ── Araçlar Başlığı ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 12),
            child: Text(
              l.proHubTitle,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary(context),
                letterSpacing: 0.6,
              ),
            ),
          ),

          // ── 1. Satış & Performans ──────────────────────────────────────────
          _buildAccordion(
            context: context,
            title: l.proHubTabSales,
            icon: Icons.trending_up,
            iconColor: const Color(0xFF6366F1),
            children: [
              _ToolCard(
                icon: Icons.auto_graph_outlined,
                iconColor: const Color(0xFF6366F1),
                title: l.proToolSalesTitle,
                description: l.proToolSalesDesc,
                isPremium: isPremium,
                onTap: isPremium
                    ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProInsightsScreen()))
                    : () => _showUpgrade(context),
              ),
              const SizedBox(height: 10),
              _ToolCard(
                icon: Icons.bar_chart_outlined,
                iconColor: const Color(0xFF10B981),
                title: l.proToolListingsTitle,
                description: l.proToolListingsDesc,
                isPremium: isPremium,
                onTap: isPremium
                    ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => ListingAnalyticsScreen(isPremium: isPremium)))
                    : () => _showUpgrade(context),
              ),
              const SizedBox(height: 10),
              _ToolCard(
                icon: Icons.pie_chart_outline,
                iconColor: const Color(0xFFEC4899),
                title: l.proToolConversionTitle,
                description: l.proToolConversionDesc,
                isPremium: isPremium,
                onTap: isPremium
                    ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ConversionBreakdownScreen()))
                    : () => _showUpgrade(context),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── 2. Piyasa & Rekabet ────────────────────────────────────────────
          _buildAccordion(
            context: context,
            title: l.proHubTabMarket,
            icon: Icons.public,
            iconColor: const Color(0xFFF59E0B),
            children: [
              _ToolCard(
                icon: Icons.insights_outlined,
                iconColor: const Color(0xFFF59E0B),
                title: l.proToolMarketTitle,
                description: l.proToolMarketDesc,
                isPremium: isPremium,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => MarketIntelligenceScreen(isPremium: isPremium)),
                ),
              ),
              const SizedBox(height: 10),
              _ToolCard(
                icon: Icons.trending_up_outlined,
                iconColor: const Color(0xFF10B981),
                title: l.proToolDemandTrendsTitle,
                description: l.proToolDemandTrendsDesc,
                isPremium: isPremium,
                onTap: isPremium
                    ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DemandTrendsScreen()))
                    : () => _showUpgrade(context),
              ),
              const SizedBox(height: 10),
              _ToolCard(
                icon: Icons.radar,
                iconColor: const Color(0xFF6366F1),
                title: l.proToolCompetitorRadarTitle,
                description: l.proToolCompetitorRadarDesc,
                isPremium: isPremium,
                onTap: isPremium
                    ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CompetitorRadarScreen()))
                    : () => _showUpgrade(context),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── 3. Canlı Yayın & Kitle ─────────────────────────────────────────
          _buildAccordion(
            context: context,
            title: l.proHubTabAudience,
            icon: Icons.stream,
            iconColor: const Color(0xFF14B8A6),
            children: [
              _ToolCard(
                icon: Icons.schedule_outlined,
                iconColor: const Color(0xFF8B5CF6),
                title: l.proToolBestTimeTitle,
                description: l.proToolBestTimeDesc,
                isPremium: isPremium,
                onTap: isPremium
                    ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BestStreamTimeScreen()))
                    : () => _showUpgrade(context),
              ),
              const SizedBox(height: 10),
              _ToolCard(
                icon: Icons.stream_outlined,
                iconColor: const Color(0xFF14B8A6),
                title: l.proToolStreamAnalyticsTitle,
                description: l.proToolStreamAnalyticsDesc,
                isPremium: isPremium,
                onTap: isPremium
                    ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LiveStreamHistoryScreen()))
                    : () => _showUpgrade(context),
              ),
              const SizedBox(height: 10),
              _ToolCard(
                icon: Icons.mark_email_unread_outlined,
                iconColor: const Color(0xFF0EA5E9),
                title: l.proToolRetargetingTitle,
                description: l.proToolRetargetingDesc,
                isPremium: isPremium,
                onTap: isPremium
                    ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RetargetingScreen(initialIndex: 0)))
                    : () => _showUpgrade(context),
              ),
            ],
          ),



          if (!isPremium) ...[
            const SizedBox(height: 28),
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 12),
              child: Text(
                l.proBenefitsTitle,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary(context),
                  letterSpacing: 0.6,
                ),
              ),
            ),
            _BenefitRow(icon: Icons.insights_outlined,      text: l.proBenefit1),
            _BenefitRow(icon: Icons.bar_chart_outlined,     text: l.proBenefit2),
            _BenefitRow(icon: Icons.schedule_outlined,      text: l.proBenefit3),
            _BenefitRow(icon: Icons.search_outlined,        text: l.proBenefit4),
          ],
        ],
        ),
      ),
    );
  }

  Widget _buildAccordion({
    required BuildContext context,
    required String title,
    required IconData icon,
    required Color iconColor,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          title: Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary(context),
            ),
          ),
          iconColor: AppColors.textSecondary(context),
          collapsedIconColor: AppColors.textSecondary(context),
          children: children,
        ),
      ),
    );
  }

  void _showUpgrade(BuildContext context) {
    AnalyticsService.trackEvent('pro_upgrade_intent', {});
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _UpgradeSheet(),
    );
  }
}

// ── Durum Kartları ─────────────────────────────────────────────────────────────

class _ProStatusCard extends StatelessWidget {
  final String? renewalDate;
  final String? planType;
  const _ProStatusCard({this.renewalDate, this.planType});

  String _getPlanName(AppLocalizations l, String? type) {
    switch (type) {
      case 'yearly': return l.planYearly;
      case 'lifetime': return l.planLifetime;
      default: return l.planMonthly;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E1B4B), Color(0xFF312E81)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.workspace_premium, color: Color(0xFF06B6D4), size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      l.proStatusTitle,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    if (planType != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _getPlanName(l, planType),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  l.proStatusDesc,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                ),
                if (renewalDate != null) ...[
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Icon(Icons.event_repeat_outlined, size: 11, color: Colors.white.withValues(alpha: 0.55)),
                      const SizedBox(width: 4),
                      Text(
                        l.proRenewalDate(_fmtRenewal(context, renewalDate)),
                        style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.55)),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UpgradeBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF92400E), Color(0xFFB45309)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.lock_outline, color: Color(0xFF06B6D4), size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.proUnlockTitle,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white),
                ),
                const SizedBox(height: 3),
                Text(
                  l.proUnlockDesc,
                  style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.8)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => launchUrl(
              Uri.parse('https://www.teqlif.com/pro-plan.html'),
              mode: LaunchMode.inAppWebView,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFF06B6D4),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                l.proUnlockBtn,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.black),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Araç Kartı ─────────────────────────────────────────────────────────────────

class _ToolCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;
  final bool isPremium;
  final VoidCallback onTap;

  const _ToolCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
    required this.isPremium,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border(context)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (!isPremium)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFB800),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(AppLocalizations.of(context)!.pro, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white)),
              )
            else
              Icon(Icons.chevron_right, color: AppColors.textSecondary(context), size: 20),
          ],
        ),
      ),
    );
  }
}

// ── Benefit Row ────────────────────────────────────────────────────────────────

class _BenefitRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _BenefitRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF6366F1)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: AppColors.textPrimary(context)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Yükseltme Bottom Sheet ─────────────────────────────────────────────────────

class _UpgradeSheet extends StatelessWidget {
  const _UpgradeSheet();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border(context),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          const Icon(Icons.workspace_premium, size: 48, color: Color(0xFFFFB800)),
          const SizedBox(height: 12),
          Text(
            l.proUpgradeTitle,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l.proUpgradeSheetDesc,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary(context), height: 1.5),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF0891B2), Color(0xFF06B6D4)]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  launchUrl(
                    Uri.parse('https://www.teqlif.com/pro-plan.html'),
                    mode: LaunchMode.inAppWebView,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  l.proUpgradeBtn,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Colors.white),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.btnDismiss, style: TextStyle(color: AppColors.textSecondary(context))),
          ),
        ],
      ),
    );
  }
}

// ── Kapsülleyici Model Sınıfı ───────────────────────────────────────────────
class CreditItemModel {
  final IconData icon;
  final Color iconColor;
  final String Function(AppLocalizations) titleBuilder;
  final String Function(AppLocalizations) descBuilder;
  final Map<String, dynamic>? data;
  final int defaultPremiumLimit;
  final int defaultFreeLimit;

  CreditItemModel({
    required this.icon,
    required this.iconColor,
    required this.titleBuilder,
    required this.descBuilder,
    required this.data,
    required this.defaultPremiumLimit,
    required this.defaultFreeLimit,
  });
}

// ── Konsolide Krediler Özeti ────────────────────────────────────────────────
class _CreditsSummaryCard extends StatelessWidget {
  final Map<String, dynamic>? blastCredits;
  final Map<String, dynamic>? boostCredits;
  final Map<String, dynamic>? aiCredits;
  final Map<String, dynamic>? reactivationCredits;
  final bool isPremium;
  final bool isLoading;

  const _CreditsSummaryCard({
    required this.blastCredits,
    required this.boostCredits,
    required this.aiCredits,
    required this.reactivationCredits,
    required this.isPremium,
    required this.isLoading,
  });

  void _showInfoSheet(BuildContext context, String title, String desc) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bg(context),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary(context))),
              const SizedBox(height: 12),
              Text(desc, style: TextStyle(fontSize: 14, color: AppColors.textSecondary(context), height: 1.5)),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: Text(AppLocalizations.of(context)!.proHubGotIt, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    
    final items = [
      CreditItemModel(
        icon: Icons.campaign_outlined,
        iconColor: const Color(0xFF8B5CF6),
        titleBuilder: (l) => l.proCreditsBlastName,
        descBuilder: (l) => l.proCreditsBlastDesc,
        data: blastCredits,
        defaultPremiumLimit: 6,
        defaultFreeLimit: 3,
      ),
      CreditItemModel(
        icon: Icons.rocket_launch_outlined,
        iconColor: const Color(0xFF0EA5E9),
        titleBuilder: (l) => l.proCreditsBoostName,
        descBuilder: (l) => l.proCreditsBoostDesc,
        data: boostCredits,
        defaultPremiumLimit: 5,
        defaultFreeLimit: 1,
      ),
      CreditItemModel(
        icon: Icons.psychology_outlined,
        iconColor: const Color(0xFFF59E0B),
        titleBuilder: (l) => l.proCreditsAiName,
        descBuilder: (l) => l.proCreditsAiDesc,
        data: aiCredits,
        defaultPremiumLimit: 20,
        defaultFreeLimit: 0,
      ),
      CreditItemModel(
        icon: Icons.replay_outlined,
        iconColor: const Color(0xFF10B981),
        titleBuilder: (l) => l.proCreditsReactivationName,
        descBuilder: (l) => l.proCreditsReactivationDesc,
        data: reactivationCredits,
        defaultPremiumLimit: 5,
        defaultFreeLimit: 0,
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              l.proCreditsSummaryTitle,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary(context)),
            ),
          ),
          Divider(height: 1, color: AppColors.border(context)),
          ...items.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            final used = item.data?['used'] as int? ?? 0;
            final limit = item.data?['limit'] as int? ?? (isPremium ? item.defaultPremiumLimit : item.defaultFreeLimit);
            final remaining = item.data?['remaining'] as int? ?? (isPremium ? item.defaultPremiumLimit : item.defaultFreeLimit);
            final progress = limit > 0 ? (used / limit).clamp(0.0, 1.0) : 0.0;
            
            final Color barColor = remaining == 0
                ? const Color(0xFFEF4444)
                : remaining <= limit ~/ 4
                    ? const Color(0xFFF59E0B)
                    : const Color(0xFF22C55E);

            return Column(
              children: [
                AbsorbPointer(
                  absorbing: isLoading,
                  child: InkWell(
                    onTap: () => _showInfoSheet(context, item.titleBuilder(l), item.descBuilder(l)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: item.iconColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(item.icon, color: item.iconColor, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    item.titleBuilder(l),
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary(context)),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(Icons.info_outline, size: 14, color: AppColors.textSecondary(context)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                l.proCreditsUsedFormat(limit - remaining, remaining),
                                style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (isLoading)
                              const Padding(
                                padding: EdgeInsets.only(bottom: 8),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            else ...[
                              Text(
                                l.proCreditsLimitFormat(remaining, limit),
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: barColor),
                              ),
                              const SizedBox(height: 4),
                            ],
                            SizedBox(
                              width: 60,
                              height: 4,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: LinearProgressIndicator(
                                  value: isLoading ? null : progress,
                                  backgroundColor: AppColors.border(context),
                                  valueColor: AlwaysStoppedAnimation<Color>(barColor),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
                if (index < items.length - 1)
                  Divider(height: 1, color: AppColors.border(context), indent: 16, endIndent: 16),
              ],
            );
          }),
        ],
      ),
    );
  }
}

String _fmtRenewal(BuildContext context, String? iso) {
  if (iso == null) return '';
  try {
    final d = DateTime.parse(iso);
    final locale = Localizations.localeOf(context).languageCode;
    return DateFormat.yMMMMd(locale).format(d);
  } catch (_) {
    return '';
  }
}
