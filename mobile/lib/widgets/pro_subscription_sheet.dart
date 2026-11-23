import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/user_tier.dart';
import '../screens/viewmodels/pro_subscription_view_model.dart';
import '../services/iap_service.dart';
import '../services/localization_service.dart';

/// Plan seçim kartı veri modeli
class _PlanOption {
  final String productId;
  final String labelKey;
  final String? savingKey;
  final bool highlighted;
  final String? badgeLabelKey;

  const _PlanOption({
    required this.productId,
    required this.labelKey,
    this.savingKey,
    this.highlighted = false,
    this.badgeLabelKey,
  });
}

const _plansByTier = <String, List<_PlanOption>>{
  UserTier.pro: [
    _PlanOption(productId: 'teqlif_pro_1m',  labelKey: 'proMonthly'),
    _PlanOption(productId: 'teqlif_pro_3m',  labelKey: 'proQuarterly', savingKey: 'proSave10', highlighted: true, badgeLabelKey: 'proPopularBadge'),
    _PlanOption(productId: 'teqlif_pro_6m',  labelKey: 'proBiannual',  savingKey: 'proSave20'),
    _PlanOption(productId: 'teqlif_pro_12m', labelKey: 'proAnnual',    savingKey: 'proSave30', badgeLabelKey: 'proPlanBadgeBest'),
  ],
  UserTier.proPlus: [
    _PlanOption(productId: 'teqlif_pro_plus_1m',  labelKey: 'proMonthly'),
    _PlanOption(productId: 'teqlif_pro_plus_3m',  labelKey: 'proQuarterly', savingKey: 'proSave10', highlighted: true, badgeLabelKey: 'proPopularBadge'),
    _PlanOption(productId: 'teqlif_pro_plus_6m',  labelKey: 'proBiannual',  savingKey: 'proSave20'),
    _PlanOption(productId: 'teqlif_pro_plus_12m', labelKey: 'proAnnual',    savingKey: 'proSave30', badgeLabelKey: 'proPlanBadgeBest'),
  ],
  UserTier.premium: [
    _PlanOption(productId: 'teqlif_premium_1m',  labelKey: 'proMonthly'),
    _PlanOption(productId: 'teqlif_premium_3m',  labelKey: 'proQuarterly', savingKey: 'proSave10', highlighted: true, badgeLabelKey: 'proPopularBadge'),
    _PlanOption(productId: 'teqlif_premium_6m',  labelKey: 'proBiannual',  savingKey: 'proSave20'),
    _PlanOption(productId: 'teqlif_premium_12m', labelKey: 'proAnnual',    savingKey: 'proSave30', badgeLabelKey: 'proPlanBadgeBest'),
  ],
};

const _tierOrder = [UserTier.pro, UserTier.proPlus, UserTier.premium];
const _tierRank = <String, int>{UserTier.standard: 0, UserTier.pro: 1, UserTier.proPlus: 2, UserTier.premium: 3};

class ProSubscriptionSheet extends ConsumerStatefulWidget {
  final TranslationPack loc;
  final VoidCallback? onPurchaseSuccess;
  /// Kullanıcının mevcut subscription tier'ı (ör. 'pro'). Null = standard, tüm tier'lar gösterilir.
  final String? currentUserType;
  /// Açılışta seçili plan ID. Null ise varsayılan (highlighted) plan seçilir.
  final String? initialPlanId;

  const ProSubscriptionSheet({
    super.key,
    required this.loc,
    this.onPurchaseSuccess,
    this.currentUserType,
    this.initialPlanId,
  });

  @override
  ConsumerState<ProSubscriptionSheet> createState() => _ProSubscriptionSheetState();
}

class _ProSubscriptionSheetState extends ConsumerState<ProSubscriptionSheet> {
  late String _selectedTier;
  late String _selectedPlanId;

  List<String> _visibleTiers() {
    final currentRank = _tierRank[widget.currentUserType ?? UserTier.standard] ?? 0;
    return _tierOrder.where((t) => (_tierRank[t] ?? 0) > currentRank).toList();
  }

  @override
  void initState() {
    super.initState();
    final visible = _visibleTiers();
    // initialPlanId verilmişse onun tier'ını ve ID'sini seç
    if (widget.initialPlanId != null) {
      final tier = kProductTierMap[widget.initialPlanId];
      if (tier != null && visible.contains(tier)) {
        _selectedTier = tier;
        _selectedPlanId = widget.initialPlanId!;
        return;
      }
    }
    _selectedTier = visible.firstOrNull ?? 'pro';
    final plans = _plansByTier[_selectedTier] ?? _plansByTier['pro']!;
    _selectedPlanId = plans.firstWhere((p) => p.highlighted, orElse: () => plans.first).productId;
  }

  void _onTierChanged(String tier) {
    final plans = _plansByTier[tier] ?? _plansByTier['pro']!;
    setState(() {
      _selectedTier = tier;
      _selectedPlanId = plans.firstWhere((p) => p.highlighted, orElse: () => plans.first).productId;
    });
  }

  void _onPurchase(PurchaseDetails purchase) {
    if (!mounted) return;
    if (purchase.status == PurchaseStatus.pending) {
      // Ask to Buy / 3D provizyon — yükleniyor devam eder, snackbar göster
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.loc.t('iapPurchasePending'))),
      );
      return;
    }
    if (purchase.status == PurchaseStatus.purchased ||
        purchase.status == PurchaseStatus.restored) {
      Navigator.pop(context);
      widget.onPurchaseSuccess?.call();
    }
  }

  Future<void> _subscribe(List<ProductDetails> products) async {
    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.loc.t('iapProductsNotLoaded'))),
      );
      return;
    }
    final product = products.where((p) => p.id == _selectedPlanId).firstOrNull;
    if (product == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.loc.t('iapProductsNotLoaded'))),
      );
      return;
    }
    try {
      await ref.read(proSubscriptionViewModelProvider.notifier).buy(product);
    } catch (_) {}
  }

  Future<void> _restore() async {
    await ref.read(proSubscriptionViewModelProvider.notifier).restorePurchases();
  }

  String _priceFor(String productId, List<ProductDetails> products) =>
      products.where((p) => p.id == productId).firstOrNull?.price ?? '—';

  @override
  Widget build(BuildContext context) {
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
          SnackBar(content: Text(widget.loc.t('iapVerifyFailed'))),
        );
      },
    );

    final loading = vm.isPurchasing;
    final loc = widget.loc;
    final isUpgradeMode = widget.currentUserType != null && UserTier.isPaidTier(widget.currentUserType!);
    final visibleTiers = _visibleTiers();
    final isVip = widget.currentUserType == UserTier.premium;
    final currentPlans = _plansByTier[_selectedTier] ?? _plansByTier[UserTier.pro]!;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      minChildSize: 0.0,
      maxChildSize: 0.95,
      snap: true,
      snapSizes: const [0.9],
      shouldCloseOnMinExtent: true,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          controller: scrollController,
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            // Başlık
            Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFD97706), Color(0xFFFFD700)],
                  ),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Center(
                  child: FaIcon(FontAwesomeIcons.crown,
                      color: Colors.white, size: 13),
                ),
              ),
              const SizedBox(width: 9),
              Text(
                isUpgradeMode
                    ? loc.t('proUpgradeSheetTitle')
                    : loc.t('proSheetTitle'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            isUpgradeMode
                ? loc.t('proUpgradeSheetSubtitle')
                : loc.t('proSheetSubtitle'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 20),

          if (isVip) ...[
            // PREMIUM sahibi — zaten en yüksek tier
            const FaIcon(FontAwesomeIcons.crown, color: Color(0xFFFFD700), size: 32),
            const SizedBox(height: 12),
            Text(
              loc.t('walletProTopPlanTitle'),
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              loc.t('walletProTopPlanDesc'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 24),
          ] else ...[
            // PRO fayda listesi (sadece yeni üye akışında)
            if (!isUpgradeMode) ...[
              _ProBenefits(loc: loc),
              const SizedBox(height: 20),
            ],

            // Tier seçici (birden fazla tier görünürse göster)
            if (visibleTiers.length > 1) ...[
              _TierSelector(
                tiers: visibleTiers,
                selected: _selectedTier,
                onTierChanged: _onTierChanged,
                loc: loc,
              ),
              const SizedBox(height: 16),
            ],

            // Plan seçim kartları (seçili tier'a göre)
            ...currentPlans.map((plan) => _PlanCard(
                  plan: plan,
                  price: _priceFor(plan.productId, vm.products),
                  selected: _selectedPlanId == plan.productId,
                  onTap: () => setState(() => _selectedPlanId = plan.productId),
                  loc: loc,
                )),
            const SizedBox(height: 20),

            // Otomatik yenileme uyarısı (Apple zorunluluğu)
            Text(
              loc.t('proAutoRenewNotice'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38, fontSize: 10, height: 1.5),
            ),
            const SizedBox(height: 16),

            // CTA butonu
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: loading ? null : () => _subscribe(vm.products),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFD97706),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: loading
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        isUpgradeMode
                            ? loc.t('proUpgradeButton')
                            : loc.t('proSubscribeButton'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 10),

            // Satın alımları geri yükle (Apple Guideline 3.1.1 zorunlu — sadece yeni üye akışında)
            if (!isUpgradeMode)
              TextButton(
                onPressed: loading ? null : _restore,
                child: Text(
                  loc.t('proRestorePurchases'),
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ),
            const SizedBox(height: 4),

            // EULA + Privacy Policy (Apple Guideline 3.1.2 zorunlu)
            _LegalLinks(loc: loc),
          ],
        ],
          ),
        ),
      ),
    );
  }
}

String _tierLabel(TranslationPack loc, String tier) {
  switch (tier) {
    case UserTier.pro: return loc.tOr('tierLabelPro', 'PRO');
    case UserTier.proPlus: return loc.tOr('tierLabelProPlus', 'PRO+');
    case UserTier.premium: return loc.tOr('tierLabelPremium', 'PREMIUM');
    default: return tier.toUpperCase();
  }
}

Color _tierAccent(String tier) {
  switch (tier) {
    case UserTier.pro: return const Color(0xFFD97706);
    case UserTier.proPlus: return const Color(0xFF7C3AED);
    case UserTier.premium: return const Color(0xFF0EA5E9);
    default: return const Color(0xFFD97706);
  }
}

class _TierSelector extends StatelessWidget {
  final List<String> tiers;
  final String selected;
  final ValueChanged<String> onTierChanged;
  final TranslationPack loc;

  const _TierSelector({
    required this.tiers,
    required this.selected,
    required this.onTierChanged,
    required this.loc,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: tiers.asMap().entries.map((entry) {
        final tier = entry.value;
        final isSelected = selected == tier;
        final accent = _tierAccent(tier);
        return Expanded(
          child: GestureDetector(
            onTap: () => onTierChanged(tier),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: EdgeInsetsDirectional.only(end: entry.key < tiers.length - 1 ? 6 : 0),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? accent.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? accent : Colors.white12,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Text(
                _tierLabel(loc, tier),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isSelected ? accent : Colors.white54,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                  fontSize: 13,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ProBenefits extends StatelessWidget {
  final TranslationPack loc;
  const _ProBenefits({required this.loc});

  @override
  Widget build(BuildContext context) {
    final benefits = [
      ('proBenefit1', Icons.percent_rounded),
      ('proBenefit2', Icons.analytics_outlined),
      ('proBenefit3', Icons.star_outline_rounded),
      ('proBenefit4', Icons.notifications_active_outlined),
    ];
    return Column(
      children: benefits.map((b) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(b.$2, color: const Color(0xFFD97706), size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                loc.t(b.$1),
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          ],
        ),
      )).toList(),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final _PlanOption plan;
  final String price;
  final bool selected;
  final VoidCallback onTap;
  final TranslationPack loc;

  const _PlanCard({
    required this.plan,
    required this.price,
    required this.selected,
    required this.onTap,
    required this.loc,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFD97706).withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? const Color(0xFFD97706) : Colors.white12,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? const Color(0xFFD97706) : Colors.white38,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    loc.t(plan.labelKey),
                    style: TextStyle(
                      color: selected ? Colors.white : Colors.white70,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                  if (plan.savingKey != null)
                    Text(
                      loc.t(plan.savingKey!),
                      style: const TextStyle(color: Color(0xFF6EE7B7), fontSize: 11),
                    ),
                ],
              ),
            ),
            if (plan.badgeLabelKey != null) ...[
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: plan.highlighted
                      ? const Color(0xFF10B981)
                      : const Color(0xFFD97706),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  loc.t(plan.badgeLabelKey!),
                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
                ),
              ),
            ],
            Text(
              price,
              style: TextStyle(
                color: selected ? const Color(0xFFD97706) : Colors.white54,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// EULA + Privacy Policy satırı (Apple Guideline 3.1.2 zorunlu)
class _LegalLinks extends StatelessWidget {
  final TranslationPack loc;
  const _LegalLinks({required this.loc});

  static const _kTermsUrl    = 'https://www.teqlif.com/kullanim-sartlari.html';
  static const _kPrivacyUrl  = 'https://www.teqlif.com/gizlilik-politikasi';

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(color: Colors.white38, fontSize: 10);
    const linkStyle = TextStyle(
      color: Colors.white54,
      fontSize: 10,
      decoration: TextDecoration.underline,
      decorationColor: Colors.white54,
    );
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 2,
      children: [
        Text(loc.t('proLegalLine'), style: style),
        GestureDetector(
          onTap: () => _launch(_kTermsUrl),
          child: Text(loc.t('proTermsLink'), style: linkStyle),
        ),
        Text(loc.t('proAndLabel'), style: style),
        GestureDetector(
          onTap: () => _launch(_kPrivacyUrl),
          child: Text(loc.t('proPrivacyLink'), style: linkStyle),
        ),
        Text(loc.t('proLegalSuffix'), style: style),
      ],
    );
  }
}
