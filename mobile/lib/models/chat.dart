class ChatMessage {
  final String id;
  final String username;
  final String? profileImageUrl;
  final String content;
  final DateTime createdAt;
  final bool isSystem;

  const ChatMessage({
    required this.id,
    required this.username,
    this.profileImageUrl,
    required this.content,
    required this.createdAt,
    this.isSystem = false,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'] as String? ?? '',
        username: j['username'] as String? ?? 'Anonim',
        profileImageUrl: j['profile_image_url'] as String?,
        content: j['content'] as String? ?? '',
        createdAt:
            DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
      );
}
