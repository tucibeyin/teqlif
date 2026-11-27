import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../../config/app_colors.dart';
import '../../../core/user_tier.dart';

/// Tier rozeti — avatar'ın sağ alt köşesine `Positioned` ile yerleştir.
/// hasSubscription değilse SizedBox.shrink() döner.
///
/// PRO / PRO+   → altın gradyanı  [0xFFD97706 → 0xFFFFD700]
/// PREMIUM / PREMIUM+ → teqlif cyan [0xFF0284C7 → 0xFF38BDF8]
class TierCrownBadge extends StatelessWidget {
  final String userType;
  final double iconSize;
  final double padding;
  final double borderWidth;

  const TierCrownBadge({
    super.key,
    required this.userType,
    this.iconSize = 9,
    this.padding = 3,
    this.borderWidth = 1.5,
  });

  @override
  Widget build(BuildContext context) {
    if (!UserTier.hasSubscription(userType)) return const SizedBox.shrink();
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: UserTier.crownGradient(userType)),
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.surface(context), width: borderWidth),
      ),
      child: FaIcon(FontAwesomeIcons.crown, size: iconSize, color: Colors.white),
    );
  }
}
