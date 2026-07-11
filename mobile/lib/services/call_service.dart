import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:audio_session/audio_session.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../config/api.dart';
import '../services/storage_service.dart';

enum CallStatus {
  idle,
  calling,      // outgoing — waiting for answer
  ringing,      // incoming — waiting for our action
  connecting,   // accepted — joining LiveKit room
  connected,    // in call
  ended,
  rejected,
  missed,
  noAnswer,
  permissionDenied,
}

class CallState {
  final CallStatus status;
  final int? callId;
  final String? roomName;
  final String? livekitUrl;
  final String? token;
  final String? otherUsername;
  final String? otherAvatar;
  final int? otherUserId;
  final Duration elapsed;
  final bool isMuted;
  final bool isSpeaker;

  const CallState({
    this.status = CallStatus.idle,
    this.callId,
    this.roomName,
    this.livekitUrl,
    this.token,
    this.otherUsername,
    this.otherAvatar,
    this.otherUserId,
    this.elapsed = Duration.zero,
    this.isMuted = false,
    this.isSpeaker = false,
  });

  CallState copyWith({
    CallStatus? status,
    int? callId,
    String? roomName,
    String? livekitUrl,
    String? token,
    String? otherUsername,
    String? otherAvatar,
    int? otherUserId,
    Duration? elapsed,
    bool? isMuted,
    bool? isSpeaker,
  }) => CallState(
    status: status ?? this.status,
    callId: callId ?? this.callId,
    roomName: roomName ?? this.roomName,
    livekitUrl: livekitUrl ?? this.livekitUrl,
    token: token ?? this.token,
    otherUsername: otherUsername ?? this.otherUsername,
    otherAvatar: otherAvatar ?? this.otherAvatar,
    otherUserId: otherUserId ?? this.otherUserId,
    elapsed: elapsed ?? this.elapsed,
    isMuted: isMuted ?? this.isMuted,
    isSpeaker: isSpeaker ?? this.isSpeaker,
  );
}

class CallService {
  CallService._();
  static final CallService instance = CallService._();

  final ValueNotifier<CallState> state = ValueNotifier(const CallState());

  Room? _room;
  Timer? _ringTimer;   // 30s no-answer timeout
  Timer? _elapsedTimer;

  // ── Helpers ──────────────────────────────────────────────────────────────

  Future<Map<String, String>> _authHeaders() async {
    final token = await StorageService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<Map<String, dynamic>> _post(String path, [Map<String, dynamic>? body]) async {
    final resp = await http.post(
      Uri.parse('$kBaseUrl$path'),
      headers: await _authHeaders(),
      body: body != null ? jsonEncode(body) : null,
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Call API error ${resp.statusCode}: ${resp.body}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  void _setState(CallState s) => state.value = s;

  // ── Outgoing Call ─────────────────────────────────────────────────────────

  Future<void> startCall({
    required int calleeId,
    required String calleeUsername,
    required String? calleeAvatar,
  }) async {
    final perm = await Permission.microphone.request();
    if (!perm.isGranted) {
      _setState(state.value.copyWith(status: CallStatus.permissionDenied));
      return;
    }

    _setState(CallState(
      status: CallStatus.calling,
      otherUserId: calleeId,
      otherUsername: calleeUsername,
      otherAvatar: calleeAvatar,
    ));

    try {
      final data = await _post('/calls/start', {'callee_id': calleeId});
      _setState(state.value.copyWith(
        callId: data['call_id'] as int,
        roomName: data['room_name'] as String,
        livekitUrl: data['livekit_url'] as String,
        token: data['token'] as String,
      ));
      _startRingTimer();
      await WakelockPlus.enable();
    } catch (e) {
      debugPrint('[CallService] startCall error: $e');
      _setState(state.value.copyWith(status: CallStatus.ended));
    }
  }

  void _startRingTimer() {
    _ringTimer?.cancel();
    _ringTimer = Timer(const Duration(seconds: 30), () async {
      if (state.value.status == CallStatus.calling) {
        final callId = state.value.callId;
        if (callId != null) {
          try { await _post('/calls/$callId/missed'); } catch (_) {}
        }
        _setState(state.value.copyWith(status: CallStatus.noAnswer));
        await Future.delayed(const Duration(seconds: 2));
        reset();
      }
    });
  }

  // ── Incoming Call (WS / FCM triggered) ────────────────────────────────────

  void onIncomingCall(Map<String, dynamic> data) {
    _setState(CallState(
      status: CallStatus.ringing,
      callId: data['call_id'] is int ? data['call_id'] : int.tryParse(data['call_id'].toString()),
      roomName: data['room_name'] as String?,
      livekitUrl: data['livekit_url'] as String?,
      otherUserId: data['caller_id'] is int ? data['caller_id'] : int.tryParse(data['caller_id'].toString()),
      otherUsername: data['caller_username'] as String?,
      otherAvatar: data['caller_avatar'] as String?,
    ));
  }

  Future<void> acceptCall() async {
    final callId = state.value.callId;
    if (callId == null) return;

    final perm = await Permission.microphone.request();
    if (!perm.isGranted) {
      _setState(state.value.copyWith(status: CallStatus.permissionDenied));
      return;
    }

    _setState(state.value.copyWith(status: CallStatus.connecting));
    try {
      final data = await _post('/calls/$callId/accept');
      await _joinRoom(
        livekitUrl: data['livekit_url'] as String,
        token: data['token'] as String,
      );
    } catch (e) {
      debugPrint('[CallService] acceptCall error: $e');
      _setState(state.value.copyWith(status: CallStatus.ended));
    }
  }

  Future<void> rejectCall() async {
    final callId = state.value.callId;
    if (callId != null) {
      try { await _post('/calls/$callId/reject'); } catch (_) {}
    }
    reset();
  }

  // ── Called when caller gets call_accepted WS event ────────────────────────

  Future<void> onCallAccepted(Map<String, dynamic> data) async {
    _ringTimer?.cancel();
    _setState(state.value.copyWith(
      status: CallStatus.connecting,
      token: data['token'] as String?,
      livekitUrl: data['livekit_url'] as String?,
      roomName: data['room_name'] as String?,
    ));
    await _joinRoom(
      livekitUrl: data['livekit_url'] as String,
      token: data['token'] as String,
    );
  }

  void onCallRejected() {
    _ringTimer?.cancel();
    _setState(state.value.copyWith(status: CallStatus.rejected));
    Future.delayed(const Duration(seconds: 2), reset);
  }

  void onCallEnded() {
    _hangUpLocally(status: CallStatus.ended);
  }

  void onCallMissed() {
    _setState(state.value.copyWith(status: CallStatus.missed));
    Future.delayed(const Duration(seconds: 2), reset);
  }

  // ── LiveKit Room ──────────────────────────────────────────────────────────

  Future<void> _joinRoom({required String livekitUrl, required String token}) async {
    _room = Room(
      roomOptions: const RoomOptions(
        defaultVideoPublishOptions: VideoPublishOptions(simulcast: false),
        defaultAudioPublishOptions: AudioPublishOptions(),
      ),
    );
    try {
      await _room!.connect(livekitUrl, token);
      await _room!.localParticipant?.setMicrophoneEnabled(true);
      _setState(state.value.copyWith(status: CallStatus.connected, elapsed: Duration.zero));
      _startElapsedTimer();
      await WakelockPlus.enable();

      _room!.addListener(_onRoomEvent);
    } catch (e) {
      debugPrint('[CallService] _joinRoom error: $e');
      _setState(state.value.copyWith(status: CallStatus.ended));
      await _disconnectRoom();
    }
  }

  void _onRoomEvent() {
    if (_room?.connectionState == ConnectionState.disconnected) {
      _hangUpLocally(status: CallStatus.ended);
    }
  }

  void _startElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.value.status == CallStatus.connected) {
        _setState(state.value.copyWith(
          elapsed: state.value.elapsed + const Duration(seconds: 1),
        ));
      }
    });
  }

  // ── Active Call Controls ──────────────────────────────────────────────────

  Future<void> toggleMute() async {
    final muted = !state.value.isMuted;
    await _room?.localParticipant?.setMicrophoneEnabled(!muted);
    _setState(state.value.copyWith(isMuted: muted));
  }

  Future<void> setSpeaker(bool enabled) async {
    try {
      final session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration(
        avAudioSessionCategory: enabled
            ? AVAudioSessionCategory.playback
            : AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.allowBluetooth,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: enabled
              ? AndroidAudioUsage.media
              : AndroidAudioUsage.voiceCommunication,
        ),
      ));
    } catch (e) {
      debugPrint('[CallService] setSpeaker error: $e');
    }
    _setState(state.value.copyWith(isSpeaker: enabled));
  }

  Future<void> endCall() async {
    final callId = state.value.callId;
    if (callId != null) {
      try { await _post('/calls/$callId/end'); } catch (_) {}
    }
    _hangUpLocally(status: CallStatus.ended);
  }

  // ── Internal Cleanup ──────────────────────────────────────────────────────

  void _hangUpLocally({required CallStatus status}) {
    _ringTimer?.cancel();
    _elapsedTimer?.cancel();
    _disconnectRoom();
    WakelockPlus.disable();
    _setState(state.value.copyWith(status: status));
    Future.delayed(const Duration(seconds: 2), reset);
  }

  Future<void> _disconnectRoom() async {
    _room?.removeListener(_onRoomEvent);
    await _room?.disconnect();
    _room?.dispose();
    _room = null;
  }

  void reset() {
    _ringTimer?.cancel();
    _elapsedTimer?.cancel();
    _disconnectRoom();
    WakelockPlus.disable();
    _setState(const CallState());
  }

  bool get hasActiveCall =>
      state.value.status != CallStatus.idle &&
      state.value.status != CallStatus.ended &&
      state.value.status != CallStatus.rejected &&
      state.value.status != CallStatus.missed &&
      state.value.status != CallStatus.noAnswer &&
      state.value.status != CallStatus.permissionDenied;
}
