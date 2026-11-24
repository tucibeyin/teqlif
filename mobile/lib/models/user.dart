import '../core/user_tier.dart';

class User {
  final int id;
  final String email;
  final String username;
  final String fullName;
  final bool isVerified;
  final String? locale;
  final String? localeUpdatedAt;
  final bool isPrivate;
  final String? phone;
  final bool phoneVerified;
  final String? profileImageUrl;
  final String? profileImageThumbUrl;
  final String userType;
  final String? planType;
  final bool autoRenewEnabled;
  final String? pendingTier;
  final String? lastTier;
  final int monthlyStreamMinutesUsed;

  /// Ücretli tier (PRO, PRO+ veya PREMIUM) ise true döner.
  bool get hasSubscription => UserTier.hasSubscription(userType);

  final bool onboardingCompleted;
  final String? websiteUrl;
  final String? instagramUrl;
  final String? kickUrl;
  final String? twitchUrl;
  final String? facebookUrl;
  final String? youtubeUrl;
  final String? tiktokUrl;

  User({
    required this.id,
    required this.email,
    required this.username,
    required this.fullName,
    required this.isVerified,
    this.locale,
    this.localeUpdatedAt,
    this.isPrivate = false,
    this.phone,
    this.phoneVerified = false,
    this.profileImageUrl,
    this.profileImageThumbUrl,
    this.userType = UserTier.standard,
    this.planType,
    this.autoRenewEnabled = true,
    this.pendingTier,
    this.lastTier,
    this.monthlyStreamMinutesUsed = 0,
    this.onboardingCompleted = false,
    this.websiteUrl,
    this.instagramUrl,
    this.kickUrl,
    this.twitchUrl,
    this.facebookUrl,
    this.youtubeUrl,
    this.tiktokUrl,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int,
      email: json['email'] as String? ?? '',
      username: json['username'] as String? ?? '',
      fullName: json['full_name'] as String? ?? '',
      isVerified: json['is_verified'] as bool? ?? false,
      locale: json['locale'] as String?,
      localeUpdatedAt: json['locale_updated_at'] as String?,
      isPrivate: json['is_private'] as bool? ?? false,
      phone: json['phone'] as String?,
      phoneVerified: json['phone_verified'] as bool? ?? false,
      profileImageUrl: json['profile_image_url'] as String?,
      profileImageThumbUrl: json['profile_image_thumb_url'] as String?,
      userType: json['user_type'] as String? ?? UserTier.standard,
      planType: json['plan_type'] as String?,
      autoRenewEnabled: json['auto_renew_enabled'] as bool? ?? true,
      pendingTier: json['pending_tier'] as String?,
      lastTier: json['last_tier'] as String?,
      monthlyStreamMinutesUsed: json['monthly_stream_minutes_used'] as int? ?? 0,
      onboardingCompleted: json['onboarding_completed'] as bool? ?? false,
      websiteUrl: json['website_url'] as String?,
      instagramUrl: json['instagram_url'] as String?,
      kickUrl: json['kick_url'] as String?,
      twitchUrl: json['twitch_url'] as String?,
      facebookUrl: json['facebook_url'] as String?,
      youtubeUrl: json['youtube_url'] as String?,
      tiktokUrl: json['tiktok_url'] as String?,
    );
  }
}
