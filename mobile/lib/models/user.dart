class User {
  final int id;
  final String email;
  final String username;
  final String fullName;
  final bool isVerified;
  final String? locale;
  final bool isPrivate;
  final String? phone;
  final bool phoneVerified;
  final String? profileImageUrl;
  final String? profileImageThumbUrl;
  final bool isPremium;
  final String? planType;
  final bool onboardingCompleted;

  User({
    required this.id,
    required this.email,
    required this.username,
    required this.fullName,
    required this.isVerified,
    this.locale,
    this.isPrivate = false,
    this.phone,
    this.phoneVerified = false,
    this.profileImageUrl,
    this.profileImageThumbUrl,
    this.isPremium = false,
    this.planType,
    this.onboardingCompleted = false,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int,
      email: json['email'] as String,
      username: json['username'] as String,
      fullName: json['full_name'] as String,
      isVerified: json['is_verified'] as bool? ?? false,
      locale: json['locale'] as String?,
      isPrivate: json['is_private'] as bool? ?? false,
      phone: json['phone'] as String?,
      phoneVerified: json['phone_verified'] as bool? ?? false,
      profileImageUrl: json['profile_image_url'] as String?,
      profileImageThumbUrl: json['profile_image_thumb_url'] as String?,
      isPremium: json['is_premium'] as bool? ?? false,
      planType: json['plan_type'] as String?,
      onboardingCompleted: json['onboarding_completed'] as bool? ?? false,
    );
  }
}
