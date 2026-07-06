import sys

with open('lib/screens/pro_hub_screen.dart', 'r') as f:
    content = f.read()

load_credits_old = """  Future<void> _loadCredits() async {
    final blastData        = await AnalyticsService.getBlastCredits();
    final boostData        = await AnalyticsService.getBoostCredits();
    final aiData           = await AnalyticsService.getAiPriceCredits();
    final reactivationData = await AnalyticsService.getReactivationCredits();
    if (mounted) {
      setState(() {
        _credits             = blastData;
        _boostCredits        = boostData;
        _aiCredits           = aiData;
        _reactivationCredits = reactivationData;
      });
    }
  }"""

load_credits_new = """  Future<void> _loadCredits() async {
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
      });
    }
  }"""

content = content.replace(load_credits_old, load_credits_new)

build_start = content.find('  @override\n  Widget build(BuildContext context) {')
build_end = content.find('  Widget _buildCreditRow(String title,', build_start)

if build_start != -1 and build_end != -1:
    new_build = """  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final isPremium = _isPremium;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.bg(context),
        appBar: AppBar(
          title: Text(l.proHubTitle),
          backgroundColor: AppColors.bg(context),
          elevation: 0,
          bottom: TabBar(
            indicatorColor: const Color(0xFF14B8A6),
            labelColor: const Color(0xFF14B8A6),
            unselectedLabelColor: Colors.grey,
            isScrollable: true,
            tabs: [
              Tab(text: l.proTabSales ?? 'Performans'),
              Tab(text: l.proTabMarket ?? 'Piyasa'),
              Tab(text: l.proTabAudience ?? 'Kitle'),
            ],
          ),
        ),
        body: RefreshIndicator(
          onRefresh: _loadCredits,
          child: TabBarView(
            children: [
              // ── 1. Performans ────────────────────────────────────────────────
              ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (isPremium) _ProStatusCard(renewalDate: _credits?['renewal_date'] as String?, planType: _planType) else _UpgradeBanner(),
                  const SizedBox(height: 24),
                  _CreditsSummaryCard(
                    blastCredits: _credits,
                    boostCredits: _boostCredits,
                    aiCredits: _aiCredits,
                    reactivationCredits: _reactivationCredits,
                    isPremium: isPremium,
                  ),
                  const SizedBox(height: 32),
                  const ProInsightsScreen(isEmbedded: true),
                  const SizedBox(height: 32),
                  ListingAnalyticsScreen(isPremium: isPremium, isEmbedded: true),
                  const SizedBox(height: 32),
                  const ConversionBreakdownScreen(isEmbedded: true),
                ],
              ),
              // ── 2. Piyasa ──────────────────────────────────────────────────
              ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  MarketIntelligenceScreen(isPremium: isPremium, isEmbedded: true),
                  const SizedBox(height: 32),
                  const CompetitorRadarScreen(isEmbedded: true),
                ],
              ),
              // ── 3. Kitle ──────────────────────────────────────────────────
              ListView(
                padding: const EdgeInsets.all(16),
                children: const [
                  LiveStreamHistoryScreen(isEmbedded: true),
                  SizedBox(height: 32),
                  BestStreamTimeScreen(isEmbedded: true),
                  SizedBox(height: 32),
                  RetargetingScreen(isEmbedded: true),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

"""
    content = content[:build_start] + new_build + content[build_end:]

with open('lib/screens/pro_hub_screen.dart', 'w') as f:
    f.write(content)
