import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../services/image_cache_manager.dart';
import '../config/app_colors.dart';
import '../config/theme.dart';
import 'package:teqlif/core/network/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/user_tier.dart';
import '../ui_library/components/badges/tier_crown_badge.dart';

class SellerAvatarCard extends ConsumerWidget {
  final Map<String, dynamic> seller;
  final VoidCallback onTap;

  const SellerAvatarCard({super.key, required this.seller, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rawAvatar = seller['profile_image_url'] as String?;
    final avatarUrl = rawAvatar != null ? ref.read(apiClientProvider).imgUrl(rawAvatar) : null;
    final username = seller['username'] as String? ?? '';
    final initial = username.isNotEmpty ? username[0].toUpperCase() : '?';
    final isVerified = seller['is_verified'] == true;
    final sellerUserType = seller['user_type'] as String? ?? UserTier.standard;
    final isPremium = UserTier.hasSubscription(sellerUserType);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72,
        margin: const EdgeInsetsDirectional.only(end: 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              children: [
                Container(
                  width: 62,
                  height: 62,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [kPrimary, kPrimaryLight, Color(0xFF7C3AED)],
                      begin: AlignmentDirectional.topStart,
                      end: AlignmentDirectional.bottomEnd,
                    ),
                  ),
                  padding: const EdgeInsets.all(2.5),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.surface(context),
                    ),
                    padding: const EdgeInsets.all(1.5),
                    child: CircleAvatar(
                      radius: 27,
                      backgroundColor: AppColors.primaryBg(context),
                      backgroundImage: avatarUrl != null
                          ? CachedNetworkImageProvider(
                              avatarUrl,
                              cacheKey: TeqlifCacheManager.avatarCacheKey(username, avatarUrl),
                              cacheManager: TeqlifCacheManager(),
                            )
                          : null,
                      child: avatarUrl == null ? Text(initial, style: TextStyle(color: kPrimary, fontWeight: FontWeight.w700, fontSize: 20)) : null,
                    ),
                  ),
                ),
                if (isPremium)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: TierCrownBadge(userType: sellerUserType, iconSize: 9, padding: 4),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    '@$username',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
                if (isVerified)
                  const Padding(
                    padding: EdgeInsetsDirectional.only(start: 3),
                    child: Icon(Icons.verified, size: 12, color: Color(0xFF2563EB)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

}
