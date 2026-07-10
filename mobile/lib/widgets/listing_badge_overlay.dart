import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// Shared seller badge overlay (PRO + seller type + trending).
/// Usage: Positioned.fill(child: ListingBadgeOverlay(listing: l))
class ListingBadgeOverlay extends StatelessWidget {
  final Map<String, dynamic> listing;
  final double badgeSize;
  final double pad;

  const ListingBadgeOverlay({
    super.key,
    required this.listing,
    this.badgeSize = 9,
    this.pad = 5,
  });

  @override
  Widget build(BuildContext context) {
    final isPro    = listing['seller_is_premium'] == true;
    final badge    = listing['seller_badge'] as String?;
    final trending = listing['is_trending'] == true;

    if (!isPro && badge == null && !trending) return const SizedBox.shrink();

    return IgnorePointer(
      child: Stack(
        children: [
          if (isPro)
            Positioned(
              top: pad,
              right: pad,
              child: _BadgePill(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0891B2), Color(0xFF06B6D4)],
                ),
                pad: pad,
                child: FaIcon(FontAwesomeIcons.crown, size: badgeSize - 2, color: Colors.white),
              ),
            ),
          if (badge == 'trusted_seller')
            Positioned(
              top: isPro ? pad + 18 : pad,
              right: pad,
              child: _BadgePill(
                color: const Color(0xFF16A34A),
                pad: pad,
                child: FaIcon(FontAwesomeIcons.userShield, size: badgeSize - 2, color: Colors.white),
              ),
            )
          else if (badge == 'active_seller')
            Positioned(
              top: isPro ? pad + 18 : pad,
              right: pad,
              child: _BadgePill(
                color: const Color(0xFFF59E0B),
                pad: pad,
                child: FaIcon(FontAwesomeIcons.bolt, size: badgeSize - 2, color: Colors.white),
              ),
            ),
          if (trending)
            Positioned(
              bottom: pad,
              right: pad,
              child: _BadgePill(
                color: Colors.deepOrange.withValues(alpha: 0.88),
                pad: pad,
                child: FaIcon(FontAwesomeIcons.fire, size: badgeSize - 1, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}

class _BadgePill extends StatelessWidget {
  final Widget child;
  final Color? color;
  final Gradient? gradient;
  final double pad;

  const _BadgePill({required this.child, this.color, this.gradient, this.pad = 5});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: pad, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        gradient: gradient,
        borderRadius: BorderRadius.circular(4),
      ),
      child: child,
    );
  }
}
