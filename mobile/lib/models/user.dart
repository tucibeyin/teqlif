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
  final bool isPremium;
  final String? planType;
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
    this.isPremium = false,
    this.planType,
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
      email: json['email'] as String,
      username: json['username'] as String,
      fullName: json['full_name'] as String,
      isVerified: json['is_verified'] as bool? ?? false,
      locale: json['locale'] as String?,
      localeUpdatedAt: json['locale_updated_at'] as String?,
      isPrivate: json['is_private'] as bool? ?? false,
      phone: json['phone'] as String?,
      phoneVerified: json['phone_verified'] as bool? ?? false,
      profileImageUrl: json['profile_image_url'] as String?,
      profileImageThumbUrl: json['profile_image_thumb_url'] as String?,
      isPremium: json['is_premium'] as bool? ?? false,
      planType: json['plan_type'] as String?,
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
