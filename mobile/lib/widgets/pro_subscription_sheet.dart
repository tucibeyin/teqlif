import 'dart:async';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/iap_service.dart';
import '../services/localization_service.dart';
import 'pro_badge_widget.dart';

/// Plan seçim kartı veri modeli
class _PlanOption {
  final String productId;
  final String labelKey;     // loc key
  final String? savingKey;   // loc key (opsiyonel tasarruf etiketi)
  final bool highlighted;

  const _PlanOption({
    required this.productId,
    required this.labelKey,
    this.savingKey,
    this.highlighted = false,
  });
}

const _plans = [
  _PlanOption(productId: 'teqlif_pro_1m', labelKey: 'proMonthly'),
  _PlanOption(productId: 'teqlif_pro_3m', labelKey: 'proQuarterly', savingKey: 'proSave10', highlighted: true),
  _PlanOption(productId: 'teqlif_pro_6m', labelKey: 'proBiannual', savingKey: 'proSave20'),
  _PlanOption(productId: 'teqlif_pro_12m', labelKey: 'proAnnual', savingKey: 'proSave30'),
];

class ProSubscriptionSheet extends StatefulWidget {
  final TranslationPack loc;
  final VoidCallback? onPurchaseSuccess;

  const ProSubscriptionSheet({
    super.key,
    required this.loc,
    this.onPurchaseSuccess,
  });

  @override
  State<ProSubscriptionSheet> createState() => _ProSubscriptionSheetState();
}

class _ProSubscriptionSheetState extends State<ProSubscriptionSheet> {
  final _iap = IAPService();
  String _selectedPlanId = 'teqlif_pro_1m';
  bool _loading = false;
  StreamSubscription<PurchaseDetails>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = _iap.purchaseStream.listen(_onPurchase);
    if (_iap.products.isEmpty) {
      _iap.loadProducts().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onPurchase(PurchaseDetails purchase) {
    if (!mounted) return;
    setState(() => _loading = false);
    if (purchase.status == PurchaseStatus.purchased ||
        purchase.status == PurchaseStatus.restored) {
      Navigator.pop(context);
      widget.onPurchaseSuccess?.call();
    }
  }

  Future<void> _subscribe() async {
    final product = _iap.products.firstWhere(
      (p) => p.id == _selectedPlanId,
      orElse: () => throw StateError('Ürün bulunamadı'),
    );
    setState(() => _loading = true);
    try {
      await _iap.buy(product);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _restore() async {
    setState(() => _loading = true);
    await _iap.restorePurchases();
    if (mounted) setState(() => _loading = false);
  }

  String _priceFor(String productId) {
    final p = _iap.products.firstWhere(
      (p) => p.id == productId,
      orElse: () => _DummyProduct(productId),
    );
    return p.price;
  }

  @override
  Widget build(BuildContext context) {
    final loc = widget.loc;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Başlık
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const ProBadgeWidget(fontSize: 13),
              const SizedBox(width: 8),
              Text(
                loc.t('proSheetTitle'),
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
            loc.t('proSheetSubtitle'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 20),

          // PRO fayda listesi
          _ProBenefits(loc: loc),
          const SizedBox(height: 20),

          // Plan seçim kartları
          ...(_plans.map((plan) => _PlanCard(
                plan: plan,
                price: _priceFor(plan.productId),
                selected: _selectedPlanId == plan.productId,
                onTap: () => setState(() => _selectedPlanId = plan.productId),
                loc: loc,
              ))),
          const SizedBox(height: 20),

          // Otomatik yenileme uyarısı (Apple zorunluluğu)
          Text(
            loc.t('proAutoRenewNotice'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white38, fontSize: 10, height: 1.5),
          ),
          const SizedBox(height: 16),

          // Abone ol CTA
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _loading ? null : _subscribe,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD97706),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      loc.t('proSubscribeButton'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 10),

          // Satın alımları geri yükle (Apple Guideline 3.1.1 zorunlu)
          TextButton(
            onPressed: _loading ? null : _restore,
            child: Text(
              loc.t('proRestorePurchases'),
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ),
          const SizedBox(height: 4),

          // EULA + Privacy Policy (Apple Guideline 3.1.2 zorunlu)
          _LegalLinks(loc: loc),
        ],
      ),
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
            Text(
              price,
              style: TextStyle(
                color: selected ? const Color(0xFFD97706) : Colors.white54,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            if (plan.highlighted) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  loc.t('proPopularBadge'),
                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Ürün bulunamazsa fiyat alanı için geçici yer tutucu
class _DummyProduct implements ProductDetails {
  final String _id;
  _DummyProduct(this._id);
  @override String get id => _id;
  @override String get title => '';
  @override String get description => '';
  @override String get price => '—';
  @override double get rawPrice => 0;
  @override String get currencyCode => '';
  @override String get currencySymbol => '';
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
