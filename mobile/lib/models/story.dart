/// Backend `UserStoryGroupResponse` şemasının Flutter karşılığı.

class StoryAuthor {
  final int id;
  final String username;
  final String fullName;
  final String? profileImageUrl;
  final String? profileImageThumbUrl;

  StoryAuthor({
    required this.id,
    required this.username,
    required this.fullName,
    this.profileImageUrl,
    this.profileImageThumbUrl,
  });

  factory StoryAuthor.fromJson(Map<String, dynamic> json) => StoryAuthor(
        id: json['id'] as int,
        username: json['username'] as String,
        fullName: json['full_name'] as String,
        profileImageUrl: json['profile_image_url'] as String?,
        profileImageThumbUrl: json['profile_image_thumb_url'] as String?,
      );
}

class StoryItem {
  final int id;
  final String videoUrl;
  final String? thumbnailUrl;
  final DateTime expiresAt;
  final DateTime createdAt;

  StoryItem({
    required this.id,
    required this.videoUrl,
    this.thumbnailUrl,
    required this.expiresAt,
    required this.createdAt,
  });

  factory StoryItem.fromJson(Map<String, dynamic> json) => StoryItem(
        id: json['id'] as int,
        videoUrl: json['video_url'] as String,
        thumbnailUrl: json['thumbnail_url'] as String?,
        expiresAt: DateTime.parse(json['expires_at'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class UserStoryGroup {
  final StoryAuthor user;
  final List<StoryItem> stories;
  final DateTime latestStoryAt;

  UserStoryGroup({
    required this.user,
    required this.stories,
    required this.latestStoryAt,
  });

  factory UserStoryGroup.fromJson(Map<String, dynamic> json) => UserStoryGroup(
        user: StoryAuthor.fromJson(json['user'] as Map<String, dynamic>),
        stories: (json['stories'] as List)
            .map((s) => StoryItem.fromJson(s as Map<String, dynamic>))
            .toList(),
        latestStoryAt: DateTime.parse(json['latest_story_at'] as String),
      );
}
