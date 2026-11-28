import 'package:flutter/material.dart';
import '../ui_library/components/buttons/teq_button.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import '../config/app_colors.dart';
import '../config/theme.dart';
import '../core/user_tier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/localization_service.dart';
import 'viewmodels/subscription_tools_view_model.dart';
import 'competitor_radar_screen.dart';
import 'demand_trends_screen.dart';
import 'listing_analytics_screen.dart';
import 'market_intelligence_screen.dart';
import 'sub_insights_screen.dart';
import 'sub_stream_analytics_screen.dart';
import 'retargeting_screen.dart';
import 'live_stream_history_screen.dart';
import 'my_recordings_screen.dart';
import 'profile_screen.dart';

class SubscriptionToolsScreen extends ConsumerStatefulWidget {
  final String userType;
  final bool scrollToLiveSection;

  const SubscriptionToolsScreen({super.key, this.userType = UserTier.standard, this.scrollToLiveSection = false});

  @override
  ConsumerState<SubscriptionToolsScreen> createState() => _SubscriptionToolsScreenState();
}

class _SubscriptionToolsScreenState extends ConsumerState<SubscriptionToolsScreen> {
  final _liveAccordionKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.scrollToLiveSection) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ModalRoute.of(context)?.didPush().then((_) {
          if (!mounted) return;
          final ctx = _liveAccordionKey.currentContext;
          if (ctx != null) {
            Scrollable.ensureVisible(
              ctx,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOut,
              alignment: 0.1,
            );
          }
        });
      });
    }
  }

  @override
  void dispose() {
    // Only cleanup if we are sure it's okay to do so, AutoDispose will take care of the ViewModel.
    // However, event stream subscriptions should be handled gracefully. AutoDispose destroys state.
    // Provider handles onDispose if we use ref.onDispose, but our VM has `cleanup`. We don't have direct access here easily to call it before destruction. 
    // Actually, we don't need to do anything here if AutoDispose destroys it and garbage collector removes the StreamSubscription, but it's better to add ref.onDispose to build. Let's do it in ViewModel instead.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(localizationProvider);
    final state = ref.watch(subscriptionToolsProvider(widget.userType));
    final viewModel = ref.read(subscriptionToolsProvider(widget.userType).notifier);

    ref.listenManual(subscriptionToolsProvider(widget.userType), (prev, next) {}, fireImmediately: true);

    final hasSubscription = state.hasSubscription;
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        title: Text(loc.t('subHubTitle')),
        backgroundColor: AppColors.bg(context),
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: () => viewModel.loadCredits(),
        child: ListView(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 32),
        children: [
          // ── Durum Kartı ────────────────────────────────────────────────────
          if (hasSubscription) _ProStatusCard(renewalDate: state.proExpiresAt, userType: state.userType, planType: state.planType) else _UpgradeBanner(lastTier: state.lastTier),

          if (!hasSubscription) ...[
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 2, bottom: 10),
              child: Text(
                loc.t('subBenefitsTitle'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary(context),
                  letterSpacing: 0.6,
                ),
              ),
            ),
            _BenefitRow(icon: Icons.auto_graph_outlined,        text: loc.t('subBenefit1')),
            _BenefitRow(icon: Icons.radar,                      text: loc.t('subBenefit2')),
            _BenefitRow(icon: Icons.trending_up_outlined,       text: loc.t('subBenefit3')),
            _BenefitRow(icon: Icons.mark_email_unread_outlined, text: loc.t('subBenefit4')),
            _BenefitRow(icon: Icons.stream_outlined,            text: loc.t('subBenefit5')),
            _BenefitRow(icon: Icons.video_library_outlined,     text: loc.t('subBenefit6')),
            const SizedBox(height: 16),
            _ScrollHintWidget(text: loc.t('subScrollHint')),
            const SizedBox(height: 8),
          ],

          const SizedBox(height: 24),
          _CreditsSummaryCard(
            blastCredits: state.blastCredits,
            boostCredits: state.boostCredits,
            aiDescCredits: state.aiDescCredits,
            reactivationCredits: state.reactivationCredits,
            userType: state.userType,
            monthlyStreamMinutesUsed: state.monthlyStreamMinutesUsed,
            streamMinutesBonus: state.streamMinutesBonus,
            isLoading: state.isLoading,
          ),
          const SizedBox(height: 20),
          // ── Araçlar Başlığı ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 2, bottom: 12),
            child: Text(
              loc.t('subHubTitle'),
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
            title: loc.t('subHubTabSales'),
            icon: Icons.trending_up,
            iconColor: const Color(0xFF6366F1),
            children: [
              _ToolCard(
                icon: Icons.auto_graph_outlined,
                iconColor: const Color(0xFF6366F1),
                title: loc.t('subToolSalesTitle'),
                description: loc.t('subToolSalesDesc'),
                userType: state.userType,
                requiredTier: UserTier.tier1,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SubInsightsScreen(userType: state.userType))),
              ),
              const SizedBox(height: 10),
              _ToolCard(
                icon: Icons.bar_chart_outlined,
                iconColor: const Color(0xFF10B981),
                title: loc.t('subToolListingsTitle'),
                description: loc.t('subToolListingsDesc'),
                userType: state.userType,
                requiredTier: UserTier.tier1,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ListingAnalyticsScreen(userType: state.userType))),
              ),
              const SizedBox(height: 10),
              _ToolCard(
                icon: Icons.pie_chart_outline,
                iconColor: const Color(0xFFEC4899),
                title: loc.t('subToolConversionTitle'),
                description: loc.t('subToolConversionDesc'),
                userType: state.userType,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ConversionBreakdownScreen(userType: state.userType))),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── 2. Piyasa & Rekabet ────────────────────────────────────────────
          _buildAccordion(
            context: context,
            title: loc.t('subHubTabMarket'),
            icon: Icons.public,
            iconColor: const Color(0xFFF59E0B),
            initiallyExpanded: false,
            children: [
              _ToolCard(
                icon: Icons.insights_outlined,
                iconColor: const Color(0xFFF59E0B),
                title: loc.t('subToolMarketTitle'),
                description: loc.t('subToolMarketDesc'),
                userType: state.userType,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => MarketIntelligenceScreen(userType: state.userType)),
                ),
              ),
              const SizedBox(height: 10),
              _ToolCard(
                icon: Icons.trending_up_outlined,
                iconColor: const Color(0xFF10B981),
                title: loc.t('subToolDemandTrendsTitle'),
                description: loc.t('subToolDemandTrendsDesc'),
                userType: state.userType,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DemandTrendsScreen(userType: state.userType))),
              ),
              const SizedBox(height: 10),
              _ToolCard(
                icon: Icons.radar,
                iconColor: const Color(0xFF6366F1),
                title: loc.t('subToolCompetitorRadarTitle'),
                description: loc.t('subToolCompetitorRadarDesc'),
                userType: state.userType,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CompetitorRadarScreen(userType: state.userType))),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── 3. Canlı Yayın & Kitle ─────────────────────────────────────────
          _buildAccordion(
            widgetKey: _liveAccordionKey,
            context: context,
            title: loc.t('subHubTabAudience'),
            icon: Icons.stream,
            iconColor: const Color(0xFF14B8A6),
            initiallyExpanded: widget.scrollToLiveSection,
            children: [
              _ToolCard(
                icon: Icons.schedule_outlined,
                iconColor: const Color(0xFF8B5CF6),
                title: loc.t('subToolBestTimeTitle'),
                description: loc.t('subToolBestTimeDesc'),
                userType: state.userType,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BestStreamTimeScreen(userType: state.userType))),
              ),
              const SizedBox(height: 10),
              _ToolCard(
                icon: Icons.stream_outlined,
                iconColor: const Color(0xFF14B8A6),
                title: loc.t('subToolStreamAnalyticsTitle'),
                description: loc.t('subToolStreamAnalyticsDesc'),
                userType: state.userType,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LiveStreamHistoryScreen(userType: state.userType))),
              ),
              const SizedBox(height: 10),
              _ToolCard(
                icon: Icons.mark_email_unread_outlined,
                iconColor: const Color(0xFF0EA5E9),
                title: loc.t('subToolRetargetingTitle'),
                description: loc.t('subToolRetargetingDesc'),
                userType: state.userType,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RetargetingScreen(initialIndex: 0, userType: state.userType))),
              ),
              const SizedBox(height: 10),
              _ToolCard(
                icon: Icons.video_library_outlined,
                iconColor: const Color(0xFFF97316),
                title: loc.t('subToolMyRecordingsTitle'),
                description: loc.t('subToolMyRecordingsDesc'),
                userType: state.userType,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MyRecordingsScreen(userType: state.userType))),
              ),
            ],
          ),



        ],
        ),
      ),
    );
  }

  Widget _buildAccordion({
    Key? widgetKey,
    required BuildContext context,
    required String title,
    required IconData icon,
    required Color iconColor,
    required List<Widget> children,
    bool initiallyExpanded = false,
  }) {
    return Container(
      key: widgetKey,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          childrenPadding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 16),
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

}

// ── Durum Kartları ─────────────────────────────────────────────────────────────

class _ProStatusCard extends ConsumerWidget {
  final String? renewalDate;
  final String userType;
  final String? planType;
  const _ProStatusCard({this.renewalDate, this.userType = 'tier1', this.planType});

  String _getPlanName(TranslationPack loc, String? type) {
    if (type == null || type.isEmpty) return loc.t('subMonthly');
    final key = 'pro${type[0].toUpperCase()}${type.substring(1)}';
    return loc.tOr(key, loc.t('subMonthly'));
  }

  String _getTierName(TranslationPack loc, String type) {
    switch (type) {
      case UserTier.tier4: return loc.tOr('tierLabelPremiumPlus', 'PREMIUM+');
      case UserTier.tier3: return loc.tOr('tierLabelPremium', 'PREMIUM');
      case UserTier.tier2: return loc.tOr('tierLabelProPlus', 'PRO+');
      default:             return loc.tOr('tierLabelPro', 'PRO');
    }
  }

  Color _getTierColor(String type) {
    if (UserTier.isTier3OrAbove(type)) return const Color(0xFF0EA5E9);
    return const Color(0xFFD97706); // tier1, tier2 → altın
  }

  List<Color> _getTierGradient(String type) {
    if (UserTier.isTier3OrAbove(type)) {
      return const [Color(0xFF0C4A6E), Color(0xFF075985)]; // PREMIUM/PREMIUM+ → derin teqlif cyan
    }
    return const [Color(0xFF451A03), Color(0xFF78350F)]; // PRO/PRO+ → derin altın-amber
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(localizationProvider);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _getTierGradient(userType),
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const FaIcon(FontAwesomeIcons.crown, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        loc.t('subStatusTitle'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _getTierColor(userType).withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _getTierName(loc, userType),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      if (planType != null) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _getPlanName(loc, planType),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  loc.t('subStatusDesc'),
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
                        loc.t('subRenewalDate', {'date': _fmtRenewal(context, renewalDate)}),
                        style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.55)),
                      ),
                    ],
                  ),
                ],
                // ── Expiry uyarı bandı (≤3 gün kaldıysa) ────────────────
                Builder(builder: (ctx) {
                  final days = _daysUntilExpiry(renewalDate);
                  if (days == null || days > 3) return const SizedBox.shrink();
                  final isCritical = days <= 1;
                  final bannerColor = isCritical ? const Color(0xFFEF4444) : const Color(0xFFF59E0B);
                  final label = days == 0
                      ? loc.tOr('subExpiryWarningToday', 'Bugün sona eriyor!')
                      : loc.tOr('subExpiryWarning', '{days} gün sonra sona eriyor').replaceAll('{days}', days.toString());
                  return Padding(
                    padding: const EdgeInsetsDirectional.only(top: 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: bannerColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: bannerColor.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, size: 14, color: bannerColor),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              label,
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: bannerColor),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UpgradeBanner extends ConsumerWidget {
  final String? lastTier;
  const _UpgradeBanner({this.lastTier});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(localizationProvider);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF92400E), Color(0xFFB45309)],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Hoş geldiniz geri bandı ─────────────────────────────
          if (lastTier != null && lastTier != UserTier.standard) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              margin: const EdgeInsetsDirectional.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Text('👋', style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      loc.tOr('subWelcomeBackDesc', 'Önceki üyeliğiniz: {tier}')
                          .replaceAll('{tier}', _tierLabel(lastTier!)),
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ],
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.lock_outline, color: Color(0xFFFBBF24), size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lastTier != null && lastTier != UserTier.standard
                          ? loc.tOr('subWelcomeBack', 'Tekrar hoş geldiniz!')
                          : loc.tOr('subUnlockTitle', 'teqlif Araçlarının kilidini aç'),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      loc.t('subUnlockDesc'),
                      style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.75)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () => Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute(builder: (_) => const WalletScreen()),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFD97706), Color(0xFFFFD700)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    loc.t('subUnlockBtn'),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _tierLabel(String tier) {
    switch (tier) {
      case UserTier.tier4: return 'PREMIUM+';
      case UserTier.tier3: return 'PREMIUM';
      case UserTier.tier2: return 'PRO+';
      case UserTier.tier1: return 'PRO';
      default:             return tier;
    }
  }
}

// ── Araç Kartı ─────────────────────────────────────────────────────────────────

class _ToolCard extends ConsumerWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;
  final String userType;
  final String requiredTier;
  final VoidCallback onTap;

  const _ToolCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
    this.userType = UserTier.standard,
    this.requiredTier = UserTier.tier3,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLocked = UserTier.tierLevel(userType) < UserTier.tierLevel(requiredTier);
    final pressColor = AppColors.textPrimary(context)
        .withValues(alpha: AppColors.isDark(context) ? 0.12 : 0.08);
    return Opacity(
      opacity: isLocked ? 0.75 : 1.0,
      child: Material(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border(context)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: InkWell(
            onTap: onTap,
            splashColor: pressColor,
            highlightColor: pressColor,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
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
                  if (isLocked)
                    _TierBadge(requiredTier: requiredTier, loc: ref.read(localizationProvider))
                  else
                    Icon(Icons.chevron_right, color: AppColors.textSecondary(context), size: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Tier Badge (araç kartı kilidi için) ───────────────────────────────────────

class _TierBadge extends StatelessWidget {
  final String requiredTier;
  final TranslationPack loc;

  const _TierBadge({required this.requiredTier, required this.loc});

  @override
  Widget build(BuildContext context) {
    final isCyan = UserTier.isTier3OrAbove(requiredTier);
    final colors = isCyan
        ? const [Color(0xFF0891B2), Color(0xFF06B6D4)]
        : const [Color(0xFFD97706), Color(0xFFFFD700)];
    final label = switch (requiredTier) {
      UserTier.tier4 => loc.tOr('tierLabelPremiumPlus', 'PREMIUM+'),
      UserTier.tier3 => loc.tOr('tierLabelPremium', 'PREMIUM'),
      UserTier.tier2 => loc.tOr('tierLabelProPlus', 'PRO+'),
      _              => loc.tOr('tierLabelPro', 'PRO'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const FaIcon(FontAwesomeIcons.crown, size: 7, color: Colors.white),
          const SizedBox(width: 3),
          Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white)),
        ],
      ),
    );
  }
}

// ── Benefit Row ────────────────────────────────────────────────────────────────

class _BenefitRow extends ConsumerWidget {
  final IconData icon;
  final String text;
  const _BenefitRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

// ── Scroll Hint Animasyonu ──────────────────────────────────────────────────────

class _ScrollHintWidget extends StatefulWidget {
  final String text;
  const _ScrollHintWidget({required this.text});

  @override
  State<_ScrollHintWidget> createState() => _ScrollHintWidgetState();
}

class _ScrollHintWidgetState extends State<_ScrollHintWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _offsetAnim;
  late final Animation<double> _opacityAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1100),
      vsync: this,
    )..repeat(reverse: true);

    _offsetAnim = Tween<double>(begin: 0, end: 7).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _opacityAnim = Tween<double>(begin: 0.45, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) => Opacity(
        opacity: _opacityAnim.value,
        child: Transform.translate(
          offset: Offset(0, _offsetAnim.value),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.text,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary(context),
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 2),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 22,
                color: AppColors.textSecondary(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Kapsülleyici Model Sınıfı ───────────────────────────────────────────────
class CreditItemModel {
  final IconData icon;
  final Color iconColor;
  final String Function(TranslationPack) titleBuilder;
  final String Function(TranslationPack) descBuilder;
  final Map<String, dynamic>? data;
  final int defaultPremiumLimit;
  final int defaultFreeLimit;
  final String Function(TranslationPack, Map<String, dynamic>?)? extraHintBuilder;

  CreditItemModel({
    required this.icon,
    required this.iconColor,
    required this.titleBuilder,
    required this.descBuilder,
    required this.data,
    required this.defaultPremiumLimit,
    required this.defaultFreeLimit,
    this.extraHintBuilder,
  });
}

// ── Konsolide Krediler Özeti ────────────────────────────────────────────────
class _StreamHoursRow extends ConsumerWidget {
  final String userType;
  final int minutesUsed;
  final int bonusMinutes;
  final bool isLoading;
  final TranslationPack loc;

  const _StreamHoursRow({
    required this.userType,
    required this.minutesUsed,
    this.bonusMinutes = 0,
    required this.isLoading,
    required this.loc,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tierLimitMins = _streamLimitMinutesFor(userType);
    final isUnlimited = tierLimitMins == null;
    // Efektif limit: tier limiti + bonus dakikalar
    final effectiveLimitMins = isUnlimited ? null : tierLimitMins! + bonusMinutes;
    final progress = isUnlimited ? 0.0 : (minutesUsed / effectiveLimitMins!).clamp(0.0, 1.0);

    final Color barColor = isUnlimited
        ? const Color(0xFF7C3AED)
        : progress >= 1.0
            ? const Color(0xFFEF4444)
            : progress >= 0.8
                ? const Color(0xFFF59E0B)
                : const Color(0xFF22C55E);

    final remainingMins = isUnlimited ? 0 : (effectiveLimitMins! - minutesUsed).clamp(0, effectiveLimitMins!);
    final percent = isUnlimited ? null : (progress * 100).round();

    return InkWell(
      onTap: () => _showCreditInfoSheet(
        context, loc,
        loc.tOr('subStreamHoursInfoTitle', 'Yayın Süresi'),
        loc.tOr('subStreamHoursInfoDesc', 'Aylık yayın süreniz tier\'ınıza göre belirlenir. Her ay yenilenir.'),
      ),
      child: Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF14B8A6).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.live_tv, color: Color(0xFF14B8A6), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          loc.tOr('subStreamHoursTitle', 'Yayın Süresi'),
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary(context)),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.info_outline, size: 14, color: AppColors.textSecondary(context)),
                      ],
                    ),
                    if (isLoading)
                      const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    else if (isUnlimited)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF7C3AED).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('∞', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF7C3AED))),
                      )
                    else
                      Text(
                        '%$percent',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: barColor),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    minHeight: 5,
                    value: isLoading ? null : (isUnlimited ? 1.0 : progress),
                    backgroundColor: AppColors.border(context),
                    valueColor: AlwaysStoppedAnimation<Color>(barColor),
                  ),
                ),
                if (!isUnlimited) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${loc.tOr('subStreamUsedLabel', 'Kullanılan')}: ${_fmtStreamTime(minutesUsed, loc)}',
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context)),
                      ),
                      Text(
                        '${loc.tOr('subStreamRemainingLabel', 'Kalan')}: ${_fmtStreamTime(remainingMins, loc)}',
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context)),
                      ),
                    ],
                  ),
                  if (bonusMinutes > 0) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.videocam_rounded, size: 12, color: Color(0xFF06B6D4)),
                        const SizedBox(width: 4),
                        Text(
                          '${loc.tOr('subStreamBonusLabel', 'Bonus')}: +${_fmtStreamTime(bonusMinutes, loc)}',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF06B6D4), fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ],
                ] else ...[
                  const SizedBox(height: 6),
                  Text(
                    loc.tOr('subStreamHoursUnlimited', 'Sınırsız yayın'),
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ));
  }
}

/// Komisyon satırı — "Kazancınızın %X'i sizin"
class _CommissionRow extends StatelessWidget {
  final String userType;
  final TranslationPack loc;

  const _CommissionRow({required this.userType, required this.loc});

  @override
  Widget build(BuildContext context) {
    final rate = UserTier.commissionPercent(userType);
    final isTopTier = UserTier.isTier3OrAbove(userType);
    final color = isTopTier
        ? const Color(0xFF0891B2)   // cyan — PREMIUM / PREMIUM+
        : UserTier.isTier2OrAbove(userType)
            ? const Color(0xFFD97706)   // altın — PRO+
            : const Color(0xFFD97706);  // altın — PRO
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.percent_outlined, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              loc.tOr('subHubCommission', 'Kazancınızın %$rate\'i sizin')
                  .replaceAll('{rate}', rate.toString()),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary(context),
              ),
            ),
          ),
          if (isTopTier)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '%100',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
              ),
            ),
        ],
      ),
    );
  }
}

int? _streamLimitMinutesFor(String userType) => UserTier.streamLimitMinutes(userType);

String _fmtStreamTime(int minutes, TranslationPack loc) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  final hA = loc.tOr('subStreamHourAbbr', 'S');
  final mA = loc.tOr('subStreamMinAbbr', 'Dk');
  return '$h $hA : $m $mA';
}

void _showCreditInfoSheet(BuildContext context, TranslationPack loc, String title, String desc) {
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
              child: TeqButton(
                onPressed: () => Navigator.pop(context),
                text: loc.t('subHubGotIt'),
                customColor: const Color(0xFF6366F1),
                isExpanded: true,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CreditsSummaryCard extends ConsumerWidget {
  final Map<String, dynamic>? blastCredits;
  final Map<String, dynamic>? boostCredits;
  final Map<String, dynamic>? aiDescCredits;
  final Map<String, dynamic>? reactivationCredits;
  final String userType;
  final int monthlyStreamMinutesUsed;
  final int streamMinutesBonus;
  final bool isLoading;

  const _CreditsSummaryCard({
    required this.blastCredits,
    required this.boostCredits,
    required this.aiDescCredits,
    required this.reactivationCredits,
    this.userType = UserTier.standard,
    this.monthlyStreamMinutesUsed = 0,
    this.streamMinutesBonus = 0,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(localizationProvider);
    
    final items = [
      CreditItemModel(
        icon: Icons.campaign_outlined,
        iconColor: const Color(0xFF8B5CF6),
        titleBuilder: (l) => loc.t('subCreditsBlastName'),
        descBuilder: (l) => loc.t('subCreditsBlastDesc'),
        data: blastCredits,
        defaultPremiumLimit: 6,
        defaultFreeLimit: 3,
      ),
      CreditItemModel(
        icon: Icons.rocket_launch_outlined,
        iconColor: const Color(0xFF0EA5E9),
        titleBuilder: (l) => loc.t('subCreditsBoostName'),
        descBuilder: (l) => loc.t('subCreditsBoostDesc'),
        data: boostCredits,
        defaultPremiumLimit: 3,
        defaultFreeLimit: 0,
      ),
      CreditItemModel(
        icon: Icons.edit_note_outlined,
        iconColor: const Color(0xFF8B5CF6),
        titleBuilder: (l) => loc.t('subCreditsAiDescName'),
        descBuilder: (l) => loc.t('subCreditsAiDescDesc'),
        data: aiDescCredits,
        defaultPremiumLimit: 6,
        defaultFreeLimit: 0,
      ),
      CreditItemModel(
        icon: Icons.replay_outlined,
        iconColor: const Color(0xFF10B981),
        titleBuilder: (l) => loc.t('subCreditsReactivationName'),
        descBuilder: (l) => loc.t('subCreditsReactivationDesc'),
        data: reactivationCredits,
        defaultPremiumLimit: 3,
        defaultFreeLimit: 0,
        extraHintBuilder: (l, d) {
          final count = (d?['within_window_count'] as num?)?.toInt() ?? 0;
          return count > 0 ? l.t('subReactivationWindowHint', {'count': count.toString()}) : '';
        },
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
              loc.t('subCreditsSummaryTitle'),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary(context)),
            ),
          ),
          Divider(height: 1, color: AppColors.border(context)),
          _StreamHoursRow(
            userType: userType,
            minutesUsed: monthlyStreamMinutesUsed,
            bonusMinutes: streamMinutesBonus,
            isLoading: isLoading,
            loc: loc,
          ),
          Divider(height: 1, color: AppColors.border(context)),
          if (UserTier.hasSubscription(userType)) ...[
            _CommissionRow(userType: userType, loc: loc),
            Divider(height: 1, color: AppColors.border(context)),
          ],
          ...items.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            final used = item.data?['used'] as int? ?? 0;
            final hasSubscription = UserTier.hasSubscription(userType);
            final limit = item.data?['limit'] as int? ?? (hasSubscription ? item.defaultPremiumLimit : item.defaultFreeLimit);
            final remaining = item.data?['remaining'] as int? ?? (hasSubscription ? item.defaultPremiumLimit : item.defaultFreeLimit);
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
                    onTap: () => _showCreditInfoSheet(context, loc, item.titleBuilder(loc), item.descBuilder(loc)),
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
                                  Flexible(
                                    child: Text(
                                      item.titleBuilder(loc),
                                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary(context)),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(Icons.info_outline, size: 14, color: AppColors.textSecondary(context)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                loc.t('subCreditsUsedFormat', {'used': (limit - remaining).toString(), 'remaining': remaining.toString()}),
                                style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context)),
                              ),
                              if (item.extraHintBuilder != null) Builder(builder: (_) {
                                final hint = item.extraHintBuilder!(loc, item.data);
                                if (hint.isEmpty) return const SizedBox.shrink();
                                return Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: Text(hint, style: const TextStyle(fontSize: 11, color: Color(0xFF10B981))),
                                );
                              }),
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
                                loc.t('subCreditsLimitFormat', {'remaining': remaining.toString(), 'limit': limit.toString()}),
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

/// ISO tarihine kaç gün kaldığını döner; geçmişse 0, parse edilemezse null.
int? _daysUntilExpiry(String? iso) {
  if (iso == null) return null;
  try {
    final expiry = DateTime.parse(iso).toLocal();
    final now = DateTime.now();
    final diff = expiry.difference(now);
    return diff.isNegative ? 0 : diff.inDays;
  } catch (_) {
    return null;
  }
}
