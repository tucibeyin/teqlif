class MessageSenderModel {
  final String id;
  final String name;
  const MessageSenderModel({required this.id, required this.name});
  factory MessageSenderModel.fromJson(Map<String, dynamic>? json) =>
      MessageSenderModel(
          id: json?['id'] as String? ?? '',
          name: json?['name'] as String? ?? '');
}

class MessageModel {
  final String id;
  final String content;
  final bool isRead;
  final DateTime createdAt;
  final String senderId;
  final String conversationId;
  final MessageSenderModel? sender;

  const MessageModel({
    required this.id,
    required this.content,
    required this.isRead,
    required this.createdAt,
    required this.senderId,
    required this.conversationId,
    this.sender,
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) => MessageModel(
        id: json['id'] as String,
        content: json['content'] as String,
        isRead: json['isRead'] as bool? ?? false,
        createdAt: DateTime.parse(json['createdAt'] as String),
        senderId: json['senderId'] as String? ?? '',
        conversationId: json['conversationId'] as String? ?? '',
        sender: json['sender'] != null
            ? MessageSenderModel.fromJson(
                json['sender'] as Map<String, dynamic>)
            : null,
      );
}

class ConversationUserModel {
  final String id;
  final String name;
  final String? avatar;
  const ConversationUserModel(
      {required this.id, required this.name, this.avatar});
  factory ConversationUserModel.fromJson(Map<String, dynamic>? json) =>
      ConversationUserModel(
          id: json?['id'] as String? ?? '',
          name: json?['name'] as String? ?? '',
          avatar: json?['avatar'] as String?);
}

class ConversationModel {
  final String id;
  final String user1Id;
  final String user2Id;
  final String? adId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final ConversationUserModel? user1;
  final ConversationUserModel? user2;
  final MessageModel? lastMessage;
  final int unreadCount;

  const ConversationModel({
    required this.id,
    required this.user1Id,
    required this.user2Id,
    this.adId,
    required this.createdAt,
    required this.updatedAt,
    this.user1,
    this.user2,
    this.lastMessage,
    this.unreadCount = 0,
  });

  ConversationUserModel? otherUser(String myId) =>
      user1Id == myId ? user2 : user1;

  factory ConversationModel.fromJson(Map<String, dynamic> json) =>
      ConversationModel(
        id: json['id'] as String,
        user1Id: json['user1Id'] as String? ?? '',
        user2Id: json['user2Id'] as String? ?? '',
        adId: json['adId'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        user1: json['user1'] != null
            ? ConversationUserModel.fromJson(
                json['user1'] as Map<String, dynamic>)
            : null,
        user2: json['user2'] != null
            ? ConversationUserModel.fromJson(
                json['user2'] as Map<String, dynamic>)
            : null,
        lastMessage: json['lastMessage'] != null
            ? MessageModel.fromJson(
                json['lastMessage'] as Map<String, dynamic>)
            : null,
        unreadCount: json['unreadCount'] as int? ?? 0,
      );
}
