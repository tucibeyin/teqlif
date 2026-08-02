import 'package:flutter/foundation.dart';
import '../../services/storage_service.dart';
import '../../core/app_exception.dart';
import '../../models/call_participant.dart';
import '../repository/call_repository.dart';
import '../state/call_state.dart';
import '../state/call_status.dart';
import '../state/end_reason.dart';

void _log(String msg) {
  debugPrint('[GROUP_CALL][${DateTime.now().toIso8601String()}] $msg');
}

/// Grup arama aksiyonları ve WS event handler'larını yönetir.
/// D-9: Grup arama kendi domain'i; CallService sadece delegate eder.
class GroupCallManager {
  GroupCallManager({
    required CallRepository repository,
    required CallState Function() getState,
    required void Function(CallState) setState,
    required Future<void> Function({required CallStatus status, EndReason? endReason}) hangUpLocally,
    required Future<void> Function({required String livekitUrl, required String token}) joinRoom,
    required void Function() onAudioSessionActivated,
  })  : _repository = repository,
        _getState = getState,
        _setState = setState,
        _hangUpLocally = hangUpLocally,
        _joinRoom = joinRoom,
        _onAudioSessionActivated = onAudioSessionActivated;

  final CallRepository _repository;
  final CallState Function() _getState;
  final void Function(CallState) _setState;
  final Future<void> Function({required CallStatus status, EndReason? endReason}) _hangUpLocally;
  final Future<void> Function({required String livekitUrl, required String token}) _joinRoom;
  final void Function() _onAudioSessionActivated;

  // ── WS Event Handlers ─────────────────────────────────────────────────────

  void onGroupInviteReceived(Map<String, dynamic> data) {
    _log('onGroupInviteReceived | data=${data.keys.toList()}');
    try {
      final invite = GroupInvite.fromJson(data);
      _setState(_getState().copyWith(pendingGroupInvite: () => invite));
      _log('onGroupInviteReceived: pendingGroupInvite set | callId=${invite.callId} inviter=${invite.inviterUsername}');
    } catch (e) {
      _log('onGroupInviteReceived PARSE ERROR | $e');
    }
  }

  void onParticipantJoined(Map<String, dynamic> data) {
    final userId = data['user_id'] as int?;
    final username = data['username'] as String? ?? '';
    final avatar = data['avatar'] as String?;
    _log('onParticipantJoined | userId=$userId username=$username');
    if (userId == null) return;

    final existing = _getState().participants;
    if (existing.any((p) => p.userId == userId)) return;

    final updated = [
      ...existing,
      CallParticipant(
        userId: userId,
        username: username,
        avatar: avatar,
        role: 'guest',
        status: 'joined',
      ),
    ];
    _setState(_getState().copyWith(participants: updated));
  }

  void onParticipantLeft(Map<String, dynamic> data) {
    final userId = data['user_id'] as int?;
    _log('onParticipantLeft | userId=$userId');
    if (userId == null) return;
    final updated = _getState().participants
        .where((p) => p.userId != userId)
        .toList();
    _setState(_getState().copyWith(participants: updated));
  }

  void onParticipantRemoved(Map<String, dynamic> data) {
    final userId = data['user_id'] as int?;
    final selfRemoved = data['self_removed'] as bool? ?? false;
    _log('onParticipantRemoved | userId=$userId selfRemoved=$selfRemoved');

    if (selfRemoved) {
      _log('onParticipantRemoved: self → hangUpLocally(ended)');
      _hangUpLocally(status: CallStatus.ended);
      return;
    }

    if (userId != null) {
      final updated = _getState().participants
          .where((p) => p.userId != userId)
          .toList();
      _setState(_getState().copyWith(participants: updated));
    }
  }

  void onParticipantRejected(Map<String, dynamic> data) {
    final userId = data['user_id'] as int?;
    final username = data['username'] as String? ?? '?';
    _log('onParticipantRejected | userId=$userId username=$username');
    // Toast is shown by UI layer listening to WS stream directly
  }

  void onParticipantTimeout(Map<String, dynamic> data) {
    final userId = data['user_id'] as int?;
    final username = data['username'] as String? ?? '?';
    _log('onParticipantTimeout | userId=$userId username=$username');
    // Toast is shown by UI layer listening to WS stream directly
  }

  // ── Aksiyonlar ────────────────────────────────────────────────────────────

  Future<void> inviteToCall(int inviteeId) async {
    final callId = _getState().callId;
    if (callId == null) {
      _log('inviteToCall: SKIPPED | callId=null');
      return;
    }
    _log('inviteToCall | callId=$callId inviteeId=$inviteeId');
    try {
      await _repository.inviteParticipant(callId, inviteeId);
      _log('inviteToCall OK | callId=$callId inviteeId=$inviteeId');
    } catch (e) {
      _log('inviteToCall ERROR | $e');
      rethrow;
    }
  }

  Future<void> acceptGroupInvite() async {
    final invite = _getState().pendingGroupInvite;
    if (invite == null) {
      _log('acceptGroupInvite: SKIPPED | no pending invite');
      return;
    }
    _log('acceptGroupInvite | callId=${invite.callId} participantId=${invite.participantId}');
    try {
      final myId = await StorageService.getCurrentUserId();
      if (myId == null) throw AppException('No user id', code: 'NO_USER', statusCode: 401);

      // FIX 1: connecting + callId ÖNCE set et — _joinRoom içi rol tespiti
      // callStatusAtEntry == connecting → isCalleeRole=true → audio session + mic açılır.
      _setState(_getState().copyWith(
        pendingGroupInvite: () => null,
        status: CallStatus.connecting,
        callId: invite.callId,
        roomName: invite.roomName,
        isGroupGuest: true,
      ));
      // FIX 2: Group invite has no CallKit incoming call → simulate audioSessionActivated
      // so waitForCallkitAudio() returns immediately in _joinRoom callee path.
      _onAudioSessionActivated();

      await _joinRoom(livekitUrl: invite.livekitUrl, token: invite.livekitToken);

      final participants = await _repository.acceptGroupParticipant(invite.callId, myId);
      _setState(_getState().copyWith(participants: participants));

      _log('acceptGroupInvite OK | callId=${invite.callId} participants=${participants.length}');
    } catch (e) {
      _log('acceptGroupInvite ERROR | $e');
      rethrow;
    }
  }

  Future<void> rejectGroupInvite() async {
    final invite = _getState().pendingGroupInvite;
    if (invite == null) {
      _log('rejectGroupInvite: SKIPPED | no pending invite');
      return;
    }
    _log('rejectGroupInvite | callId=${invite.callId}');
    try {
      final myId = await StorageService.getCurrentUserId();
      if (myId == null) return;
      await _repository.rejectGroupParticipant(invite.callId, myId);
      _setState(_getState().copyWith(pendingGroupInvite: () => null));
      _log('rejectGroupInvite OK | callId=${invite.callId}');
    } catch (e) {
      _log('rejectGroupInvite ERROR (non-fatal) | $e');
    }
  }

  Future<void> leaveGroupCall() async {
    final callId = _getState().callId;
    final myId = await StorageService.getCurrentUserId();
    _log('leaveGroupCall | callId=$callId myId=$myId');
    if (callId != null && myId != null) {
      _repository.leaveGroupCall(callId, myId);
    }
    await _hangUpLocally(status: CallStatus.ended);
  }

  Future<void> removeParticipant(int userId) async {
    final callId = _getState().callId;
    if (callId == null) return;
    _log('removeParticipant | callId=$callId userId=$userId');
    try {
      await _repository.removeParticipant(callId, userId);
      _log('removeParticipant OK | callId=$callId userId=$userId');
    } catch (e) {
      _log('removeParticipant ERROR | $e');
      rethrow;
    }
  }
}
