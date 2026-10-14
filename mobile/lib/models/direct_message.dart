import 'dart:typed_data';

enum MessageContentType {
  text,
  image,
  video,
  voice,
  file;

  static MessageContentType fromString(String? s) => switch (s) {
    'image' => image,
    'video' => video,
    'voice' => voice,
    'file'  => file,
    _       => text,
  };
}

class DirectMessage {
  final int id;
  final int senderId;
  final int receiverId;
  final String? content;
  final MessageContentType contentType;
  final String? mediaUrl;
  final String? thumbnailUrl;
  final String? fileName;
  final int? fileSizeBytes;
  final int? durationSecs;
  final bool isRead;
  final DateTime createdAt;
  final bool isPending;
  final bool isFailed;
  final String? errorMessage;
  final String? localId;
  final Uint8List? localBytes; // optimistik önizleme için (upload sırasında)

  const DirectMessage({
    required this.id,
    required this.senderId,
    required this.receiverId,
    this.content,
    this.contentType = MessageContentType.text,
    this.mediaUrl,
    this.thumbnailUrl,
    this.fileName,
    this.fileSizeBytes,
    this.durationSecs,
    this.isRead = false,
    required this.createdAt,
    this.isPending = false,
    this.isFailed = false,
    this.errorMessage,
    this.localId,
    this.localBytes,
  });

  factory DirectMessage.fromJson(Map<String, dynamic> j) => DirectMessage(
    id: j['id'] as int,
    senderId: j['sender_id'] as int,
    receiverId: j['receiver_id'] as int,
    content: j['content'] as String?,
    contentType: MessageContentType.fromString(j['content_type'] as String?),
    mediaUrl: j['media_url'] as String?,
    thumbnailUrl: j['thumbnail_url'] as String?,
    fileName: j['file_name'] as String?,
    fileSizeBytes: j['file_size_bytes'] as int?,
    durationSecs: j['duration_secs'] as int?,
    isRead: j['is_read'] as bool? ?? false,
    createdAt: DateTime.parse(j['created_at'] as String),
    isPending: j['_pending'] as bool? ?? false,
    isFailed: j['_failed'] as bool? ?? false,
    errorMessage: j['_error'] as String?,
    localId: j['_local_id'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'sender_id': senderId,
    'receiver_id': receiverId,
    if (content != null) 'content': content,
    'content_type': contentType.name,
    if (mediaUrl != null) 'media_url': mediaUrl,
    if (thumbnailUrl != null) 'thumbnail_url': thumbnailUrl,
    if (fileName != null) 'file_name': fileName,
    if (fileSizeBytes != null) 'file_size_bytes': fileSizeBytes,
    if (durationSecs != null) 'duration_secs': durationSecs,
    'is_read': isRead,
    'created_at': createdAt.toUtc().toIso8601String(),
    if (isPending) '_pending': true,
    if (isFailed) '_failed': true,
    if (errorMessage != null) '_error': errorMessage,
    if (localId != null) '_local_id': localId,
    if (localBytes != null) '_bytes': localBytes,
  };

  DirectMessage copyWith({
    bool? isRead,
    bool? isPending,
    bool? isFailed,
    String? errorMessage,
    String? localId,
    Uint8List? localBytes,
  }) => DirectMessage(
    id: id,
    senderId: senderId,
    receiverId: receiverId,
    content: content,
    contentType: contentType,
    mediaUrl: mediaUrl,
    thumbnailUrl: thumbnailUrl,
    fileName: fileName,
    fileSizeBytes: fileSizeBytes,
    durationSecs: durationSecs,
    createdAt: createdAt,
    isRead: isRead ?? this.isRead,
    isPending: isPending ?? this.isPending,
    isFailed: isFailed ?? this.isFailed,
    errorMessage: errorMessage ?? this.errorMessage,
    localId: localId ?? this.localId,
    localBytes: localBytes ?? this.localBytes,
  );
}
