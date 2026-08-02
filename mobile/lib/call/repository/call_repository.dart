import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../config/api.dart';
import '../../core/app_exception.dart';
import '../../services/storage_service.dart';
import '../../models/call_participant.dart';

// ── Result types ──────────────────────────────────────────────────────────────

class CallStartResult {
  final int callId;
  final String roomName;
  final String livekitUrl;
  final String token;

  const CallStartResult({
    required this.callId,
    required this.roomName,
    required this.livekitUrl,
    required this.token,
  });
}

class CallAcceptResult {
  final DateTime? acceptedAt;
  final String? token;
  final String? livekitUrl;

  const CallAcceptResult({this.acceptedAt, this.token, this.livekitUrl});
}

class ActiveCallResult {
  final int callId;
  final String status;
  final String role;
  final String roomName;
  final String livekitUrl;
  final String token;
  final Map<String, dynamic> otherUser;
  final DateTime? acceptedAt;

  const ActiveCallResult({
    required this.callId,
    required this.status,
    required this.role,
    required this.roomName,
    required this.livekitUrl,
    required this.token,
    required this.otherUser,
    this.acceptedAt,
  });
}

class CalleeTokenResult {
  final String? token;
  final String? livekitUrl;
  final String? roomName;

  const CalleeTokenResult({this.token, this.livekitUrl, this.roomName});
}

// ── Repository ────────────────────────────────────────────────────────────────

class CallRepository {
  void _log(String phase, String msg) =>
      debugPrint('[CALL_REPO][${DateTime.now().toIso8601String()}][$phase] $msg');

  Future<Map<String, String>> _authHeaders() async {
    final token = await StorageService.getToken();
    if (token == null) {
      throw AppException('Oturum bilgisi bulunamadı', code: 'NO_TOKEN', statusCode: 401);
    }
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Future<Map<String, dynamic>> _post(String path, [Map<String, dynamic>? body]) =>
      apiCall(() async => http.post(
            Uri.parse('$kBaseUrl$path'),
            headers: await _authHeaders(),
            body: body != null ? jsonEncode(body) : null,
          ));

  Future<Map<String, dynamic>> _get(String path) =>
      apiCall(() async => http.get(
            Uri.parse('$kBaseUrl$path'),
            headers: await _authHeaders(),
          ));

  // ── startCall ─────────────────────────────────────────────────────────────

  Future<CallStartResult> startCall(int calleeId) async {
    _log('API', '→ POST /calls/start | calleeId=$calleeId');
    final data = await _post('/calls/start', {'callee_id': calleeId});
    final result = CallStartResult(
      callId: data['call_id'] as int,
      roomName: data['room_name'] as String,
      livekitUrl: data['livekit_url'] as String,
      token: data['token'] as String,
    );
    _log('API', '← POST /calls/start | callId=${result.callId} roomName=${result.roomName}');
    return result;
  }

  // ── acceptCall ────────────────────────────────────────────────────────────
  // shouldAbort: caller passes () => status != connecting to abort mid-retry.
  // Throws AppException(code:'ABORTED') if aborted; rethrows HTTP errors after
  // 4 attempts.

  Future<CallAcceptResult> acceptCall(
    int callId, {
    required bool Function() shouldAbort,
  }) async {
    _log('API', '→ POST /calls/$callId/accept (retry max=4)');
    Map<String, dynamic>? data;
    int retryCount = 0;
    while (retryCount < 4) {
      if (shouldAbort()) {
        _log('API', '← POST /calls/$callId/accept ABORTED | attempt=${retryCount + 1}');
        throw AppException('acceptCall aborted', code: 'ABORTED', statusCode: 0);
      }
      try {
        _log('API', '→ POST /calls/$callId/accept attempt=${retryCount + 1}');
        data = await _post('/calls/$callId/accept');
        _log('API', '← POST /calls/$callId/accept SUCCESS | acceptedAt=${data['accepted_at']} tokenLen=${(data['token'] as String?)?.length}');
        break;
      } catch (e) {
        retryCount++;
        _log('API', '← POST /calls/$callId/accept RETRY | attempt=$retryCount error=$e');
        if (retryCount >= 4) rethrow;
        await Future.delayed(Duration(milliseconds: 500 * retryCount));
      }
    }
    if (data == null) throw Exception('acceptCall: data is null after retries');
    return CallAcceptResult(
      acceptedAt: data['accepted_at'] != null
          ? DateTime.tryParse(data['accepted_at'] as String)
          : null,
      token: data['token'] as String?,
      livekitUrl: data['livekit_url'] as String?,
    );
  }

  // ── rejectCall ────────────────────────────────────────────────────────────

  void rejectCall(int callId) {
    _log('API', '→ POST /calls/$callId/reject (fire-and-forget)');
    _post('/calls/$callId/reject').then((_) {
      _log('API', '← POST /calls/$callId/reject OK');
    }).catchError((Object e) {
      _log('API', '← POST /calls/$callId/reject FAILED (non-fatal) | $e');
    });
  }

  // ── endCall ───────────────────────────────────────────────────────────────

  void endCall(int callId) {
    _log('API', '→ POST /calls/$callId/end (fire-and-forget, 1 retry)');
    _post('/calls/$callId/end').then((_) {
      _log('API', '← POST /calls/$callId/end OK');
    }).catchError((Object e) {
      _log('API', '← POST /calls/$callId/end FAILED → retry | $e');
      Future.delayed(const Duration(milliseconds: 500)).then((_) {
        _post('/calls/$callId/end').then((_) {
          _log('API', '← POST /calls/$callId/end retry OK');
        }).catchError((Object e2) {
          _log('API', '← POST /calls/$callId/end retry FAILED | $e2');
        });
      });
    });
  }

  // ── reportMissed ──────────────────────────────────────────────────────────

  void reportMissed(int callId) {
    _log('API', '→ POST /calls/$callId/missed (fire-and-forget)');
    _post('/calls/$callId/missed').then((_) {
      _log('API', '← POST /calls/$callId/missed OK');
    }).catchError((Object e) {
      _log('API', '← POST /calls/$callId/missed FAILED (non-fatal) | $e');
    });
  }

  // ── reportConnected ───────────────────────────────────────────────────────

  void reportConnected(int callId) {
    _log('API', '→ POST /calls/$callId/connected (fire-and-forget)');
    _post('/calls/$callId/connected').then((_) {
      _log('API', '← POST /calls/$callId/connected OK');
    }).catchError((Object e) {
      _log('API', '← POST /calls/$callId/connected FAILED (non-fatal) | $e');
    });
  }

  // ── getActiveCall ─────────────────────────────────────────────────────────

  Future<ActiveCallResult?> getActiveCall() async {
    _log('API', '→ GET /calls/active');
    final data = await _get('/calls/active');
    final activeCall = data['active_call'];
    if (activeCall == null) {
      _log('API', '← GET /calls/active | no active call');
      return null;
    }
    final otherUser = activeCall['other_user'] as Map<String, dynamic>? ?? {};
    final acceptedAtStr = activeCall['accepted_at'] as String?;
    final result = ActiveCallResult(
      callId: activeCall['call_id'] as int,
      status: activeCall['status'] as String,
      role: activeCall['role'] as String,
      roomName: activeCall['room_name'] as String,
      livekitUrl: activeCall['livekit_url'] as String,
      token: activeCall['token'] as String,
      otherUser: otherUser,
      acceptedAt: acceptedAtStr != null ? DateTime.tryParse(acceptedAtStr) : null,
    );
    _log('API', '← GET /calls/active | callId=${result.callId} status=${result.status} role=${result.role}');
    return result;
  }

  // ── getCallStatus ─────────────────────────────────────────────────────────

  Future<String> getCallStatus(int callId) async {
    _log('API', '→ GET /calls/$callId/status');
    final data = await _get('/calls/$callId/status');
    final status = data['status'] as String;
    _log('API', '← GET /calls/$callId/status | status=$status');
    return status;
  }

  // ── getCalleeToken ────────────────────────────────────────────────────────

  Future<CalleeTokenResult> getCalleeToken(int callId) async {
    _log('API', '→ GET /calls/$callId/callee-token');
    final data = await _get('/calls/$callId/callee-token');
    final result = CalleeTokenResult(
      token: data['token'] as String?,
      livekitUrl: data['livekit_url'] as String?,
      roomName: data['room_name'] as String?,
    );
    _log('API', '← GET /calls/$callId/callee-token | tokenLen=${result.token?.length} urlOk=${result.livekitUrl != null}');
    return result;
  }

  // ── Group call endpoints ──────────────────────────────────────────────────

  Future<void> inviteParticipant(int callId, int inviteeId) async {
    _log('API', '→ POST /calls/$callId/invite | inviteeId=$inviteeId');
    await _post('/calls/$callId/invite', {'invitee_id': inviteeId});
    _log('API', '← POST /calls/$callId/invite OK');
  }

  Future<List<CallParticipant>> acceptGroupParticipant(int callId, int participantId) async {
    _log('API', '→ POST /calls/$callId/participants/$participantId/accept');
    final data = await _post('/calls/$callId/participants/$participantId/accept');
    final raw = data['participants'] as List<dynamic>? ?? [];
    final participants = raw
        .map((p) => CallParticipant.fromJson(p as Map<String, dynamic>))
        .toList();
    _log('API', '← POST /calls/$callId/participants/$participantId/accept | participants=${participants.length}');
    return participants;
  }

  Future<void> rejectGroupParticipant(int callId, int participantId) async {
    _log('API', '→ POST /calls/$callId/participants/$participantId/reject');
    await _post('/calls/$callId/participants/$participantId/reject');
    _log('API', '← POST /calls/$callId/participants/$participantId/reject OK');
  }

  void leaveGroupCall(int callId, int participantId) {
    _log('API', '→ POST /calls/$callId/participants/$participantId/leave (fire-and-forget)');
    _post('/calls/$callId/participants/$participantId/leave').then((_) {
      _log('API', '← POST /calls/$callId/participants/$participantId/leave OK');
    }).catchError((Object e) {
      _log('API', '← POST /calls/$callId/participants/$participantId/leave FAILED (non-fatal) | $e');
    });
  }

  Future<void> removeParticipant(int callId, int userId) async {
    _log('API', '→ POST /calls/$callId/participants/$userId/remove | userId=$userId');
    await _post('/calls/$callId/participants/$userId/remove');
    _log('API', '← POST /calls/$callId/participants/$userId/remove OK');
  }
}
