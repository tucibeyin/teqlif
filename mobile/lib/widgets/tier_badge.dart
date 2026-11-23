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
    switch (userType) {
      case UserTier.premium: return const Color(0xFF0891B2);
      case UserTier.proPlus: return const Color(0xFF7C3AED);
      default:               return const Color(0xFFD97706);
    }
  }

  static List<Color> tierGradient(String userType) {
    switch (userType) {
      case UserTier.premium: return const [Color(0xFF0891B2), Color(0xFF06B6D4)];
      case UserTier.proPlus: return const [Color(0xFF7C3AED), Color(0xFF9333EA)];
      default:               return const [Color(0xFFD97706), Color(0xFFFFD700)];
    }
  }

  static String tierLabel(String userType, dynamic loc) {
    switch (userType) {
      case UserTier.premium: return loc.tOr('tierLabelPremium', 'PREMIUM');
      case UserTier.proPlus: return loc.tOr('tierLabelProPlus', 'PRO+');
      case UserTier.pro:     return loc.tOr('tierLabelPro', 'PRO');
      default:               return loc.tOr('tierLabelNormal', 'Normal');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!UserTier.isPaidTier(userType)) return const SizedBox.shrink();
    final loc = ref.watch(localizationProvider);
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
