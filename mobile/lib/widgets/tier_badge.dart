import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../core/user_tier.dart';
import '../services/localization_service.dart';

/// Tier rozeti — rounded rectangle, PRO/PRO+/PREMIUM için.
/// Standard için hiçbir şey render edilmez.
class TierBadge extends ConsumerWidget {
  final String userType;
  final double fontSize;
  final double iconSize;

  const TierBadge({
    super.key,
    required this.userType,
    this.fontSize = 9,
    this.iconSize = 7,
  });

  static Color tierColor(String userType) {
    if (UserTier.isTier3OrAbove(userType)) return const Color(0xFF0891B2);
    return const Color(0xFFD97706);
  }

  static List<Color> tierGradient(String userType) {
    if (UserTier.isTier3OrAbove(userType)) return const [Color(0xFF0891B2), Color(0xFF06B6D4)];
    return const [Color(0xFFD97706), Color(0xFFFFD700)];
  }

  static String tierLabel(String userType, dynamic loc) {
    switch (userType) {
      case UserTier.tier4: return loc.tOr('tierLabelPremiumPlus', 'PREMIUM+');
      case UserTier.tier3: return loc.tOr('tierLabelPremium', 'PREMIUM');
      case UserTier.tier2: return loc.tOr('tierLabelProPlus', 'PRO+');
      case UserTier.tier1: return loc.tOr('tierLabelPro', 'PRO');
      default:             return loc.tOr('tierLabelNormal', 'Normal');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(localizationProvider);
    if (!UserTier.hasSubscription(userType)) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFF9CA3AF),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          tierLabel(userType, loc),
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: tierGradient(userType)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FaIcon(FontAwesomeIcons.crown, size: iconSize, color: Colors.white),
          const SizedBox(width: 3),
          Text(
            tierLabel(userType, loc),
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
