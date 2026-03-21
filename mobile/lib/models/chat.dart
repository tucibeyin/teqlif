class ChatMessage {
  final String id;
  final String username;
  final String content;
  final DateTime createdAt;
  final bool isSystem;

  const ChatMessage({
    required this.id,
    required this.username,
    required this.content,
    required this.createdAt,
    this.isSystem = false,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'] as String? ?? '',
        username: j['username'] as String? ?? 'Anonim',
        content: j['content'] as String? ?? '',
        createdAt:
            DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
      );
}
