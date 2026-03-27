/// Backend `UserStoryGroupResponse` hybrid şemasının Flutter karşılığı.
///
/// story_type değerleri:
///   'video'         → normal video hikayesi; videoUrl dolu.
///   'live_redirect' → kullanıcı şu an canlı yayında; streamId dolu, video alanları null.

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

  /// 'video' veya 'live_redirect'
  final String storyType;

  // ── Video alanları (storyType == 'video' olduğunda dolu) ──────────────────
  final String? videoUrl;
  final String? thumbnailUrl;
  final DateTime? expiresAt;
  final DateTime? createdAt;

  // ── Canlı yayın alanı (storyType == 'live_redirect' olduğunda dolu) ───────
  final int? streamId;

  bool get isVideo => storyType == 'video';
  bool get isImage => storyType == 'image';
  bool get isLiveRedirect => storyType == 'live_redirect';

  StoryItem({
    required this.id,
    required this.storyType,
    this.videoUrl,
    this.thumbnailUrl,
    this.expiresAt,
    this.createdAt,
    this.streamId,
  });

  factory StoryItem.fromJson(Map<String, dynamic> json) => StoryItem(
        id: json['id'] as int,
        storyType: json['story_type'] as String,
        videoUrl: json['video_url'] as String?,
        thumbnailUrl: json['thumbnail_url'] as String?,
        expiresAt: json['expires_at'] != null
            ? DateTime.parse(json['expires_at'] as String)
            : null,
        createdAt: json['created_at'] != null
            ? DateTime.parse(json['created_at'] as String)
            : null,
        streamId: json['stream_id'] as int?,
      );
}

class StoryViewer {
  final int userId;
  final String username;
  final String fullName;
  final String? profileImageThumbUrl;
  final DateTime viewedAt;

  StoryViewer({
    required this.userId,
    required this.username,
    required this.fullName,
    this.profileImageThumbUrl,
    required this.viewedAt,
  });

  factory StoryViewer.fromJson(Map<String, dynamic> json) => StoryViewer(
        userId: json['user_id'] as int,
        username: json['username'] as String,
        fullName: json['full_name'] as String,
        profileImageThumbUrl: json['profile_image_thumb_url'] as String?,
        viewedAt: DateTime.parse(json['viewed_at'] as String),
      );
}

class UserStoryGroup {
  final StoryAuthor user;

  /// Hybrid öğe listesi: önce videolar (created_at ASC), sonunda live_redirect (varsa).
  final List<StoryItem> items;
  final DateTime latestActivityAt;

  UserStoryGroup({
    required this.user,
    required this.items,
    required this.latestActivityAt,
  });

  factory UserStoryGroup.fromJson(Map<String, dynamic> json) => UserStoryGroup(
        user: StoryAuthor.fromJson(json['user'] as Map<String, dynamic>),
        items: (json['items'] as List)
            .map((s) => StoryItem.fromJson(s as Map<String, dynamic>))
            .toList(),
        latestActivityAt:
            DateTime.parse(json['latest_activity_at'] as String),
      );
}
