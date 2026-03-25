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
  });

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'] as String? ?? '',
        username: j['username'] as String? ?? 'Anonim',
        profileImageUrl: j['profile_image_url'] as String?,
        content: j['content'] as String? ?? '',
        createdAt:
            DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
        isMod: j['is_mod'] as bool? ?? false,
        isHost: j['is_host'] as bool? ?? false,
        isAuctionResult: j['is_auction_result'] as bool? ?? false,
      );
}
