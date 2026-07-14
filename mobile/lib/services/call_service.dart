import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:audio_session/audio_session.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:vibration/vibration.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audioplayers/audioplayers.dart' hide AVAudioSessionCategory;
import 'package:audioplayers/audioplayers.dart' as ap;
import '../config/api.dart';
import '../core/app_exception.dart';
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

  const CallState({
    this.status = CallStatus.idle,
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
  });

  CallState copyWith({
    CallStatus? status,
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
  }) {
    return CallState(
      status: status ?? this.status,
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
    );
  }
}

class CallService {
  CallService._() {
    _audioPlayer.onPlayerComplete.listen((_) async {
      if (state.value.status == CallStatus.calling) {
        await _audioPlayer.play(ap.AssetSource('sounds/ringing.wav'));
      }
    });
  }
  static final CallService instance = CallService._();

  final ValueNotifier<CallState> state = ValueNotifier(const CallState());
  final isCallScreenVisible = ValueNotifier<bool>(false);
  final preventCallScreenAutoOpen = ValueNotifier<bool>(false);

  Room? _room;
  Function? _roomEventsSubscription;
  StreamSubscription<AudioInterruptionEvent>? _audioInterruptionSubscription;
  Timer? _ringTimer; // 30s no-answer timeout
  Timer? _elapsedTimer;
  Timer? _peerTimeoutTimer; // Timeout if other user doesn't join LiveKit room
  Timer? _ringtoneLoopTimer; // For iOS ringtone looping
  Timer? _resetTimer; // To prevent delayed reset overwriting new calls
  Timer? _callerStatusPollTimer; // Poll /status while in calling state (WS kayıp event recovery)

  bool _isHangingUp = false; // Eş zamanlı _hangUpLocally çağrılarını önler
  
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
    debugPrint('[LIVE_SCREEN_CALL][${DateTime.now().toIso8601String()}] CallState changed to: ${s.status}');
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
      AudioSession.instance.then((session) async {
        try {
          // Ringtone için ses ayarları — VoiceCommunication değil, ring/notification.
          // Android'de voiceCommunication + AudioFocus.gain, ReleaseMode.loop'u
          // keserek ses sadece bir kere çalar. Ring context bunu engeller.
          await session.configure(AudioSessionConfiguration(
            avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
            avAudioSessionMode: AVAudioSessionMode.voiceChat,
            avAudioSessionCategoryOptions:
                AVAudioSessionCategoryOptions.allowBluetooth |
                AVAudioSessionCategoryOptions.allowBluetoothA2dp,
            androidAudioAttributes: AndroidAudioAttributes(
              contentType: AndroidAudioContentType.music,
              flags: AndroidAudioFlags.none,
              usage: AndroidAudioUsage.notificationRingtone,
            ),
            androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransientMayDuck,
            androidWillPauseWhenDucked: false,
          ));
          await Hardware.instance.setSpeakerphoneOn(false);

          // AudioPlayer context: ringtone için ring stream
          await _audioPlayer.setAudioContext(ap.AudioContext(
            android: const ap.AudioContextAndroid(
              usageType: ap.AndroidUsageType.notificationRingtone,
              contentType: ap.AndroidContentType.music,
              audioFocus: ap.AndroidAudioFocus.gainTransientMayDuck,
            ),
            iOS: ap.AudioContextIOS(
              category: ap.AVAudioSessionCategory.playAndRecord,
              options: {
                ap.AVAudioSessionOptions.allowBluetooth,
                ap.AVAudioSessionOptions.allowBluetoothA2DP,
              },
            ),
          ));
        } catch (e) {
          debugPrint('[LIVE_SCREEN_CALL] AudioSession prep error: $e');
        }

        _audioPlayer.setReleaseMode(ReleaseMode.loop);
        if (state.value.status == CallStatus.calling) {
          if (Platform.isIOS) {
            await Future.delayed(const Duration(milliseconds: 600));
          }
          if (state.value.status == CallStatus.calling) {
            debugPrint('[LIVE_SCREEN_CALL][${DateTime.now().toIso8601String()}] _handleStatusChange: AUDIO PLAYER ringing.wav PLAY STARTED (EARPIECE/LOOP)');
            _audioPlayer.play(AssetSource('sounds/ringing.wav'));
          }
        }
      });
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
    debugPrint('[LIVE_SCREEN_CALL][\${DateTime.now().toIso8601String()}] startCall function ENTERED');
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
      debugPrint('[LIVE_SCREEN_CALL][\${DateTime.now().toIso8601String()}] startCall: Calling HTTP POST /calls/start');
      final data = await _post('/calls/start', {'callee_id': calleeId});
      debugPrint('[LIVE_SCREEN_CALL][\${DateTime.now().toIso8601String()}] startCall: HTTP POST SUCCESS');
      _setState(
        state.value.copyWith(
          callId: data['call_id'] as int,
          roomName: data['room_name'] as String,
          livekitUrl: data['livekit_url'] as String,
          token: data['token'] as String,
        ),
      );

      if (Platform.isIOS) {
        try {
          final uuid = _formatToUuid(data['call_id'].toString());
          final params = CallKitParams(
            id: uuid,
            nameCaller: calleeUsername,
            appName: 'teqlif',
            avatar: calleeAvatar ?? 'https://i.pravatar.cc/100',
            handle: 'Teqlif Voice Call',
            type: 0,
            duration: 45000,
            extra: {'call_id': data['call_id']},
            ios: IOSParams(
              iconName: 'AppIcon',
              handleType: 'generic',
              supportsVideo: false,
              maximumCallGroups: 1,
              maximumCallsPerCallGroup: 1,
              audioSessionMode: 'voiceChat',
              audioSessionActive: true,
              audioSessionPreferredSampleRate: 44100.0,
              audioSessionPreferredIOBufferDuration: 0.005,
              supportsDTMF: true,
              supportsHolding: true,
              supportsGrouping: false,
              supportsUngrouping: false,
              ringtonePath: 'system_ringtone_default',
            ),
          );
          await FlutterCallkitIncoming.startCall(params);
        } catch (e) {
          debugPrint('[LIVE_SCREEN_CALL][\${DateTime.now().toIso8601String()}] startCall CallKit Error: \$e');
        }
      }

      _startRingTimer();
      await WakelockPlus.enable();
      
      // WhatsApp-like Pre-Connection: Arayan kişi beklemeden LiveKit'e bağlanır.
      debugPrint('[LIVE_SCREEN_CALL][${DateTime.now().toIso8601String()}] startCall: About to AWAIT _joinRoom for Pre-Connection');
      await _joinRoom(
        livekitUrl: data['livekit_url'] as String,
        token: data['token'] as String,
      );
      debugPrint('[LIVE_SCREEN_CALL][${DateTime.now().toIso8601String()}] startCall: AWAIT _joinRoom FINISHED');

      // WS kayıp event recovery: call_accepted WS'den gelmezse poll ile yakala
      final callIdForPoll = data['call_id'] as int;
      _startCallerStatusPoll(callIdForPoll);
    } on AppException catch (e) {
      debugPrint('[LIVE_SCREEN_CALL][${DateTime.now().toIso8601String()}] startCall catch (AppException) triggered: ${e.code}');
      if (e.code == 'USER_BUSY') {
        _setState(state.value.copyWith(status: CallStatus.busy));
        _scheduleReset();
      } else {
        _setState(state.value.copyWith(status: CallStatus.ended));
        _scheduleReset();
      }
    } catch (e, stack) {
      debugPrint('[LIVE_SCREEN_CALL][${DateTime.now().toIso8601String()}] startCall catch (general exception) triggered: $e');
      _setState(state.value.copyWith(status: CallStatus.ended));
      _scheduleReset();
    }
  }

  void _startRingTimer() {
    _ringTimer?.cancel();
    // 30s: server ARQ 35s'den önce client timeout atar (server sadece backup)
    _ringTimer = Timer(const Duration(seconds: 30), () async {
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

  /// WS kayıp event recovery: caller calling durumundayken /status'u poll et.
  /// WS geçici kopuksa ve call_accepted eventi kaçtıysa bu metod yakalar.
  void _startCallerStatusPoll(int callId) {
    _callerStatusPollTimer?.cancel();
    _callerStatusPollTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      if (state.value.status != CallStatus.calling) {
        _callerStatusPollTimer?.cancel();
        return;
      }
      try {
        final statusData = await _get('/calls/$callId/status');
        final s = statusData['status'] as String?;
        if (s == 'active') {
          _callerStatusPollTimer?.cancel();
          if (state.value.status == CallStatus.calling) {
            debugPrint('[LIVE_SCREEN_CALL] Poll recovered call_accepted event | call_id=$callId');
            await onCallAccepted({
              if (statusData['accepted_at'] != null) 'accepted_at': statusData['accepted_at'],
            });
          }
        } else if (s == 'missed' || s == 'ended' || s == 'rejected') {
          _callerStatusPollTimer?.cancel();
          if (state.value.status == CallStatus.calling) {
            debugPrint('[LIVE_SCREEN_CALL] Poll detected call terminated | call_id=$callId status=$s');
            await _hangUpLocally(status: CallStatus.ended);
          }
        }
      } catch (_) {}
    });
  }

  // Ghost call protection
  int? _lastEndedCallId;

  // ── Incoming Call (WS / FCM triggered) ────────────────────────────────────

  Future<void> onIncomingCall(Map<String, dynamic> data) async {
    debugPrint('[LIVE_SCREEN_CALL][${DateTime.now().toIso8601String()}] onIncomingCall received. data=$data');
    debugPrint('[LIVE_SCREEN_CALL][${DateTime.now().toIso8601String()}] onIncomingCall Explicit Check: livekitUrl=${data['livekit_url']}, calleeToken=${data['callee_token'] != null ? "EXISTS" : "MISSING"}');
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
        calleeToken: data['callee_token'] as String?,
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
    debugPrint('[LIVE_SCREEN_CALL][\${DateTime.now().toIso8601String()}] playNotification() triggered');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (state.value.status == CallStatus.ringing) {
        FlutterRingtonePlayer().playNotification();
      }
    });
  }

  void startRingtoneAndVibration() async {
    debugPrint('[LIVE_SCREEN_CALL][\${DateTime.now().toIso8601String()}] startRingtoneAndVibration() triggered');
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (state.value.status != CallStatus.ringing) return;
      
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
    });
  }

  void stopRingtoneAndVibration() {
    debugPrint('[LIVE_SCREEN_CALL][\${DateTime.now().toIso8601String()}] stopRingtoneAndVibration() triggered');
    _ringtoneLoopTimer?.cancel();
    _ringtoneLoopTimer = null;
    _hapticLoopTimer?.cancel();
    _hapticLoopTimer = null;
    FlutterRingtonePlayer().stop();
    Vibration.cancel();
  }

  Future<void> acceptCall() async {
    debugPrint('[LIVE_SCREEN_CALL][${DateTime.now().toIso8601String()}] acceptCall triggered. Current status: ${state.value.status}');
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
    
    debugPrint('[LIVE_SCREEN_CALL][${DateTime.now().toIso8601String()}] acceptCall Pre-Connection Check: livekitUrl=${state.value.livekitUrl != null ? "EXISTS" : "NULL"}, calleeToken=${state.value.calleeToken != null ? "EXISTS" : "NULL"}');
    
    // WhatsApp-like Pre-Connection: Aranan kişi beklemeden LiveKit'e bağlanır.
    if (state.value.livekitUrl != null && state.value.calleeToken != null) {
      debugPrint('[LIVE_SCREEN_CALL][${DateTime.now().toIso8601String()}] Executing _joinRoom for Callee pre-connection');
      _joinRoom(
        livekitUrl: state.value.livekitUrl!,
        token: state.value.calleeToken!,
      ).catchError((e) {
        debugPrint('[LIVE_SCREEN_CALL][${DateTime.now().toIso8601String()}] Pre-connection error: $e');
      });
    } else {
      debugPrint('[LIVE_SCREEN_CALL][${DateTime.now().toIso8601String()}] SKIPPED _joinRoom for Callee because URL or Token is NULL!');
    }

    debugPrint('[LIVE_SCREEN_CALL][${DateTime.now().toIso8601String()}] Calling POST /calls/$callId/accept');
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

      debugPrint('[LIVE_SCREEN_CALL][${DateTime.now().toIso8601String()}] Accept SUCCESS.');
      if (data['accepted_at'] != null) {
        _setState(state.value.copyWith(
          acceptedAt: DateTime.parse(data['accepted_at']),
        ));
      }
    } catch (e, stack) {
      debugPrint('[LIVE_SCREEN_CALL][${DateTime.now().toIso8601String()}] acceptCall ERROR: $e');
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
    _callerStatusPollTimer?.cancel(); // Poll'u durdur — event zaten geldi
    stopRingtoneAndVibration();
    
    if (data['accepted_at'] != null) {
      _setState(state.value.copyWith(
        acceptedAt: DateTime.parse(data['accepted_at']),
      ));
    }
    
    if (state.value.status == CallStatus.connecting || state.value.status == CallStatus.connected) return;
    
    _resetTimer?.cancel();
    _setState(state.value.copyWith(status: CallStatus.connecting));
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
    debugPrint('[LIVE_SCREEN_CALL][${DateTime.now().toIso8601String()}] onCallEnded (via WS) triggered');
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
      debugPrint('[LIVE_SCREEN_CALL][${DateTime.now().toIso8601String()}] _joinRoom starting... livekitUrl: $livekitUrl, token length: ${token.length}');
      
      // We must fulfill CallKit BEFORE enabling the microphone and connecting on iOS!
      // This prevents the AudioSession from defaulting to SoloAmbient (Speaker) and jumping to VoiceChat.
      if (Platform.isIOS && state.value.callId != null && state.value.status == CallStatus.connecting) {
        final uuid = formatToUuid(state.value.callId!.toString());
        const MethodChannel('com.teqlif/callkit').invokeMethod('fulfillAccept', {'uuid': uuid}).catchError((e) {
          debugPrint('[CallService] ERROR invoking fulfillAccept: $e');
        });
        // Give CallKit a moment to fully activate the audio session
        await Future.delayed(const Duration(milliseconds: 500));
      } else if (Platform.isAndroid && state.value.callId != null && state.value.status == CallStatus.connecting) {
        final uuid = formatToUuid(state.value.callId!.toString());
        FlutterCallkitIncoming.setCallConnected(uuid).catchError((e) {
          debugPrint('[CallService] ERROR invoking setCallConnected: $e');
        });
      }

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
      debugPrint('[LIVE_SCREEN_CALL][${DateTime.now().toIso8601String()}] _joinRoom SUCCESSFUL!');

      await _room!.localParticipant?.setMicrophoneEnabled(true);
      
      // Re-assert speakerphone setting after publishing mic
      await Future.delayed(const Duration(milliseconds: 500));
      await Hardware.instance.setSpeakerphoneOn(false);
      
      _roomEventsSubscription = _room!.events.listen(_onRoomEvent);
      
      bool peerAlreadyJoined = _room!.remoteParticipants.isNotEmpty;
      if (state.value.status == CallStatus.connecting || peerAlreadyJoined) {
        _setState(
          state.value.copyWith(
            status: CallStatus.connected,
          ),
        );
        _startElapsedTimer();
        debugPrint('[LIVE_SCREEN_CALL][${DateTime.now().toIso8601String()}] Call is now CONNECTED in _joinRoom.');
      } else {
        debugPrint('[LIVE_SCREEN_CALL][${DateTime.now().toIso8601String()}] Joined LiveKit, waiting for peer to join.');
      }
      
      await WakelockPlus.enable();

      _peerTimeoutTimer?.cancel();
      _peerTimeoutTimer = Timer(const Duration(seconds: 15), () {
        if (_room != null && _room!.remoteParticipants.isEmpty) {
          if (state.value.status == CallStatus.connected) {
             debugPrint('[LIVE_SCREEN_CALL][${DateTime.now().toIso8601String()}] Peer left or did not join within 15 seconds. Hanging up.');
             endCall();
          }
        }
      });
      
      await _setupAudioInterruptionListener();
    } catch (e) {
      debugPrint('[LIVE_SCREEN_CALL][${DateTime.now().toIso8601String()}] _joinRoom EXCEPTION: $e');
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
      debugPrint('[LIVE_SCREEN_CALL][${DateTime.now().toIso8601String()}] Peer joined the room. Cancelling peer timeout.');
      _peerTimeoutTimer?.cancel();
      if (state.value.status == CallStatus.calling || state.value.status == CallStatus.connecting) {
        _setState(state.value.copyWith(status: CallStatus.connected));
        _startElapsedTimer();
        stopRingtoneAndVibration(); // Just in case Caller was still ringing
      }
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
        if (state.value.acceptedAt != null) {
          _setState(
            state.value.copyWith(
              elapsed: DateTime.now().toUtc().difference(state.value.acceptedAt!.toUtc()),
            ),
          );
        } else {
          _setState(
            state.value.copyWith(
              elapsed: state.value.elapsed + const Duration(seconds: 1),
            ),
          );
        }
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
    debugPrint('[LIVE_SCREEN_CALL][${DateTime.now().toIso8601String()}] endCall triggered manually by user');
    if (state.value.status == CallStatus.ended || state.value.status == CallStatus.idle) {
      return;
    }
    final callId = state.value.callId;
    _callerStatusPollTimer?.cancel();
    if (callId != null) {
      // Fire-and-forget + tek retry: UI'ı bloke etme, arka planda gönder
      _post('/calls/$callId/end').catchError((_) async {
        await Future.delayed(const Duration(milliseconds: 500));
        _post('/calls/$callId/end').catchError((_) {});
      });
    }
    await _hangUpLocally(status: CallStatus.ended);
  }

  // ── Internal Cleanup ──────────────────────────────────────────────────────

  String _formatToUuid(String id) {
    final padded = id.padLeft(32, '0');
    return '${padded.substring(0, 8)}-${padded.substring(8, 12)}-${padded.substring(12, 16)}-${padded.substring(16, 20)}-${padded.substring(20, 32)}';
  }

  Future<void> _hangUpLocally({required CallStatus status}) async {
    debugPrint('[LIVE_SCREEN_CALL][${DateTime.now().toIso8601String()}] _hangUpLocally called with status: $status');
    // _isHangingUp: eş zamanlı çağrıları (WS event + FCM + LK disconnect) önler
    if (_isHangingUp) {
      debugPrint('[LIVE_SCREEN_CALL][${DateTime.now().toIso8601String()}] _hangUpLocally skipped (already hanging up)');
      return;
    }
    _isHangingUp = true;
    try {
      if (state.value.status == status) {
        return;
      }
      _callerStatusPollTimer?.cancel();
      stopRingtoneAndVibration();
      _ringTimer?.cancel();
      _elapsedTimer?.cancel();
      
      // 1. Bekleyerek odayı koparıyoruz (LiveKit native kaynakları serbest bıraksın)
      await _disconnectRoom();
      WakelockPlus.disable();
      
      // 2. CallKit'in iOS/Android native çağrılarını temizlemesini bekliyoruz
      if (state.value.callId != null) {
        await FlutterCallkitIncoming.endCall(_formatToUuid(state.value.callId.toString()));
      }
      await FlutterCallkitIncoming.endAllCalls();

      // 3. CallKit ve LiveKit kapandıktan sonra global ses oturumunu (AVAudioSession)
      // hoparlöre yönlendirecek şekilde zorluyoruz.
      try {
        await Hardware.instance.setSpeakerphoneOn(true);
      } catch (e) {
        debugPrint('[CallService] setSpeakerphoneOn(true) error: $e');
      }

      // 4. Bütün donanım/native işlemler bittikten sonra state'i güncelliyoruz
      // Böylece UI katmanı (SwipeLiveScreen) tepki verdiğinde her şey hazır oluyor.
      _setState(state.value.copyWith(status: status));
      _scheduleReset();
    } finally {
      _isHangingUp = false;
    }
  }

  Future<void> _disconnectRoom() async {
    _ringtoneLoopTimer?.cancel();
    _elapsedTimer?.cancel();
    _peerTimeoutTimer?.cancel();
    _callerStatusPollTimer?.cancel();
    _roomEventsSubscription?.call();
    _audioInterruptionSubscription?.cancel();
    
    if (_room != null) {
      await _room!.disconnect();
      await _room!.dispose();
      _room = null;
    }
  }

  void reset() {
    _resetTimer?.cancel();
    _callerStatusPollTimer?.cancel();
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
