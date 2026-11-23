import 'package:flutter/material.dart';
import '../ui_library/components/buttons/teq_button.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_colors.dart';
import '../core/user_tier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/localization_service.dart';
import 'viewmodels/pro_hub_view_model.dart';
import 'competitor_radar_screen.dart';
import 'demand_trends_screen.dart';
import 'listing_analytics_screen.dart';
import 'market_intelligence_screen.dart';
import 'pro_insights_screen.dart';
import 'pro_stream_analytics_screen.dart';
import 'retargeting_screen.dart';
import 'live_stream_history_screen.dart';
import 'my_recordings_screen.dart';
import '../widgets/pro_subscription_sheet.dart';

class ProHubScreen extends ConsumerStatefulWidget {
  final String userType;
  final bool scrollToLiveSection;

  const ProHubScreen({super.key, this.userType = UserTier.standard, this.scrollToLiveSection = false});

  @override
  ConsumerState<ProHubScreen> createState() => _ProHubScreenState();
}

class _ProHubScreenState extends ConsumerState<ProHubScreen> {
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
    final state = ref.watch(proHubProvider(widget.userType));
    final viewModel = ref.read(proHubProvider(widget.userType).notifier);

    ref.listenManual(proHubProvider(widget.userType), (prev, next) {}, fireImmediately: true);

    final isPaidTier = state.isPaidTier;
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        title: Text(loc.t('proHubTitle')),
        backgroundColor: AppColors.bg(context),
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: () => viewModel.loadCredits(),
        child: ListView(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 32),
        children: [
          // ── Durum Kartı ────────────────────────────────────────────────────
          if (isPaidTier) _ProStatusCard(renewalDate: state.proExpiresAt, userType: state.userType, planType: state.planType) else _UpgradeBanner(),

          if (!isPaidTier) ...[
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 2, bottom: 10),
              child: Text(
                loc.t('proBenefitsTitle'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary(context),
                  letterSpacing: 0.6,
                ),
              ),
            ),
            _BenefitRow(icon: Icons.auto_graph_outlined,        text: loc.t('proBenefit1')),
            _BenefitRow(icon: Icons.radar,                      text: loc.t('proBenefit2')),
            _BenefitRow(icon: Icons.trending_up_outlined,       text: loc.t('proBenefit3')),
            _BenefitRow(icon: Icons.mark_email_unread_outlined, text: loc.t('proBenefit4')),
            _BenefitRow(icon: Icons.stream_outlined,            text: loc.t('proBenefit5')),
            _BenefitRow(icon: Icons.video_library_outlined,     text: loc.t('proBenefit6')),
            const SizedBox(height: 16),
            _ScrollHintWidget(text: loc.t('proScrollHint')),
            const SizedBox(height: 8),
          ],

          const SizedBox(height: 24),
          _CreditsSummaryCard(
            blastCredits: state.blastCredits,
            boostCredits: state.boostCredits,
            aiDescCredits: state.aiDescCredits,
            reactivationCredits: state.reactivationCredits,
            userType: state.userType,
            monthlyStreamSecondsUsed: state.monthlyStreamSecondsUsed,
            isLoading: state.isLoading,
          ),
          const SizedBox(height: 24),
          // ── Araçlar Başlığı ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 2, bottom: 12),
            child: Text(
              loc.t('proHubTitle'),
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
            title: loc.t('proHubTabSales'),
            icon: Icons.trending_up,
            iconColor: const Color(0xFF6366F1),
            children: [
              _ToolCard(
                icon: Icons.auto_graph_outlined,
                iconColor: const Color(0xFF6366F1),
                title: loc.t('proToolSalesTitle'),
                description: loc.t('proToolSalesDesc'),
                userType: state.userType,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProInsightsScreen(userType: state.userType))),
              ),
              const SizedBox(height: 10),
              _ToolCard(
                icon: Icons.bar_chart_outlined,
                iconColor: const Color(0xFF10B981),
                title: loc.t('proToolListingsTitle'),
                description: loc.t('proToolListingsDesc'),
                userType: state.userType,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ListingAnalyticsScreen(userType: state.userType))),
              ),
              const SizedBox(height: 10),
              _ToolCard(
                icon: Icons.pie_chart_outline,
                iconColor: const Color(0xFFEC4899),
                title: loc.t('proToolConversionTitle'),
                description: loc.t('proToolConversionDesc'),
                userType: state.userType,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ConversionBreakdownScreen(userType: state.userType))),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── 2. Piyasa & Rekabet ────────────────────────────────────────────
          _buildAccordion(
            context: context,
            title: loc.t('proHubTabMarket'),
            icon: Icons.public,
            iconColor: const Color(0xFFF59E0B),
            initiallyExpanded: false,
            children: [
              _ToolCard(
                icon: Icons.insights_outlined,
                iconColor: const Color(0xFFF59E0B),
                title: loc.t('proToolMarketTitle'),
                description: loc.t('proToolMarketDesc'),
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
                title: loc.t('proToolDemandTrendsTitle'),
                description: loc.t('proToolDemandTrendsDesc'),
                userType: state.userType,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DemandTrendsScreen(userType: state.userType))),
              ),
              const SizedBox(height: 10),
              _ToolCard(
                icon: Icons.radar,
                iconColor: const Color(0xFF6366F1),
                title: loc.t('proToolCompetitorRadarTitle'),
                description: loc.t('proToolCompetitorRadarDesc'),
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
            title: loc.t('proHubTabAudience'),
            icon: Icons.stream,
            iconColor: const Color(0xFF14B8A6),
            initiallyExpanded: widget.scrollToLiveSection,
            children: [
              _ToolCard(
                icon: Icons.schedule_outlined,
                iconColor: const Color(0xFF8B5CF6),
                title: loc.t('proToolBestTimeTitle'),
                description: loc.t('proToolBestTimeDesc'),
                userType: state.userType,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BestStreamTimeScreen(userType: state.userType))),
              ),
              const SizedBox(height: 10),
              _ToolCard(
                icon: Icons.stream_outlined,
                iconColor: const Color(0xFF14B8A6),
                title: loc.t('proToolStreamAnalyticsTitle'),
                description: loc.t('proToolStreamAnalyticsDesc'),
                userType: state.userType,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LiveStreamHistoryScreen(userType: state.userType))),
              ),
              const SizedBox(height: 10),
              _ToolCard(
                icon: Icons.mark_email_unread_outlined,
                iconColor: const Color(0xFF0EA5E9),
                title: loc.t('proToolRetargetingTitle'),
                description: loc.t('proToolRetargetingDesc'),
                userType: state.userType,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RetargetingScreen(initialIndex: 0, userType: state.userType))),
              ),
              const SizedBox(height: 10),
              _ToolCard(
                icon: Icons.video_library_outlined,
                iconColor: const Color(0xFFF97316),
                title: loc.t('proToolMyRecordingsTitle'),
                description: loc.t('proToolMyRecordingsDesc'),
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
  const _ProStatusCard({this.renewalDate, this.userType = 'pro', this.planType});

  String _getPlanName(TranslationPack loc, String? type) {
    if (type == null || type.isEmpty) return loc.t('proMonthly');
    final key = 'pro${type[0].toUpperCase()}${type.substring(1)}';
    return loc.tOr(key, loc.t('proMonthly'));
  }

  String _getTierName(TranslationPack loc, String type) {
    switch (type) {
      case UserTier.proPlus: return loc.tOr('tierLabelProPlus', 'PRO+');
      case UserTier.premium: return loc.tOr('tierLabelPremium', 'PREMIUM');
      default: return loc.tOr('tierLabelPro', 'PRO');
    }
  }

  Color _getTierColor(String type) {
    switch (type) {
      case UserTier.proPlus: return const Color(0xFF7C3AED);
      case UserTier.premium: return const Color(0xFF0EA5E9);
      default: return const Color(0xFFD97706);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(localizationProvider);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E1B4B), Color(0xFF312E81)],
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
                        loc.t('proStatusTitle'),
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
                  loc.t('proStatusDesc'),
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
                        loc.t('proRenewalDate', {'date': _fmtRenewal(context, renewalDate)}),
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

class _UpgradeBanner extends ConsumerWidget {
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
      child: Row(
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
                  loc.t('proUnlockTitle'),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white),
                ),
                const SizedBox(height: 3),
                Text(
                  loc.t('proUnlockDesc'),
                  style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.75)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              backgroundColor: Colors.transparent,
              builder: (_) => ProSubscriptionSheet(
                loc: loc,
                onPurchaseSuccess: () => Navigator.of(context).pop(),
              ),
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
                loc.t('proUnlockBtn'),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Araç Kartı ─────────────────────────────────────────────────────────────────

class _ToolCard extends ConsumerWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;
  final String userType;
  final VoidCallback onTap;

  const _ToolCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
    this.userType = UserTier.standard,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            if (!UserTier.isPaidTier(userType))
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFD97706), Color(0xFFFFD700)],
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const FaIcon(FontAwesomeIcons.crown, size: 7, color: Colors.white),
                    const SizedBox(width: 3),
                    Text(ref.read(localizationProvider).t('pro'), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white)),
                  ],
                ),
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

// ── Yükseltme Bottom Sheet ─────────────────────────────────────────────────────

class _UpgradeSheet extends ConsumerWidget {
  const _UpgradeSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(localizationProvider);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsetsDirectional.fromSTEB(24, 16, 24, 40),
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
          const FaIcon(FontAwesomeIcons.crown, size: 48, color: Color(0xFFFFD700)),
          const SizedBox(height: 12),
          Text(
            loc.t('proUpgradeTitle'),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            loc.t('proUpgradeSheetDesc'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary(context), height: 1.5),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFFD97706), Color(0xFFFFD700)]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TeqButton(
                onPressed: () {
                  Navigator.pop(context);
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => ProSubscriptionSheet(
                      loc: loc,
                      onPurchaseSuccess: () => Navigator.of(context).pop(),
                    ),
                  );
                },
                text: loc.t('proUpgradeBtn'),
                customColor: Colors.transparent,
                isExpanded: true,
              ),
            ),
          ),
          const SizedBox(height: 10),
          TeqButton.text(
            onPressed: () => Navigator.pop(context),
            text: loc.t('btnDismiss'),
            customColor: AppColors.textSecondary(context),
            isExpanded: false,
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
  final int secondsUsed;
  final bool isLoading;
  final TranslationPack loc;

  const _StreamHoursRow({
    required this.userType,
    required this.secondsUsed,
    required this.isLoading,
    required this.loc,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final limitSecs = _streamLimitSecondsFor(userType);
    final isUnlimited = limitSecs == null;
    final usedHours = (secondsUsed / 3600).floor();
    final limitHours = isUnlimited ? null : (limitSecs / 3600).floor();
    final progress = isUnlimited ? 0.0 : (secondsUsed / limitSecs).clamp(0.0, 1.0);

    final Color barColor = isUnlimited
        ? const Color(0xFF7C3AED)
        : progress >= 1.0
            ? const Color(0xFFEF4444)
            : progress >= 0.8
                ? const Color(0xFFF59E0B)
                : const Color(0xFF22C55E);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF14B8A6).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.stream_outlined, color: Color(0xFF14B8A6), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loc.tOr('proStreamHoursTitle', 'Yayın Saati'),
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary(context)),
                ),
                const SizedBox(height: 4),
                Text(
                  isUnlimited
                      ? loc.tOr('proStreamHoursUnlimited', 'Sınırsız yayın')
                      : loc.tOr('proStreamHoursUsed', '{used} / {limit} saat kullanıldı')
                          .replaceAll('{used}', usedHours.toString())
                          .replaceAll('{limit}', (limitHours ?? 0).toString()),
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
                const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
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
                  '$usedHours/${limitHours}h',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: barColor),
                ),
              const SizedBox(height: 4),
              SizedBox(
                width: 60,
                height: 4,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: isLoading ? null : (isUnlimited ? 1.0 : progress),
                    backgroundColor: AppColors.border(context),
                    valueColor: AlwaysStoppedAnimation<Color>(barColor),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

int? _streamLimitSecondsFor(String userType) => UserTier.streamLimitSeconds(userType);

class _CreditsSummaryCard extends ConsumerWidget {
  final Map<String, dynamic>? blastCredits;
  final Map<String, dynamic>? boostCredits;
  final Map<String, dynamic>? aiDescCredits;
  final Map<String, dynamic>? reactivationCredits;
  final String userType;
  final int monthlyStreamSecondsUsed;
  final bool isLoading;

  const _CreditsSummaryCard({
    required this.blastCredits,
    required this.boostCredits,
    required this.aiDescCredits,
    required this.reactivationCredits,
    this.userType = UserTier.standard,
    this.monthlyStreamSecondsUsed = 0,
    required this.isLoading,
  });

  void _showInfoSheet(BuildContext context, TranslationPack loc, String title, String desc) {
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
                  text: loc.t('proHubGotIt'),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(localizationProvider);
    
    final items = [
      CreditItemModel(
        icon: Icons.campaign_outlined,
        iconColor: const Color(0xFF8B5CF6),
        titleBuilder: (l) => loc.t('proCreditsBlastName'),
        descBuilder: (l) => loc.t('proCreditsBlastDesc'),
        data: blastCredits,
        defaultPremiumLimit: 6,
        defaultFreeLimit: 3,
      ),
      CreditItemModel(
        icon: Icons.rocket_launch_outlined,
        iconColor: const Color(0xFF0EA5E9),
        titleBuilder: (l) => loc.t('proCreditsBoostName'),
        descBuilder: (l) => loc.t('proCreditsBoostDesc'),
        data: boostCredits,
        defaultPremiumLimit: 3,
        defaultFreeLimit: 0,
      ),
      CreditItemModel(
        icon: Icons.edit_note_outlined,
        iconColor: const Color(0xFF8B5CF6),
        titleBuilder: (l) => loc.t('proCreditsAiDescName'),
        descBuilder: (l) => loc.t('proCreditsAiDescDesc'),
        data: aiDescCredits,
        defaultPremiumLimit: 6,
        defaultFreeLimit: 0,
      ),
      CreditItemModel(
        icon: Icons.replay_outlined,
        iconColor: const Color(0xFF10B981),
        titleBuilder: (l) => loc.t('proCreditsReactivationName'),
        descBuilder: (l) => loc.t('proCreditsReactivationDesc'),
        data: reactivationCredits,
        defaultPremiumLimit: 3,
        defaultFreeLimit: 0,
        extraHintBuilder: (l, d) {
          final count = (d?['within_window_count'] as num?)?.toInt() ?? 0;
          return count > 0 ? l.t('proReactivationWindowHint', {'count': count.toString()}) : '';
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
              loc.t('proCreditsSummaryTitle'),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary(context)),
            ),
          ),
          Divider(height: 1, color: AppColors.border(context)),
          if (UserTier.isPaidTier(userType)) ...[
            _StreamHoursRow(
              userType: userType,
              secondsUsed: monthlyStreamSecondsUsed,
              isLoading: isLoading,
              loc: loc,
            ),
            Divider(height: 1, color: AppColors.border(context)),
          ],
          ...items.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            final used = item.data?['used'] as int? ?? 0;
            final isPaidTier = UserTier.isPaidTier(userType);
            final limit = item.data?['limit'] as int? ?? (isPaidTier ? item.defaultPremiumLimit : item.defaultFreeLimit);
            final remaining = item.data?['remaining'] as int? ?? (isPaidTier ? item.defaultPremiumLimit : item.defaultFreeLimit);
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
                    onTap: () => _showInfoSheet(context, loc, item.titleBuilder(loc), item.descBuilder(loc)),
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
                                loc.t('proCreditsUsedFormat', {'used': (limit - remaining).toString(), 'remaining': remaining.toString()}),
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
                                loc.t('proCreditsLimitFormat', {'remaining': remaining.toString(), 'limit': limit.toString()}),
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
