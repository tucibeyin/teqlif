import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../config/app_colors.dart';
import '../config/theme.dart';
import '../config/api.dart'; // for imgUrl

class StreamerAvatarCard extends StatelessWidget {
  final Map<String, dynamic> streamer;
  final VoidCallback? onTap;
  const StreamerAvatarCard({super.key, required this.streamer, this.onTap});

  @override
  Widget build(BuildContext context) {
    final rawUrl = (streamer['profile_image_url'] as String?) ?? '';
    final imageUrl = rawUrl.isNotEmpty ? imgUrl(rawUrl) : null;
    final isVerified = streamer['is_verified'] == true;
    final isPremium = streamer['is_premium'] == true;
    final isLive = streamer['is_live'] == true;
    final username = streamer['username'] as String? ?? '';
    final initial = username.isNotEmpty ? username[0].toUpperCase() : '?';

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 72,
        child: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  // Gradient ring + white border + avatar (Story stilinde)
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
                        child: imageUrl != null && imageUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: imageUrl,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                                memCacheWidth: 150,
                                placeholder: (_, _) => _AvatarInitial(initial: initial, context: context),
                                errorWidget: (_, _, _) => _AvatarInitial(initial: initial, context: context),
                              )
                            : _AvatarInitial(initial: initial, context: context),
                      ),
                    ),
                  ),
                  // Premium badge
                  if (isPremium)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFF59E0B),
                          border: Border.all(color: AppColors.surface(context), width: 1.5),
                        ),
                        child: const Center(child: Text('👑', style: TextStyle(fontSize: 10))),
                      ),
                    ),
                  
                  // CANLI badge (üst kısım)
                  if (isLive)
                    Positioned(
                      top: 0,
                      left: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.surface(context), width: 1),
                        ),
                        child: const Text(
                          'CANLI',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 7,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 5),
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      '@$username',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary(context),
                      ),
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
      ),
    );
  }
}

class _AvatarInitial extends StatelessWidget {
  final String initial;
  final BuildContext context;
  const _AvatarInitial({required this.initial, required this.context});

  @override
  Widget build(BuildContext _) {
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
