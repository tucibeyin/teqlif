class ChatMessage {
  final String id;
  final String username;
  final String? profileImageUrl;
  final String content;
  final DateTime createdAt;
  final bool isSystem;
  final bool isMod;
  final bool isHost;
  final bool isAuctionResult;
  final String? announcementType;
  final Map<String, dynamic>? announcementPayload;

  bool get isAnnouncement => announcementType != null;

  const ChatMessage({
    required this.id,
    required this.username,
    this.profileImageUrl,
    required this.content,
    required this.createdAt,
    this.isSystem = false,
    this.isMod = false,
    this.isHost = false,
    this.isAuctionResult = false,
    this.announcementType,
    this.announcementPayload,
  });

  ChatMessage copyWith({Map<String, dynamic>? announcementPayload}) {
    return ChatMessage(
      id: id,
      username: username,
      profileImageUrl: profileImageUrl,
      content: content,
      createdAt: createdAt,
      isSystem: isSystem,
      isMod: isMod,
      isHost: isHost,
      isAuctionResult: isAuctionResult,
      announcementType: announcementType,
      announcementPayload: announcementPayload ?? this.announcementPayload,
    );
  }

  factory ChatMessage.fromJson(Map<String, dynamic> j) {
    if (j['type'] == 'announcement') {
      return ChatMessage(
        id: j['id'] as String? ?? '',
        username: '',
        content: '',
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
        announcementType: j['announcement_type'] as String?,
        announcementPayload: j['payload'] != null
            ? Map<String, dynamic>.from(j['payload'] as Map)
            : null,
      );
    }
    return ChatMessage(
      id: j['id'] as String? ?? '',
      username: j['username'] as String? ?? 'Anonim',
      profileImageUrl: j['profile_image_url'] as String?,
      content: j['content'] as String? ?? '',
      createdAt: DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
      isMod: j['is_mod'] as bool? ?? false,
      isHost: j['is_host'] as bool? ?? false,
      isAuctionResult: j['is_auction_result'] as bool? ?? false,
    );
  }
}
