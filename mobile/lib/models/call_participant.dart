class CallParticipant {
  final int userId;
  final String username;
  final String? avatar;
  final String role;   // initiator | callee | guest
  final String status; // invited | ringing | joined | left | rejected | timeout | removed

  const CallParticipant({
    required this.userId,
    required this.username,
    this.avatar,
    required this.role,
    required this.status,
  });

  factory CallParticipant.fromJson(Map<String, dynamic> json) {
    return CallParticipant(
      userId: json['user_id'] as int,
      username: json['username'] as String,
      avatar: json['avatar'] as String?,
      role: json['role'] as String,
      status: json['status'] as String,
    );
  }

  CallParticipant copyWith({String? status}) {
    return CallParticipant(
      userId: userId,
      username: username,
      avatar: avatar,
      role: role,
      status: status ?? this.status,
    );
  }
}


class GroupInvite {
  final int callId;
  final String roomName;
  final String livekitToken;
  final String livekitUrl;
  final int inviterId;
  final String inviterUsername;
  final String? inviterAvatar;
  final int participantId;

  const GroupInvite({
    required this.callId,
    required this.roomName,
    required this.livekitToken,
    required this.livekitUrl,
    required this.inviterId,
    required this.inviterUsername,
    this.inviterAvatar,
    required this.participantId,
  });

  factory GroupInvite.fromJson(Map<String, dynamic> json) {
    return GroupInvite(
      callId: json['call_id'] as int,
      roomName: json['room_name'] as String,
      livekitToken: json['livekit_token'] as String,
      livekitUrl: json['livekit_url'] as String,
      inviterId: json['inviter_id'] as int,
      inviterUsername: json['inviter_username'] as String,
      inviterAvatar: json['inviter_avatar'] as String?,
      participantId: json['participant_id'] as int,
    );
  }
}
