import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:audio_session/audio_session.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:vibration/vibration.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audioplayers/audioplayers.dart' hide AVAudioSessionCategory;
import '../config/api.dart';
import '../services/storage_service.dart';
import 'push_notification_service.dart';

enum CallStatus {
  idle,
  calling, // outgoing — waiting for answer
  ringing, // incoming — waiting for our action
  connecting, // accepted — joining LiveKit room
  connected, // in call
  ended,
  rejected,
  missed,
  noAnswer,
  permissionDenied,
  busy,
  reconnecting,
}

class CallApiException implements Exception {
  final int statusCode;
  final String? code;
  final String message;

  CallApiException(this.statusCode, this.code, this.message);

  @override
  String toString() => 'CallApiException($statusCode): $code - $message';
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
  final bool permPermanentlyDenied;
  final bool isPoorConnection;

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
    this.permPermanentlyDenied = false,
    this.isPoorConnection = false,
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
    bool? permPermanentlyDenied,
    bool? isPoorConnection,
  }) {
    return CallState(
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
      permPermanentlyDenied:
          permPermanentlyDenied ?? this.permPermanentlyDenied,
      isPoorConnection: isPoorConnection ?? this.isPoorConnection,
    );
  }
}

class CallService {
  CallService._();
  static final CallService instance = CallService._();

  final ValueNotifier<CallState> state = ValueNotifier(const CallState());
  final isCallScreenVisible = ValueNotifier<bool>(false);

  Room? _room;
  Function? _roomEventsSubscription;
  StreamSubscription<AudioInterruptionEvent>? _audioInterruptionSubscription;
  Timer? _ringTimer; // 30s no-answer timeout
  Timer? _elapsedTimer;
  Timer? _peerTimeoutTimer; // Timeout if other user doesn't join LiveKit room
  Timer? _ringtoneLoopTimer; // For iOS ringtone looping
  Timer? _resetTimer; // To prevent delayed reset overwriting new calls
  
  Timer? _hapticLoopTimer;
  
  final AudioPlayer _audioPlayer = AudioPlayer();

  // ── Helpers ──────────────────────────────────────────────────────────────

  Future<Map<String, String>> _authHeaders() async {
    final token = await StorageService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<Map<String, dynamic>> _post(
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    return await apiCall(
      () async => http.post(
        Uri.parse('$kBaseUrl$path'),
        headers: await _authHeaders(),
        body: body != null ? jsonEncode(body) : null,
      ),
    );
  }

  Future<Map<String, dynamic>> _get(String path) async {
    return await apiCall(
      () async => http.get(
        Uri.parse('$kBaseUrl$path'),
        headers: await _authHeaders(),
      ),
    );
  }

  void _setState(CallState s) {
    debugPrint('[LIVE_SCREEN_CALL] CallState changed to: ${s.status}');
    final oldStatus = state.value.status;
    final oldPoor = state.value.isPoorConnection;
    state.value = s;
    
    if (oldStatus != s.status) {
      _handleStatusChange(oldStatus, s.status);
    }
    
    if (!oldPoor && s.isPoorConnection && s.status == CallStatus.connected) {
      _audioPlayer.setReleaseMode(ReleaseMode.release);
      _audioPlayer.play(AssetSource('sounds/weak.wav'));
    }
  }

  void _handleStatusChange(CallStatus oldStatus, CallStatus newStatus) {
    if (newStatus == CallStatus.calling) {
      _audioPlayer.setReleaseMode(ReleaseMode.loop);
      _audioPlayer.play(AssetSource('sounds/ringing.wav'));
    } else if (newStatus == CallStatus.busy || newStatus == CallStatus.rejected) {
      _audioPlayer.setReleaseMode(ReleaseMode.release);
      _audioPlayer.play(AssetSource('sounds/busy.wav'));
    } else if (newStatus == CallStatus.ended) {
      if (oldStatus == CallStatus.connected || oldStatus == CallStatus.connecting) {
        _audioPlayer.setReleaseMode(ReleaseMode.release);
        _audioPlayer.play(AssetSource('sounds/ended.wav'));
      } else {
        _audioPlayer.stop();
      }
    } else if (newStatus == CallStatus.connected || newStatus == CallStatus.idle) {
      _audioPlayer.stop();

    }
  }

  // ── Outgoing Call ─────────────────────────────────────────────────────────

  Future<void> startCall({
    required int calleeId,
    required String calleeUsername,
    required String? calleeAvatar,
  }) async {
    _resetTimer?.cancel();
    if (hasActiveCall) {
      debugPrint('[CallService] Cannot start call: already in an active call.');
      return;
    }

    final permStatus = await Permission.microphone.request();
    if (permStatus != PermissionStatus.granted) {
      _setState(
        state.value.copyWith(
          status: CallStatus.permissionDenied,
          permPermanentlyDenied: permStatus.isPermanentlyDenied,
        ),
      );
      return;
    }

    _setState(
      CallState(
        status: CallStatus.calling,
        otherUserId: calleeId,
        otherUsername: calleeUsername,
        otherAvatar: calleeAvatar,
      ),
    );

    try {
      final data = await _post('/calls/start', {'callee_id': calleeId});
      _setState(
        state.value.copyWith(
          callId: data['call_id'] as int,
          roomName: data['room_name'] as String,
          livekitUrl: data['livekit_url'] as String,
          token: data['token'] as String,
        ),
      );
      _startRingTimer();
      await WakelockPlus.enable();
    } on CallApiException catch (e) {
      debugPrint('[LIVE_SCREEN_CALL] startCall catch (CallApiException) USER_BUSY triggered');
      if (e.code == 'USER_BUSY') {
        _setState(state.value.copyWith(status: CallStatus.busy));
        _scheduleReset();
      } else {
        _setState(state.value.copyWith(status: CallStatus.ended));
        _scheduleReset();
      }
    } catch (e, stack) {
      debugPrint('[LIVE_SCREEN_CALL] startCall catch (general exception) triggered: $e');
      _setState(state.value.copyWith(status: CallStatus.ended));
      _scheduleReset();
    }
  }

  void _startRingTimer() {
    _ringTimer?.cancel();
    _ringTimer = Timer(const Duration(seconds: 45), () async {
      if (state.value.status == CallStatus.calling) {
        final callId = state.value.callId;
        if (callId != null) {
          try {
            await _post('/calls/$callId/missed');
          } catch (_) {}
        }
        _setState(state.value.copyWith(status: CallStatus.noAnswer));
        await Future.delayed(const Duration(seconds: 2));
        reset();
      }
    });
  }

  // Ghost call protection
  int? _lastEndedCallId;

  // ── Incoming Call (WS / FCM triggered) ────────────────────────────────────

  Future<void> onIncomingCall(Map<String, dynamic> data) async {
    debugPrint('[LIVE_SCREEN_CALL] onIncomingCall received. data=$data');
    _resetTimer?.cancel();
    
    final incomingCallId = data['call_id'] is int
        ? data['call_id']
        : int.tryParse(data['call_id'].toString());

    if (incomingCallId != null && incomingCallId == _lastEndedCallId) {
      return;
    }

    if (hasActiveCall) {
      if (incomingCallId != null && incomingCallId != state.value.callId) {
        try {
          await _post('/calls/$incomingCallId/reject');
        } catch (_) {}
      }
      return;
    }

    if (incomingCallId != null) {
      try {
        final statusData = await _get('/calls/$incomingCallId/status');
        final backendStatus = statusData['status'];
        if (backendStatus == 'ended' || backendStatus == 'rejected' || backendStatus == 'missed') {
          return;
        }
      } catch (e) {
      }
    }

    _setState(
      CallState(
        status: CallStatus.ringing,
        callId: data['call_id'] is int
            ? data['call_id']
            : int.tryParse(data['call_id'].toString()),
        roomName: data['room_name'] as String?,
        livekitUrl: data['livekit_url'] as String?,
        otherUserId: data['caller_id'] is int
            ? data['caller_id']
            : int.tryParse(data['caller_id'].toString()),
        otherUsername: data['caller_username'] as String?,
        otherAvatar: data['caller_avatar'] as String?,
      ),
    );

    playNotification();
  }

  void playNotification() {
    FlutterRingtonePlayer().playNotification();
  }

  void startRingtoneAndVibration() async {
    // Play immediately
    FlutterRingtonePlayer().playRingtone(
      looping: true,
    ); // Android handles looping natively

    // iOS manual ringtone & haptic loop
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      _ringtoneLoopTimer?.cancel();
      _ringtoneLoopTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
        FlutterRingtonePlayer().playRingtone();
      });

      _hapticLoopTimer?.cancel();
      _hapticLoopTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
        if (await Vibration.hasVibrator() == true) {
          Vibration.vibrate();
        }
      });
    }

    if (await Vibration.hasVibrator() == true && defaultTargetPlatform != TargetPlatform.iOS) {
      Vibration.vibrate(pattern: [2000, 500, 2000, 500], repeat: 0);
    }
  }

  void stopRingtoneAndVibration() {
    _ringtoneLoopTimer?.cancel();
    _ringtoneLoopTimer = null;
    _hapticLoopTimer?.cancel();
    _hapticLoopTimer = null;
    FlutterRingtonePlayer().stop();
    Vibration.cancel();
  }

  Future<void> acceptCall() async {
    debugPrint('[LIVE_SCREEN_CALL] acceptCall triggered. Current status: ${state.value.status}');
    if (state.value.status == CallStatus.connecting || state.value.status == CallStatus.connected) {
      return;
    }
    final callId = state.value.callId;
    if (callId == null) {
      return;
    }
    if (state.value.status == CallStatus.connecting || state.value.status == CallStatus.connected) {
      return;
    }

    _resetTimer?.cancel();
    stopRingtoneAndVibration();
    final permStatus = await Permission.microphone.status;
    if (!permStatus.isGranted) {
      _setState(
        state.value.copyWith(
          status: CallStatus.permissionDenied,
          permPermanentlyDenied: permStatus.isPermanentlyDenied,
        ),
      );
      _hangUpLocally(status: CallStatus.ended);
      try {
        await PushNotificationService.showWarningNotification();
      } catch (_) {}
      return;
    }

    _setState(state.value.copyWith(status: CallStatus.connecting));
    debugPrint('[LIVE_SCREEN_CALL] Calling POST /calls/$callId/accept');
    try {
      Map<String, dynamic>? data;
      int retryCount = 0;
      while (retryCount < 4) {
        try {
          data = await _post('/calls/$callId/accept');
          break; // Success
        } catch (e) {
          retryCount++;
          if (retryCount >= 4) rethrow;
          await Future.delayed(Duration(milliseconds: 500 * retryCount)); // 500ms, 1000ms, 1500ms
        }
      }
      if (data == null) throw Exception('Accept data is null');

      debugPrint('[LIVE_SCREEN_CALL] Accept SUCCESS. Joining room...');
      await _joinRoom(
        livekitUrl: data['livekit_url'] as String,
        token: data['token'] as String,
      );
    } catch (e, stack) {
      debugPrint('[LIVE_SCREEN_CALL] acceptCall ERROR: $e');
      _hangUpLocally(status: CallStatus.ended);
    }
  }

  Future<void> rejectCall() async {
    if (state.value.status == CallStatus.ended || state.value.status == CallStatus.rejected) return;
    final callId = state.value.callId;
    if (callId != null) {
      try {
        await _post('/calls/$callId/reject');
      } catch (_) {}
    }
    reset();
  }

  // ── Called when caller gets call_accepted WS event ────────────────────────

  Future<void> onCallAccepted(Map<String, dynamic> data) async {
    _ringTimer?.cancel();
    stopRingtoneAndVibration();
    
    final currentUrl = state.value.livekitUrl;
    final currentToken = state.value.token;
    
    if (currentUrl == null || currentToken == null) {
      debugPrint('[CallService] Cannot join room: token or url is null.');
      _setState(state.value.copyWith(status: CallStatus.ended));
      return;
    }
    
    if (state.value.status == CallStatus.connecting || state.value.status == CallStatus.connected) return;
    
    _resetTimer?.cancel();
    _setState(state.value.copyWith(status: CallStatus.connecting));
    
    await _joinRoom(
      livekitUrl: currentUrl,
      token: currentToken,
    );
  }

  void onCallRejected() async {
    if (state.value.status == CallStatus.rejected) return;
    stopRingtoneAndVibration();
    _ringTimer?.cancel();
    _setState(state.value.copyWith(status: CallStatus.rejected));
    if (await Vibration.hasVibrator() == true) {
      Vibration.vibrate(pattern: [200, 100, 200, 100, 200]);
    }
    _scheduleReset();
  }

  void onCallEnded() {
    debugPrint('[LIVE_SCREEN_CALL] onCallEnded (via WS) triggered');
    _hangUpLocally(status: CallStatus.ended);
  }

  void onCallMissed() async {
    if (state.value.status == CallStatus.missed) return;
    stopRingtoneAndVibration();
    _setState(state.value.copyWith(status: CallStatus.missed));
    if (await Vibration.hasVibrator() == true) {
      Vibration.vibrate(pattern: [200, 100, 200]);
    }
    _scheduleReset();
  }

  // ── LiveKit Room ──────────────────────────────────────────────────────────

  Future<void> _joinRoom({
    required String livekitUrl,
    required String token,
  }) async {
    _room = Room();
    
    try {
      debugPrint('[LIVE_SCREEN_CALL] _joinRoom starting... livekitUrl: $livekitUrl, token length: ${token.length}');
      
      // Force iOS to use earpiece and playAndRecord category before LiveKit messes with it
      try {
        final session = await AudioSession.instance;
        await session.configure(AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
          avAudioSessionMode: AVAudioSessionMode.voiceChat,
          avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.allowBluetooth | AVAudioSessionCategoryOptions.allowBluetoothA2dp,
        ));
        await Hardware.instance.setSpeakerphoneOn(false);
      } catch (e) {
        debugPrint('[CallService] AudioSession pre-config error: $e');
      }

      await _room!.connect(livekitUrl, token, roomOptions: const RoomOptions(defaultAudioOutputOptions: AudioOutputOptions(speakerOn: false)));
      debugPrint('[LIVE_SCREEN_CALL] _joinRoom SUCCESSFUL!');
      
      // We must fulfill CallKit BEFORE enabling the microphone on iOS!
      if (Platform.isIOS && state.value.callId != null) {
        final uuid = formatToUuid(state.value.callId!.toString());
        const MethodChannel('com.teqlif/callkit').invokeMethod('fulfillAccept', {'uuid': uuid}).catchError((e) {
          debugPrint('[CallService] ERROR invoking fulfillAccept: $e');
        });
        // Give CallKit a moment to fully activate the audio session
        await Future.delayed(const Duration(milliseconds: 800));
      } else if (Platform.isAndroid && state.value.callId != null) {
        final uuid = formatToUuid(state.value.callId!.toString());
        FlutterCallkitIncoming.setCallConnected(uuid).catchError((e) {
          debugPrint('[CallService] ERROR invoking setCallConnected: $e');
        });
      }

      await _room!.localParticipant?.setMicrophoneEnabled(true);
      
      // Re-assert speakerphone setting after publishing mic
      await Future.delayed(const Duration(milliseconds: 500));
      await Hardware.instance.setSpeakerphoneOn(false);
      
      _setState(
        state.value.copyWith(
          status: CallStatus.connected,
          elapsed: Duration.zero,
        ),
      );
      
      _startElapsedTimer();
      await WakelockPlus.enable();

      _roomEventsSubscription = _room!.events.listen(_onRoomEvent);
      
      _peerTimeoutTimer?.cancel();
      _peerTimeoutTimer = Timer(const Duration(seconds: 15), () {
        if (_room != null && _room!.remoteParticipants.isEmpty) {
          debugPrint('[LIVE_SCREEN_CALL] Peer did not join within 15 seconds. Hanging up.');
          endCall();
        }
      });
      
      _setState(state.value.copyWith(status: CallStatus.connected));
      debugPrint('[LIVE_SCREEN_CALL] Call is now CONNECTED.');
      await _setupAudioInterruptionListener();
    } catch (e) {
      debugPrint('[LIVE_SCREEN_CALL] _joinRoom EXCEPTION: $e');
      _hangUpLocally(status: CallStatus.ended);
      await _disconnectRoom();
    }
  }

  void _onRoomEvent(RoomEvent event) {
    if (event is RoomDisconnectedEvent) {
      _hangUpLocally(status: CallStatus.ended);
    } else if (event is RoomReconnectingEvent) {
      _setState(state.value.copyWith(status: CallStatus.reconnecting));
    } else if (event is RoomReconnectedEvent) {
      if (state.value.status == CallStatus.reconnecting) {
        _setState(state.value.copyWith(status: CallStatus.connected));
      }
    } else if (event is ParticipantConnectedEvent) {
      debugPrint('[LIVE_SCREEN_CALL] Peer joined the room. Cancelling peer timeout.');
      _peerTimeoutTimer?.cancel();
    } else if (event is TrackSubscribedEvent) {
      if (Platform.isAndroid && event.track.kind == TrackType.AUDIO) {
        Hardware.instance.setSpeakerphoneOn(false);
        _setState(state.value.copyWith(isSpeaker: false));
      }
    } else if (event is ParticipantConnectionQualityUpdatedEvent) {
      if (event.participant == _room?.localParticipant) {
        final isPoor =
            (event.connectionQuality == ConnectionQuality.poor ||
            event.connectionQuality == ConnectionQuality.lost);
        if (state.value.isPoorConnection != isPoor) {
          _setState(state.value.copyWith(isPoorConnection: isPoor));
        }
      }
    }
  }

  Future<void> _setupAudioInterruptionListener() async {
    _audioInterruptionSubscription?.cancel();
    final session = await AudioSession.instance;
    _audioInterruptionSubscription = session.interruptionEventStream.listen((
      event,
    ) {
      if (event.begin) {
        // Interruption began (e.g. phone call came in)
        if (!state.value.isMuted) {
          _room?.localParticipant?.setMicrophoneEnabled(false);
          _setState(state.value.copyWith(isMuted: true));
        }
      } else {
        // Interruption ended
        if (state.value.isMuted) {
          _room?.localParticipant?.setMicrophoneEnabled(true);
          _setState(state.value.copyWith(isMuted: false));
        }
      }
    });
  }

  void _startElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.value.status == CallStatus.connected) {
        _setState(
          state.value.copyWith(
            elapsed: state.value.elapsed + const Duration(seconds: 1),
          ),
        );
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
      await Hardware.instance.setSpeakerphoneOn(enabled);
    } catch (e) {
      debugPrint('[CallService] setSpeaker error: $e');
    }
    _setState(state.value.copyWith(isSpeaker: enabled));
  }
  Future<void> endCall() async {
    debugPrint('[LIVE_SCREEN_CALL] endCall triggered manually by user');
    if (state.value.status == CallStatus.ended || state.value.status == CallStatus.idle) {
      return;
    }
    final callId = state.value.callId;
    if (callId != null) {
      try {
        int retryCount = 0;
        while (retryCount < 4) {
          try {
            await _post('/calls/$callId/end');
            break;
          } catch (e) {
            retryCount++;
            if (retryCount >= 4) break;
            await Future.delayed(Duration(milliseconds: 500 * retryCount));
          }
        }
      } catch (_) {}
    }
    _hangUpLocally(status: CallStatus.ended);
  }

  // ── Internal Cleanup ──────────────────────────────────────────────────────

  String _formatToUuid(String id) {
    final padded = id.padLeft(32, '0');
    return '${padded.substring(0, 8)}-${padded.substring(8, 12)}-${padded.substring(12, 16)}-${padded.substring(16, 20)}-${padded.substring(20, 32)}';
  }

  void _hangUpLocally({required CallStatus status}) {
    debugPrint('[LIVE_SCREEN_CALL] _hangUpLocally called with status: $status');
    try {
      throw Exception('_hangUpLocally stack trace logger');
    } catch (e, st) {
      debugPrint('[LIVE_SCREEN_CALL] Trace: $st');
    }
    if (state.value.status == status) return;
    stopRingtoneAndVibration();
    _ringTimer?.cancel();
    _elapsedTimer?.cancel();
    _disconnectRoom();
    WakelockPlus.disable();
    if (state.value.callId != null) {
      FlutterCallkitIncoming.endCall(_formatToUuid(state.value.callId.toString()));
    }
    FlutterCallkitIncoming.endAllCalls();
    _setState(state.value.copyWith(status: status));
    _scheduleReset();
  }

  Future<void> _disconnectRoom() async {
    _ringtoneLoopTimer?.cancel();
    _elapsedTimer?.cancel();
    _peerTimeoutTimer?.cancel();
    _roomEventsSubscription?.call();
    _audioInterruptionSubscription?.cancel();
    _room?.disconnect();
    _room?.dispose();
    _room = null;
  }

  void reset() {
    _resetTimer?.cancel();
    stopRingtoneAndVibration();
    _ringTimer?.cancel();
    _elapsedTimer?.cancel();
    _peerTimeoutTimer?.cancel();
    _disconnectRoom();
    WakelockPlus.disable();
    FlutterCallkitIncoming.endAllCalls();
    
    if (state.value.callId != null) {
      _lastEndedCallId = state.value.callId;
    }
    
    _setState(const CallState());
  }

  void _scheduleReset() {
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(seconds: 2), reset);
  }

  bool get hasActiveCall =>
      state.value.status == CallStatus.calling ||
      state.value.status == CallStatus.ringing ||
      state.value.status == CallStatus.connecting ||
      state.value.status == CallStatus.connected ||
      state.value.status == CallStatus.reconnecting;
}
