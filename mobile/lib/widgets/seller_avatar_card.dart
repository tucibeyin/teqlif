import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../config/app_colors.dart';
import '../config/theme.dart';
import '../config/api.dart';

class SellerAvatarCard extends StatelessWidget {
  final Map<String, dynamic> seller;
  final VoidCallback onTap;

  const SellerAvatarCard({super.key, required this.seller, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final rawAvatar = seller['profile_image_url'] as String?;
    final avatarUrl = rawAvatar != null ? imgUrl(rawAvatar) : null;
    final username = seller['username'] as String? ?? '';
    final initial = username.isNotEmpty ? username[0].toUpperCase() : '?';
    final isVerified = seller['is_verified'] == true;
    final isPremium = seller['is_premium'] == true;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72,
        margin: const EdgeInsets.only(right: 12),
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
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  padding: const EdgeInsets.all(2.5),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.surface(context),
                    ),
                    padding: const EdgeInsets.all(1.5),
                    child: ClipOval(
                      child: avatarUrl != null
                          ? CachedNetworkImage(
                              memCacheWidth: 400, memCacheHeight: 400, imageUrl: avatarUrl,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => _buildPlaceholder(context, initial),
                              errorWidget: (context, url, error) => _buildPlaceholder(context, initial),
                            )
                          : _buildPlaceholder(context, initial),
                    ),
                  ),
                ),
                if (isPremium)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0891B2), Color(0xFF06B6D4)],
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.surface(context), width: 1.5),
                      ),
                      child: const FaIcon(
                        FontAwesomeIcons.crown,
                        size: 9,
                        color: Colors.white,
                      ),
                    ),
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
                    padding: EdgeInsets.only(left: 3),
                    child: Icon(Icons.verified, size: 12, color: Color(0xFF2563EB)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context, String initial) {
    return Container(
      color: AppColors.primaryBg(context),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: kPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 20,
        ),
      ),
    );
  }
}
