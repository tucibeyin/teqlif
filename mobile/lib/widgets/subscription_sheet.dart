import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/user_tier.dart';
import '../screens/viewmodels/subscription_view_model.dart';
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
  UserTier.tier1: [
    _PlanOption(productId: 'teqlif_pro_1m',   labelKey: 'subMonthly'),
    _PlanOption(productId: 'teqlif_pro_12m',  labelKey: 'subAnnual', savingKey: 'subSave25', highlighted: true, badgeLabelKey: 'subPlanBadgeBest'),
  ],
  UserTier.tier2: [
    _PlanOption(productId: 'teqlif_pro_plus_1m',   labelKey: 'subMonthly'),
    _PlanOption(productId: 'teqlif_pro_plus_12m',  labelKey: 'subAnnual', savingKey: 'subSave25', highlighted: true, badgeLabelKey: 'subPlanBadgeBest'),
  ],
  UserTier.tier3: [
    _PlanOption(productId: 'teqlif_premium_1m',   labelKey: 'subMonthly'),
    _PlanOption(productId: 'teqlif_premium_12m',  labelKey: 'subAnnual', savingKey: 'subSave25', highlighted: true, badgeLabelKey: 'subPlanBadgeBest'),
  ],
  UserTier.tier4: [
    _PlanOption(productId: 'teqlif_premium_plus_1m',   labelKey: 'subMonthly'),
    _PlanOption(productId: 'teqlif_premium_plus_12m',  labelKey: 'subAnnual', savingKey: 'subSave25', highlighted: true, badgeLabelKey: 'subPlanBadgeBest'),
  ],
};

const _tierOrder = [UserTier.tier1, UserTier.tier2, UserTier.tier3, UserTier.tier4];
const _tierRank = <String, int>{
  UserTier.standard: 0,
  UserTier.tier1:    1,
  UserTier.tier2:    2,
  UserTier.tier3:    3,
  UserTier.tier4:    4,
};

class SubscriptionSheet extends ConsumerStatefulWidget {
  final TranslationPack loc;
  final VoidCallback? onPurchaseSuccess;
  final String? currentUserType;
  final String? initialPlanId;

  const SubscriptionSheet({
    super.key,
    required this.loc,
    this.onPurchaseSuccess,
    this.currentUserType,
    this.initialPlanId,
  });

  @override
  ConsumerState<SubscriptionSheet> createState() => _SubscriptionSheetState();
}

class _SubscriptionSheetState extends ConsumerState<SubscriptionSheet>
    with TickerProviderStateMixin {
  late String _selectedTier;
  late String _selectedPlanId;
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat(reverse: true);

    // initialPlanId verilmişse onun tier'ını ve ID'sini seç
    if (widget.initialPlanId != null) {
      final tier = kProductTierMap[widget.initialPlanId];
      if (tier != null && _tierOrder.contains(tier)) {
        _selectedTier = tier;
        _selectedPlanId = widget.initialPlanId!;
        return;
      }
    }
    // Varsayılan: kullanıcının mevcut tier'ının bir üstü, minimum PRO
    final currentRank = _tierRank[widget.currentUserType ?? UserTier.standard] ?? 0;
    _selectedTier = _tierOrder.firstWhere(
      (t) => (_tierRank[t] ?? 0) > currentRank,
      orElse: () => UserTier.tier1,
    );
    final plans = _plansByTier[_selectedTier] ?? _plansByTier[UserTier.tier1]!;
    _selectedPlanId = plans.firstWhere((p) => p.highlighted, orElse: () => plans.first).productId;
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _onTierChanged(String tier) {
    final plans = _plansByTier[tier] ?? _plansByTier[UserTier.tier1]!;
    setState(() {
      _selectedTier = tier;
      _selectedPlanId = plans.firstWhere((p) => p.highlighted, orElse: () => plans.first).productId;
    });
  }

  void _onPurchase(PurchaseDetails purchase) {
    if (!mounted) return;
    if (purchase.status == PurchaseStatus.pending) {
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
      await ref.read(subscriptionViewModelProvider.notifier).buy(product);
    } catch (_) {}
  }

  Future<void> _restore() async {
    await ref.read(subscriptionViewModelProvider.notifier).restorePurchases();
  }

  String _priceFor(String productId, List<ProductDetails> products) =>
      products.where((p) => p.id == productId).firstOrNull?.price ?? '—';

  @override
  Widget build(BuildContext context) {
    final vm = ref.watch(subscriptionViewModelProvider);

    ref.listen<PurchaseDetails?>(
      subscriptionViewModelProvider.select((s) => s.lastPurchase),
      (prev, next) {
        if (next == null || next == prev) return;
        _onPurchase(next);
      },
    );

    ref.listen<String?>(
      subscriptionViewModelProvider.select((s) => s.error),
      (_, error) {
        if (error == null || !mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.loc.t('iapVerifyFailed'))),
        );
      },
    );

    final loading = vm.isPurchasing;
    final loc = widget.loc;
    final isUpgradeMode = widget.currentUserType != null && UserTier.hasSubscription(widget.currentUserType!);
    final isVip = UserTier.isTier4(widget.currentUserType ?? UserTier.standard);
    final currentPlans = _plansByTier[_selectedTier] ?? _plansByTier[UserTier.tier1]!;
    final isCurrent = widget.currentUserType == _selectedTier;
    final isLower = (_tierRank[widget.currentUserType ?? UserTier.standard] ?? 0) >
        (_tierRank[_selectedTier] ?? 0);

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
                      child: FaIcon(FontAwesomeIcons.crown, color: Colors.white, size: 13),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Text(
                    isUpgradeMode ? loc.t('subUpgradeSheetTitle') : loc.t('subSheetTitle'),
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                isUpgradeMode ? loc.t('subUpgradeSheetSubtitle') : loc.t('subSheetSubtitle'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 20),

              // ── Tier seçici (her zaman 3 tab, en üstte) ──
              _TierSelector(
                tiers: _tierOrder,
                selected: _selectedTier,
                currentUserType: widget.currentUserType,
                onTierChanged: _onTierChanged,
                pulseCtrl: _pulseCtrl,
                loc: loc,
              ),
              const SizedBox(height: 20),

              if (isVip) ...[
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
                // Tier'a göre değişen içerik
                _TierBenefits(tier: _selectedTier, loc: loc),
                const SizedBox(height: 20),

                // Plan seçim kartları (seçili tier'a göre)
                if (!isCurrent && !isLower) ...[
                  ...currentPlans.map((plan) => _PlanCard(
                        plan: plan,
                        price: _priceFor(plan.productId, vm.products),
                        selectedTier: _selectedTier,
                        selected: _selectedPlanId == plan.productId,
                        onTap: () => setState(() => _selectedPlanId = plan.productId),
                        loc: loc,
                      )),
                  const SizedBox(height: 20),

                  Text(
                    loc.t('subAutoRenewNotice'),
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
                        backgroundColor: _tierAccent(_selectedTier),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: loading
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text(
                              _ctaLabel(loc, _selectedTier),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  if (!isUpgradeMode)
                    TextButton(
                      onPressed: loading ? null : _restore,
                      child: Text(
                        loc.t('subRestorePurchases'),
                        style: const TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    ),
                ] else ...[
                  // Mevcut veya daha düşük tier — satın alma gizli
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          isCurrent
                              ? loc.tOr('subPlanCurrentBadge', 'Mevcut Planın')
                              : loc.tOr('subPlanLowerTier', 'Mevcut planın daha yüksek'),
                          style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                const SizedBox(height: 4),
                _LegalLinks(loc: loc),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Yardımcılar ───────────────────────────────────────────────────────────────

String _tierLabel(TranslationPack loc, String tier) {
  switch (tier) {
    case UserTier.tier4: return loc.tOr('tierLabelPremiumPlus', 'PREMIUM+');
    case UserTier.tier3: return loc.tOr('tierLabelPremium', 'PREMIUM');
    case UserTier.tier2: return loc.tOr('tierLabelProPlus', 'PRO+');
    case UserTier.tier1: return loc.tOr('tierLabelPro', 'PRO');
    default:             return tier.toUpperCase();
  }
}

String _ctaLabel(TranslationPack loc, String tier) {
  switch (tier) {
    case UserTier.tier4: return loc.tOr('subCtaTier4', "PREMIUM+'a Geç");
    case UserTier.tier3: return loc.tOr('subCtaTier3', "PREMIUM'a Geç");
    case UserTier.tier2: return loc.tOr('subCtaTier2', "PRO+'a Geç");
    default:             return loc.tOr('subCtaTier1', "PRO'ya Geç");
  }
}

Color _tierAccent(String tier) {
  if (UserTier.isTier3OrAbove(tier)) return const Color(0xFF0EA5E9); // cyan
  return const Color(0xFFD97706); // altın — tier1 ve tier2
}

IconData _tierFaIcon(String tier) {
  if (UserTier.isTier3OrAbove(tier)) return FontAwesomeIcons.gem;
  if (tier == UserTier.tier2)        return FontAwesomeIcons.crown;
  return FontAwesomeIcons.bolt;
}

// ── Tier seçici (pulse animasyonlu, her zaman 3 tab) ─────────────────────────

class _TierSelector extends StatelessWidget {
  final List<String> tiers;
  final String selected;
  final String? currentUserType;
  final ValueChanged<String> onTierChanged;
  final AnimationController pulseCtrl;
  final TranslationPack loc;

  const _TierSelector({
    required this.tiers,
    required this.selected,
    required this.currentUserType,
    required this.onTierChanged,
    required this.pulseCtrl,
    required this.loc,
  });

  Widget _buildBtn(String tier, double p) {
    final sel    = selected == tier;
    final accent = _tierAccent(tier);
    return Expanded(
      child: GestureDetector(
        onTap: () => onTierChanged(tier),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: sel
                ? accent.withValues(alpha: 0.22)
                : accent.withValues(alpha: 0.04 + 0.08 * p),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: sel ? accent : accent.withValues(alpha: 0.2 + 0.4 * p),
              width: sel ? 2 : 1,
            ),
            boxShadow: sel
                ? [BoxShadow(color: accent.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 2))]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              FaIcon(
                _tierFaIcon(tier),
                size: 10,
                color: sel ? accent : accent.withValues(alpha: 0.4 + 0.5 * p),
              ),
              const SizedBox(width: 5),
              Text(
                _tierLabel(loc, tier),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: sel ? accent : accent.withValues(alpha: 0.4 + 0.5 * p),
                  fontWeight: sel ? FontWeight.w800 : FontWeight.w500,
                  fontSize: 13,
                  letterSpacing: 0.5,
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
    return AnimatedBuilder(
      animation: pulseCtrl,
      builder: (context, _) {
        final p = pulseCtrl.value;
        return Column(
          children: [
            Row(children: [
              _buildBtn(tiers[0], p), // PRO
              const SizedBox(width: 6),
              _buildBtn(tiers[1], p), // PRO+
            ]),
            const SizedBox(height: 6),
            Row(children: [
              _buildBtn(tiers[2], p), // PREMIUM
              const SizedBox(width: 6),
              _buildBtn(tiers[3], p), // PREMIUM+
            ]),
          ],
        );
      },
    );
  }
}

// ── Tier'a özel açıklama içeriği ─────────────────────────────────────────────

class _TierBenefits extends StatelessWidget {
  final String tier;
  final TranslationPack loc;
  const _TierBenefits({required this.tier, required this.loc});

  @override
  Widget build(BuildContext context) {
    final accent = _tierAccent(tier);

    final benefits = switch (tier) {
      UserTier.tier4 => [
        (Icons.hd_rounded,                  loc.tOr('premiumPlus_benefit1', 'Full HD (1080p) yayın kalitesi')),
        (Icons.percent_rounded,             loc.tOr('premiumPlus_benefit2', '%100 gelir payı — kesintisiz')),
        (Icons.all_inclusive_rounded,       loc.tOr('premiumPlus_benefit3', 'Sınırsız yayın süresi')),
        (Icons.auto_awesome_rounded,        loc.tOr('premiumPlus_benefit4', 'Tüm krediler + öncelikli destek')),
        (Icons.check_circle_outline,        loc.tOr('subBenefitToolsIncluded', 'teqlif Araçları: Dahil')),
      ],
      UserTier.tier3 => [
        (Icons.hd_rounded,                  loc.tOr('premium_benefit1', 'Full HD (1080p) yayın kalitesi')),
        (Icons.percent_rounded,             loc.tOr('premium_benefit2', '%100 gelir payı — kesintisiz')),
        (Icons.videocam_outlined,           loc.tOr('premium_benefit3', '360 saat/ay yayın süresi')),
        (Icons.auto_awesome_rounded,        loc.tOr('premium_benefit4', 'Tüm krediler + öncelikli destek')),
        (Icons.check_circle_outline,        loc.tOr('subBenefitToolsIncluded', 'teqlif Araçları: Dahil')),
      ],
      UserTier.tier2 => [
        (Icons.hd_outlined,                 loc.tOr('subPlus_benefit1', 'HD (720p) yayın kalitesi')),
        (Icons.percent_rounded,             loc.tOr('subPlus_benefit2', '%90 gelir payı')),
        (Icons.videocam_outlined,           loc.tOr('subPlus_benefit3', '180 saat/ay yayın süresi')),
        (Icons.rocket_launch_outlined,      loc.tOr('subPlus_benefit4', 'Blast, Boost ve AI Danışman kredileri')),
        (Icons.auto_graph_outlined,         loc.tOr('subBenefitToolsPartial', 'Satış ve İlan Analizi: Dahil')),
      ],
      _ /* PRO */ => [
        (Icons.hd_outlined,                 loc.tOr('pro_benefit1', 'HD (720p) yayın kalitesi')),
        (Icons.percent_rounded,             loc.tOr('pro_benefit2', '%75 gelir payı')),
        (Icons.videocam_outlined,           loc.tOr('pro_benefit3', '90 saat/ay yayın süresi')),
        (Icons.notifications_active_outlined, loc.tOr('pro_benefit4', 'Blast kredileri ve analiz araçları')),
        (Icons.lock_outline,                loc.tOr('subBenefitToolsLocked', 'teqlif Araçları: Erişim yok')),
      ],
    };

    // Kredi sayıları — tier.py CREDIT_FREE_LIMITS ile senkron
    final (int blast, int boost, int ai, int reaktivasyon) = switch (tier) {
      UserTier.tier4 => (30, 10, 30, 10),
      UserTier.tier3 => (30, 10, 30, 10),
      UserTier.tier2 => (20,  6, 15,  6),
      _              => (10,  3,  6,  3),  // tier1 / PRO
    };

    // (icon, labelKey, labelFallback, count, descKey, descFallback)
    final credits = [
      (Icons.campaign_outlined,      'subCreditBlast',        'Blast',        blast,        'subCreditBlastDesc',        'İlanla ilgilenebilecek kullanıcılara toplu bildirim'),
      (Icons.rocket_launch_outlined, 'subCreditBoost',        'Boost',        boost,        'subCreditBoostDesc',        'İlan/yayın öne çıkarma'),
      (Icons.psychology_outlined,    'subCreditAi',           'AI Danışman',  ai,           'subCreditAiDesc',           'Yapay zeka ile ilan açıklaması'),
      (Icons.refresh_rounded,        'subCreditReactivation', 'Reaktivasyon', reaktivasyon, 'subCreditReactivationDesc', 'Süresi dolan ilanı yeniden aktifleştirme'),
    ];

    final countSuffix = loc.tOr('subCreditCountSuffix', 'adet/ay');
    return Column(
      children: [
        ...benefits.map((b) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(b.$1, color: accent, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  b.$2,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ],
          ),
        )),
        ...credits.map((c) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(c.$1, color: accent, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${loc.tOr(c.$2, c.$3)}: ${loc.tOr(c.$5, c.$6)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${c.$4} $countSuffix',
                style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        )),
      ],
    );
  }
}

// ── Plan kartı ────────────────────────────────────────────────────────────────

class _PlanCard extends StatelessWidget {
  final _PlanOption plan;
  final String price;
  final String selectedTier;
  final bool selected;
  final VoidCallback onTap;
  final TranslationPack loc;

  const _PlanCard({
    required this.plan,
    required this.price,
    required this.selectedTier,
    required this.selected,
    required this.onTap,
    required this.loc,
  });

  @override
  Widget build(BuildContext context) {
    final accent = _tierAccent(selectedTier);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? accent : Colors.white12,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? accent : Colors.white38,
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
                  color: plan.highlighted ? const Color(0xFF10B981) : accent,
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
                color: selected ? accent : Colors.white54,
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

  static const _kTermsUrl   = 'https://www.teqlif.com/kullanim-sartlari.html';
  static const _kPrivacyUrl = 'https://www.teqlif.com/gizlilik-politikasi';

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
      color: Colors.white54, fontSize: 10,
      decoration: TextDecoration.underline, decorationColor: Colors.white54,
    );
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 2,
      children: [
        Text(loc.t('subLegalLine'), style: style),
        GestureDetector(onTap: () => _launch(_kTermsUrl),   child: Text(loc.t('subTermsLink'),   style: linkStyle)),
        Text(loc.t('subAndLabel'), style: style),
        GestureDetector(onTap: () => _launch(_kPrivacyUrl), child: Text(loc.t('subPrivacyLink'), style: linkStyle)),
        Text(loc.t('subLegalSuffix'), style: style),
      ],
    );
  }
}
