class StreamHost {
  final int id;
  final String username;

  StreamHost({required this.id, required this.username});

  factory StreamHost.fromJson(Map<String, dynamic> json) => StreamHost(
        id: json['id'],
        username: json['username'],
      );
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

  factory StreamOut.fromJson(Map<String, dynamic> json) => StreamOut(
        id: json['id'],
        roomName: json['room_name'],
        title: json['title'],
        category: json['category'] ?? 'diger',
        viewerCount: json['viewer_count'] ?? 0,
        host: StreamHost.fromJson(json['host']),
        thumbnailUrl: json['thumbnail_url'] as String?,
      );
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

  JoinTokenOut({
    required this.streamId,
    required this.roomName,
    required this.livekitUrl,
    required this.token,
    required this.title,
    required this.hostUsername,
  });

  factory JoinTokenOut.fromJson(Map<String, dynamic> json) => JoinTokenOut(
        streamId: json['stream_id'],
        roomName: json['room_name'],
        livekitUrl: json['livekit_url'],
        token: json['token'],
        title: json['title'],
        hostUsername: json['host_username'],
      );
}
