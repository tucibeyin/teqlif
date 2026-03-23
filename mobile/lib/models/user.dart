class User {
  final int id;
  final String email;
  final String username;
  final String fullName;
  final bool isVerified;
  final String? profileImageUrl;
  final String? profileImageThumbUrl;

  User({
    required this.id,
    required this.email,
    required this.username,
    required this.fullName,
    required this.isVerified,
    this.profileImageUrl,
    this.profileImageThumbUrl,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int,
      email: json['email'] as String,
      username: json['username'] as String,
      fullName: json['full_name'] as String,
      isVerified: json['is_verified'] as bool? ?? false,
      profileImageUrl: json['profile_image_url'] as String?,
      profileImageThumbUrl: json['profile_image_thumb_url'] as String?,
    );
  }
}
