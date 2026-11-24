import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../config/app_colors.dart';
import '../core/user_tier.dart';
import '../services/localization_service.dart';
import 'viewmodels/pro_subscription_view_model.dart';

// ── Tier sabit verileri ────────────────────────────────────────────────────────

const _kTiers = [UserTier.pro, UserTier.proPlus, UserTier.premium];

const _kTierProductIds = <String, List<String>>{
  UserTier.pro:     ['teqlif_pro_1m',      'teqlif_pro_3m',      'teqlif_pro_6m',      'teqlif_pro_12m'],
  UserTier.proPlus: ['teqlif_pro_plus_1m', 'teqlif_pro_plus_3m', 'teqlif_pro_plus_6m', 'teqlif_pro_plus_12m'],
  UserTier.premium: ['teqlif_premium_1m',  'teqlif_premium_3m',  'teqlif_premium_6m',  'teqlif_premium_12m'],
};

// Fallback fiyatlar (IAP yüklenene kadar gösterilir)
const _kFallbackPrices = <String, List<String>>{
  UserTier.pro:     ['399,99 ₺', '1.079,99 ₺', '1.999,99 ₺', '3.599,99 ₺'],
  UserTier.proPlus: ['899,99 ₺', '2.399,99 ₺', '4.499,99 ₺', '7.999,99 ₺'],
  UserTier.premium: ['1.799,99 ₺', '4.599,99 ₺', '8.999,99 ₺', '15.999,99 ₺'],
};

// Tasarruf yüzdesi [1ay, 3ay, 6ay, 12ay]
const _kSavings = <String, List<int>>{
  UserTier.pro:     [0, 10, 17, 25],
  UserTier.proPlus: [0, 11, 17, 26],
  UserTier.premium: [0, 15, 17, 26],
};

// Süre etiketleri
const _kDurationLabels = ['1 Ay', '3 Ay', '6 Ay', '12 Ay'];

// ── Renk/gradient yardımcıları ────────────────────────────────────────────────

Color _tierColor(String tier) {
  switch (tier) {
    case UserTier.premium: return const Color(0xFF0EA5E9);
    case UserTier.proPlus: return const Color(0xFF7C3AED);
    default:               return const Color(0xFFD97706);
  }
}

LinearGradient _tierGradient(String tier) {
  switch (tier) {
    case UserTier.premium:
      return const LinearGradient(colors: [Color(0xFF0C4A6E), Color(0xFF075985)],
          begin: Alignment.topLeft, end: Alignment.bottomRight);
    case UserTier.proPlus:
      return const LinearGradient(colors: [Color(0xFF3B0764), Color(0xFF4C1D95)],
          begin: Alignment.topLeft, end: Alignment.bottomRight);
    default:
      return const LinearGradient(colors: [Color(0xFF78350F), Color(0xFF92400E)],
          begin: Alignment.topLeft, end: Alignment.bottomRight);
  }
}

String _tierLabel(String tier) {
  switch (tier) {
    case UserTier.premium: return 'PREMIUM';
    case UserTier.proPlus: return 'PRO+';
    default:               return 'PRO';
  }
}

// ── Ana ekran ─────────────────────────────────────────────────────────────────

class SubscriptionPlansScreen extends ConsumerStatefulWidget {
  /// Kullanıcının mevcut tier'ı; satın alma akışında zaten sahip olunan tier'lar
  /// için "Mevcut Plan" badge'i gösterilir.
  final String currentUserType;

  /// Açılışta seçili tab (ör. 'pro_plus' kalite kilidi için).
  final String? initialTier;

  final VoidCallback? onPurchaseSuccess;

  const SubscriptionPlansScreen({
    super.key,
    this.currentUserType = UserTier.standard,
    this.initialTier,
    this.onPurchaseSuccess,
  });

  /// Kolaylık helper — tüm entry-point'ler buradan geçer.
  static Future<void> show(
    BuildContext context, {
    String currentUserType = UserTier.standard,
    String? initialTier,
    VoidCallback? onPurchaseSuccess,
  }) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        builder: (_) => SubscriptionPlansScreen(
          currentUserType: currentUserType,
          initialTier: initialTier,
          onPurchaseSuccess: onPurchaseSuccess,
        ),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  ConsumerState<SubscriptionPlansScreen> createState() =>
      _SubscriptionPlansScreenState();
}

class _SubscriptionPlansScreenState
    extends ConsumerState<SubscriptionPlansScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Her tier için seçili süre indeksi (0=1ay, 1=3ay, 2=6ay, 3=12ay)
  final Map<String, int> _durationIdx = {
    UserTier.pro:     1, // varsayılan 3 aylık (en popüler)
    UserTier.proPlus: 1,
    UserTier.premium: 1,
  };

  int _initialTabIndex() {
    final tier = widget.initialTier;
    if (tier != null) {
      final idx = _kTiers.indexOf(tier);
      if (idx >= 0) return idx;
    }
    // Kullanıcının bir üst tier'ı varsayılan
    final rank = UserTier.tierLevel(widget.currentUserType);
    return (rank).clamp(0, 2); // 0=pro, 1=pro_plus, 2=premium
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: _initialTabIndex(),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _onPurchase(PurchaseDetails purchase) {
    if (!mounted) return;
    if (purchase.status == PurchaseStatus.pending) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ref.read(localizationProvider).t('iapPurchasePending'))),
      );
      return;
    }
    if (purchase.status == PurchaseStatus.purchased ||
        purchase.status == PurchaseStatus.restored) {
      Navigator.of(context).pop();
      widget.onPurchaseSuccess?.call();
    }
  }

  Future<void> _subscribe(String productId, List<ProductDetails> products) async {
    final product = products.where((p) => p.id == productId).firstOrNull;
    final loc = ref.read(localizationProvider);
    if (product == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('iapProductsNotLoaded'))),
      );
      return;
    }
    try {
      await ref.read(proSubscriptionViewModelProvider.notifier).buy(product);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(localizationProvider);
    final vm = ref.watch(proSubscriptionViewModelProvider);

    ref.listen<PurchaseDetails?>(
      proSubscriptionViewModelProvider.select((s) => s.lastPurchase),
      (prev, next) {
        if (next == null || next == prev) return;
        _onPurchase(next);
      },
    );
    ref.listen<String?>(
      proSubscriptionViewModelProvider.select((s) => s.error),
      (_, error) {
        if (error == null || !mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('iapVerifyFailed'))),
        );
      },
    );

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          loc.tOr('subPlansTitle', 'Üyelik Planları'),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          indicatorColor: Colors.white,
          indicatorWeight: 2,
          tabs: _kTiers.map((tier) => Tab(text: _tierLabel(tier))).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _kTiers.map((tier) => _TierPage(
          tier: tier,
          currentUserType: widget.currentUserType,
          durationIdx: _durationIdx[tier] ?? 1,
          onDurationChanged: (idx) => setState(() => _durationIdx[tier] = idx),
          products: vm.products,
          isPurchasing: vm.isPurchasing,
          onSubscribe: (productId) => _subscribe(productId, vm.products),
          loc: loc,
        )).toList(),
      ),
    );
  }
}

// ── Tier sayfa ─────────────────────────────────────────────────────────────────

class _TierPage extends StatelessWidget {
  final String tier;
  final String currentUserType;
  final int durationIdx;
  final ValueChanged<int> onDurationChanged;
  final List<ProductDetails> products;
  final bool isPurchasing;
  final ValueChanged<String> onSubscribe;
  final TranslationPack loc;

  const _TierPage({
    required this.tier,
    required this.currentUserType,
    required this.durationIdx,
    required this.onDurationChanged,
    required this.products,
    required this.isPurchasing,
    required this.onSubscribe,
    required this.loc,
  });

  bool get _isCurrentTier => currentUserType == tier;
  bool get _isLowerTier =>
      (UserTier.tierLevel(currentUserType)) > (UserTier.tierLevel(tier));

  String get _productId => (_kTierProductIds[tier] ?? [])[durationIdx];

  String _priceFor(String productId) =>
      products.where((p) => p.id == productId).firstOrNull?.price ??
      (_kFallbackPrices[tier] ?? [])[durationIdx];

  String _ctaLabel() {
    if (_isCurrentTier) return loc.tOr('subPlanCurrentBadge', 'Mevcut Plan');
    if (_isLowerTier)   return loc.tOr('subPlanCurrentBadge', 'Mevcut Plan');
    final name = _tierLabel(tier);
    final isUpgrade = UserTier.isPaidTier(currentUserType);
    return isUpgrade
        ? loc.tOr('subPlanUpgradeCta', '$name\'a Geçiş Yap').replaceAll('{tier}', name)
        : loc.tOr('subPlanStartCta', '$name\'ya Başla').replaceAll('{tier}', name);
  }

  bool get _ctaEnabled => !_isCurrentTier && !_isLowerTier;

  @override
  Widget build(BuildContext context) {
    final color = _tierColor(tier);
    final gradient = _tierGradient(tier);
    final savings = (_kSavings[tier] ?? [])[durationIdx];
    final productId = _productId;
    final price = _priceFor(productId);

    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 20, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Başlık kartı ───────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FaIcon(FontAwesomeIcons.crown, size: 10, color: color),
                          const SizedBox(width: 5),
                          Text(
                            _tierLabel(tier),
                            style: TextStyle(
                              color: color,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_isCurrentTier) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.withValues(alpha: 0.5)),
                        ),
                        child: Text(
                          loc.tOr('subPlanCurrentBadge', 'Mevcut Plan'),
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.greenAccent),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),

                // ── Fiyat büyük ────────────────────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      price,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        loc.tOr('subPerMonth', '/ ay'),
                        style: const TextStyle(fontSize: 13, color: Colors.white60),
                      ),
                    ),
                    if (savings > 0) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.5)),
                        ),
                        child: Text(
                          loc.tOr('subSaveBadge', '%$savings tasarruf').replaceAll('{pct}', savings.toString()),
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.greenAccent),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),

                // ── Süre seçici ────────────────────────────────────────
                Row(
                  children: List.generate(4, (i) {
                    final selected = i == durationIdx;
                    return GestureDetector(
                      onTap: () => onDurationChanged(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsetsDirectional.only(end: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: selected
                              ? Colors.white.withValues(alpha: 0.2)
                              : Colors.white.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: selected ? Colors.white54 : Colors.white24,
                            width: selected ? 1.5 : 1,
                          ),
                        ),
                        child: Text(
                          _kDurationLabels[i],
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                            color: selected ? Colors.white : Colors.white60,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── 3 öne çıkan kazanım ────────────────────────────────────────
          _TopBenefits(tier: tier, loc: loc),
          const SizedBox(height: 20),

          // ── CTA butonu ─────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: (_ctaEnabled && !isPurchasing)
                  ? () => onSubscribe(productId)
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: _ctaEnabled ? color : Colors.grey.shade700,
                disabledBackgroundColor: _isCurrentTier ? Colors.green.shade800 : Colors.grey.shade800,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: isPurchasing && _ctaEnabled
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      _ctaLabel(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 24),

          // ── Tam özellik listesi ────────────────────────────────────────
          _FeatureList(tier: tier, loc: loc),
          const SizedBox(height: 24),

          // ── Politika metni ────────────────────────────────────────────
          Text(
            loc.t('proAutoRenewNotice'),
            style: const TextStyle(color: Colors.white38, fontSize: 10, height: 1.5),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── 3 öne çıkan kazanım ───────────────────────────────────────────────────────

class _TopBenefits extends StatelessWidget {
  final String tier;
  final TranslationPack loc;
  const _TopBenefits({required this.tier, required this.loc});

  List<({IconData icon, String label, String value})> _benefits() {
    final hours = UserTier.streamLimitSeconds(tier);
    final hoursStr = hours == null
        ? loc.tOr('subBenefitUnlimitedStream', 'Sınırsız')
        : '${hours ~/ 3600} ${loc.tOr("subHourUnit", "saat")}/ay';
    final quality = UserTier.maxStreamQuality(tier);
    final commission = UserTier.commissionPercent(tier);

    return [
      (icon: Icons.videocam_outlined,  label: loc.tOr('proHubStreamHours', 'Yayın Saati'),   value: hoursStr),
      (icon: Icons.hd_outlined,        label: loc.tOr('proVideoQuality', 'Yayın Kalitesi'),  value: quality),
      (icon: Icons.percent_outlined,   label: loc.tOr('proCommissionTitle', 'Komisyon'),      value: '%$commission'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final color = _tierColor(tier);
    return Column(
      children: _benefits().map((b) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(b.icon, size: 20, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                b.label,
                style: const TextStyle(fontSize: 13, color: Colors.white70),
              ),
            ),
            Text(
              b.value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      )).toList(),
    );
  }
}

// ── Tam özellik listesi ───────────────────────────────────────────────────────

class _FeatureList extends StatelessWidget {
  final String tier;
  final TranslationPack loc;
  const _FeatureList({required this.tier, required this.loc});

  @override
  Widget build(BuildContext context) {
    // Kredi limitleri — tier.py CREDIT_FREE_LIMITS değerleriyle eşleşir
    final blast        = _creditLimit(tier, 'blast');
    final boost        = _creditLimit(tier, 'boost');
    final aiDesc       = _creditLimit(tier, 'ai_desc');
    final reactivation = _creditLimit(tier, 'reactivation');
    final unlimitedLbl = loc.tOr('subFeatureUnlimited', 'Sınırsız');

    final features = [
      _FeatureRow(label: loc.tOr('proCreditsBlastName', 'Toplu Blast'),       value: blast),
      _FeatureRow(label: loc.tOr('proCreditsBoostName', 'Öne Çıkarma'),       value: boost),
      _FeatureRow(label: loc.tOr('proCreditsAiName', 'AI Fiyat Danışmanı'),   value: aiDesc),
      _FeatureRow(label: loc.tOr('proCreditsReactivationName', 'Reaktivasyon'), value: reactivation),
      _FeatureRow(
        label: loc.tOr('subFeatureLiveRecording', 'Yayın Kaydı'),
        value: UserTier.isProPlusOrAbove(tier) ? unlimitedLbl : '—',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          loc.tOr('subFeaturesTitle', 'Tüm Özellikler'),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white54, letterSpacing: 0.5),
        ),
        const SizedBox(height: 10),
        ...features,
      ],
    );
  }

  String _creditLimit(String tier, String feature) {
    final limits = <String, Map<String, int>>{
      'blast':        {UserTier.standard: 3,  UserTier.pro: 10, UserTier.proPlus: 20, UserTier.premium: 30},
      'boost':        {UserTier.standard: 0,  UserTier.pro: 3,  UserTier.proPlus: 6,  UserTier.premium: 10},
      'ai_desc':      {UserTier.standard: 0,  UserTier.pro: 6,  UserTier.proPlus: 15, UserTier.premium: 30},
      'reactivation': {UserTier.standard: 0,  UserTier.pro: 3,  UserTier.proPlus: 6,  UserTier.premium: 10},
    };
    final val = limits[feature]?[tier] ?? 0;
    return '$val/ay';
  }
}

class _FeatureRow extends StatelessWidget {
  final String label;
  final String value;
  const _FeatureRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 13, color: Colors.white70)),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
