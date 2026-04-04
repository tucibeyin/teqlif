class StreamHost {
  final int id;
  final String username;

  StreamHost({required this.id, required this.username});

  factory StreamHost.fromJson(Map<String, dynamic> json) => StreamHost(
        id: json['id'],
        username: json['username'],
      );

  Map<String, dynamic> toJson() => {'id': id, 'username': username};
}

class StreamOut {
  final int id;
  final String roomName;
  final String title;
  final String category;
  final int viewerCount;
  final StreamHost host;
  final String? thumbnailUrl;

  StreamOut({
    required this.id,
    required this.roomName,
    required this.title,
    required this.category,
    required this.viewerCount,
    required this.host,
    this.thumbnailUrl,
  });

  /// JoinTokenOut'tan minimal bir StreamOut stub'ı oluşturur.
  /// Yalnızca id, roomName, title, hostUsername alanları doludur.
  /// SwipeLiveScreen.single() tarafından kullanılır.
  factory StreamOut.fromJoinToken(JoinTokenOut t) => StreamOut(
        id: t.streamId,
        roomName: t.roomName,
        title: t.title,
        category: '',
        viewerCount: 0,
        host: StreamHost(id: 0, username: t.hostUsername),
      );

  factory StreamOut.fromJson(Map<String, dynamic> json) => StreamOut(
        id: json['id'],
        roomName: json['room_name'],
        title: json['title'],
        category: json['category'] ?? 'diger',
        viewerCount: json['viewer_count'] ?? 0,
        host: StreamHost.fromJson(json['host']),
        thumbnailUrl: json['thumbnail_url'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'room_name': roomName,
        'title': title,
        'category': category,
        'viewer_count': viewerCount,
        'host': host.toJson(),
        'thumbnail_url': thumbnailUrl,
      };
}

class StreamTokenOut {
  final int streamId;
  final String roomName;
  final String livekitUrl;
  final String token;

  StreamTokenOut({
    required this.streamId,
    required this.roomName,
    required this.livekitUrl,
    required this.token,
  });

  factory StreamTokenOut.fromJson(Map<String, dynamic> json) => StreamTokenOut(
        streamId: json['stream_id'],
        roomName: json['room_name'],
        livekitUrl: json['livekit_url'],
        token: json['token'],
      );
}

class JoinTokenOut {
  final int streamId;
  final String roomName;
  final String livekitUrl;
  final String token;
  final String title;
  final String hostUsername;
  final String hostLivekitIdentity;  // LiveKit identity = str(host.id)

  JoinTokenOut({
    required this.streamId,
    required this.roomName,
    required this.livekitUrl,
    required this.token,
    required this.title,
    required this.hostUsername,
    required this.hostLivekitIdentity,
  });

  factory JoinTokenOut.fromJson(Map<String, dynamic> json) => JoinTokenOut(
        streamId: json['stream_id'],
        roomName: json['room_name'],
        livekitUrl: json['livekit_url'],
        token: json['token'],
        title: json['title'],
        hostUsername: json['host_username'],
        hostLivekitIdentity: json['host_livekit_identity'],
      );
}
