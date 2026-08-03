class CallHistoryItem {
  final int callId;
  final String status;
  final String role;
  final int? durationSeconds;
  final DateTime? startedAt;
  final int? otherUserId;
  final String? otherUsername;
  final String? otherAvatar;

  const CallHistoryItem({
    required this.callId,
    required this.status,
    required this.role,
    this.durationSeconds,
    this.startedAt,
    this.otherUserId,
    this.otherUsername,
    this.otherAvatar,
  });

  factory CallHistoryItem.fromMap(Map<String, dynamic> m) {
    final other = m['other_user'] as Map<String, dynamic>?;
    return CallHistoryItem(
      callId: m['call_id'] as int,
      status: m['status'] as String,
      role: m['role'] as String,
      durationSeconds: m['duration_seconds'] as int?,
      startedAt: m['started_at'] != null
          ? DateTime.tryParse(m['started_at'] as String)
          : null,
      otherUserId: other?['id'] as int?,
      otherUsername: other?['username'] as String?,
      otherAvatar: other?['avatar'] as String?,
    );
  }

  bool get isMissed =>
      status == 'missed' || (status == 'ended' && role == 'callee' && (durationSeconds ?? 0) == 0);
  bool get isOutgoing => role == 'caller';
}
