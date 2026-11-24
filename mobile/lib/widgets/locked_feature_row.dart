import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/user_tier.dart';
import '../services/localization_service.dart';
import '../screens/profile_screen.dart';

/// Kilitli özellik satırı — §8.13 UI pattern'ı.
///
/// Kullanım: kalite seçici, PRO Araçları, Keşfet filtreler, yayın başlatma.
/// Tıklanınca WalletScreen'e yönlendirilir.
class LockedFeatureRow extends ConsumerWidget {
  /// Özellik adı (ör. "1080p Yayın", "Pazar Analizi")
  final String label;

  /// Kısa CTA metni (ör. "PRO+'ya geçerek 1080p yayın yap")
  final String ctaText;

  /// Gereken minimum tier (UserTier.tier1 | UserTier.tier2 | UserTier.tier3)
  final String requiredTier;

  /// Özel onTap handler — null ise WalletScreen açılır.
  final VoidCallback? onTap;

  const LockedFeatureRow({
    super.key,
    required this.label,
    required this.ctaText,
    this.requiredTier = UserTier.tier1,
    this.onTap,
  });

  /// Tier rengi (badge / icon için)
  Color _tierColor() {
    switch (requiredTier) {
      case UserTier.tier3: return const Color(0xFF0891B2);
      case UserTier.tier2: return const Color(0xFF7C3AED);
      default:               return const Color(0xFFD97706);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(localizationProvider);
    final color = _tierColor();

    return Opacity(
      opacity: 0.75,
      child: GestureDetector(
        onTap: onTap ?? () => _showUpgradeSheet(context, loc),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Icon(Icons.lock_outline, size: 14, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      ctaText,
                      style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 16, color: color),
            ],
          ),
        ),
      ),
    );
  }

  void _showUpgradeSheet(BuildContext context, TranslationPack loc) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => const WalletScreen()),
    );
  }
}

/// Kilitli chip versiyonu — tek satır çip olarak gösterim.
/// Kalite seçici ve filtreler için uygundur.
class LockedChip extends ConsumerWidget {
  final String label;
  final String requiredTier;
  final VoidCallback? onTap;

  const LockedChip({
    super.key,
    required this.label,
    this.requiredTier = UserTier.tier1,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(localizationProvider);
    final tierLabel = switch (requiredTier) {
      UserTier.tier2 => 'PRO+',
      UserTier.tier3 => 'PREMIUM',
      _ => 'PRO',
    };

    return GestureDetector(
      onTap: onTap ?? () => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            loc.tOr('streamQualityLocked', '$label için $tierLabel üyeliği gerekli')
                .replaceAll('{tier}', tierLabel),
          ),
          duration: const Duration(seconds: 2),
          action: SnackBarAction(
            label: loc.tOr('btnUpgrade', 'Yükselt'),
            onPressed: () => Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute(builder: (_) => const WalletScreen()),
            ),
          ),
        ),
      ),
      child: Opacity(
        opacity: 0.5,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
