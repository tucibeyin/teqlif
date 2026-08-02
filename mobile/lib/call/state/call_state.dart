import 'call_status.dart';
import 'end_reason.dart';
import '../../models/call_participant.dart';

class CallState {
  final CallStatus status;
  final EndReason? endReason;
  final int? callId;
  final String? roomName;
  final String? livekitUrl;
  final String? token;
  final String? calleeToken;
  final String? otherUsername;
  final String? otherAvatar;
  final int? otherUserId;
  final DateTime? acceptedAt;
  final Duration elapsed;
  final bool isMuted;
  final bool isSpeaker;
  final bool permPermanentlyDenied;
  final bool isPoorConnection;
  final bool localVideoEnabled;
  final bool remoteVideoEnabled;
  final List<CallParticipant> participants;
  final GroupInvite? pendingGroupInvite;
  // true: grup davetine katılan misafir (host değil).
  // Bu flag endCall() yerine leaveGroupCall() çağrısını tetikler.
  final bool isGroupGuest;

  const CallState({
    this.status = CallStatus.idle,
    this.endReason,
    this.callId,
    this.roomName,
    this.livekitUrl,
    this.token,
    this.calleeToken,
    this.otherUsername,
    this.otherAvatar,
    this.otherUserId,
    this.acceptedAt,
    this.elapsed = Duration.zero,
    this.isMuted = false,
    this.isSpeaker = false,
    this.permPermanentlyDenied = false,
    this.isPoorConnection = false,
    this.localVideoEnabled = false,
    this.remoteVideoEnabled = false,
    this.participants = const [],
    this.pendingGroupInvite,
    this.isGroupGuest = false,
  });

  CallState copyWith({
    CallStatus? status,
    EndReason? endReason,
    bool clearEndReason = false,
    int? callId,
    String? roomName,
    String? livekitUrl,
    String? token,
    String? calleeToken,
    String? otherUsername,
    String? otherAvatar,
    int? otherUserId,
    DateTime? acceptedAt,
    Duration? elapsed,
    bool? isMuted,
    bool? isSpeaker,
    bool? permPermanentlyDenied,
    bool? isPoorConnection,
    bool? localVideoEnabled,
    bool? remoteVideoEnabled,
    List<CallParticipant>? participants,
    GroupInvite? Function()? pendingGroupInvite,
    bool? isGroupGuest,
  }) {
    return CallState(
      status: status ?? this.status,
      endReason: clearEndReason ? null : (endReason ?? this.endReason),
      callId: callId ?? this.callId,
      roomName: roomName ?? this.roomName,
      livekitUrl: livekitUrl ?? this.livekitUrl,
      token: token ?? this.token,
      calleeToken: calleeToken ?? this.calleeToken,
      otherUsername: otherUsername ?? this.otherUsername,
      otherAvatar: otherAvatar ?? this.otherAvatar,
      otherUserId: otherUserId ?? this.otherUserId,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      elapsed: elapsed ?? this.elapsed,
      isMuted: isMuted ?? this.isMuted,
      isSpeaker: isSpeaker ?? this.isSpeaker,
      permPermanentlyDenied:
          permPermanentlyDenied ?? this.permPermanentlyDenied,
      isPoorConnection: isPoorConnection ?? this.isPoorConnection,
      localVideoEnabled: localVideoEnabled ?? this.localVideoEnabled,
      remoteVideoEnabled: remoteVideoEnabled ?? this.remoteVideoEnabled,
      participants: participants ?? this.participants,
      pendingGroupInvite: pendingGroupInvite != null
          ? pendingGroupInvite()
          : this.pendingGroupInvite,
      isGroupGuest: isGroupGuest ?? this.isGroupGuest,
    );
  }
}
