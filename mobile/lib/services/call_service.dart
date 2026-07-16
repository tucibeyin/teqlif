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

void _cpLog(String phase, String msg) {
  debugPrint('[CALL_PROCESS][${DateTime.now().toIso8601String()}][$phase] $msg');
}

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
    final oldStatus = state.value.status;
    _cpLog('STATE', '${oldStatus.name} → ${s.status.name} | callId=${s.callId}');
    final oldPoor = state.value.isPoorConnection;
    state.value = s;
    
    if (oldStatus != s.status) {
      _handleStatusChange(oldStatus, s.status);
    }
    
    if (!oldPoor && s.isPoorConnection && s.status == CallStatus.connected) {
      _cpLog('SOUND', 'weak.wav PLAY | poorConnection detected');
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
            _cpLog('SOUND', 'ringing.wav PLAY | mode=loop earpiece');
            _audioPlayer.play(AssetSource('sounds/ringing.wav'));
          }
        }
      });
    } else if (newStatus == CallStatus.busy || newStatus == CallStatus.rejected) {
      _cpLog('SOUND', 'busy.wav PLAY | reason=$newStatus');
      _audioPlayer.setReleaseMode(ReleaseMode.release);
      _audioPlayer.play(AssetSource('sounds/busy.wav'));
    } else if (newStatus == CallStatus.ended) {
      if (oldStatus == CallStatus.connected || oldStatus == CallStatus.connecting) {
        _cpLog('SOUND', 'ended.wav PLAY | wasConnected=true');
        _audioPlayer.setReleaseMode(ReleaseMode.release);
        _audioPlayer.play(AssetSource('sounds/ended.wav'));
      } else {
        _cpLog('SOUND', 'audioPlayer.stop | ended without connection');
        _audioPlayer.stop();
      }
    } else if (newStatus == CallStatus.connected || newStatus == CallStatus.idle) {
      _cpLog('SOUND', 'audioPlayer.stop | status=$newStatus');
      _audioPlayer.stop();
    }
  }

  // ── Outgoing Call ─────────────────────────────────────────────────────────

  Future<void> startCall({
    required int calleeId,
    required String calleeUsername,
    required String? calleeAvatar,
  }) async {
    _cpLog('OUT', 'startCall ENTERED | calleeId=$calleeId calleeUsername=$calleeUsername');
    _resetTimer?.cancel();
    if (hasActiveCall) {
      _cpLog('OUT', 'startCall BLOCKED | hasActiveCall=true currentStatus=${state.value.status}');
      return;
    }

    final permStatus = await Permission.microphone.request();
    _cpLog('OUT', 'mic permission | status=$permStatus');
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
      _cpLog('OUT', 'POST /calls/start → request | calleeId=$calleeId');
      final data = await _post('/calls/start', {'callee_id': calleeId});
      _cpLog('OUT', 'POST /calls/start → response | callId=${data['call_id']} roomName=${data['room_name']}');
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
          _cpLog('OUT', 'CallKit.startCall ERROR | $e');
        }
      }

      _startRingTimer();
      await WakelockPlus.enable();
      
      // WhatsApp-like Pre-Connection: Arayan kişi beklemeden LiveKit'e bağlanır.
      _cpLog('OUT', 'pre-connect _joinRoom starting (WhatsApp-like)');
      await _joinRoom(
        livekitUrl: data['livekit_url'] as String,
        token: data['token'] as String,
      );
      _cpLog('OUT', 'pre-connect _joinRoom finished');

      // WS kayıp event recovery: call_accepted WS'den gelmezse poll ile yakala
      final callIdForPoll = data['call_id'] as int;
      _startCallerStatusPoll(callIdForPoll);
    } on AppException catch (e) {
      _cpLog('OUT', 'startCall AppException | code=${e.code}');
      if (e.code == 'USER_BUSY') {
        _setState(state.value.copyWith(status: CallStatus.busy));
        _scheduleReset();
      } else {
        _setState(state.value.copyWith(status: CallStatus.ended));
        _scheduleReset();
      }
    } catch (e, stack) {
      _cpLog('OUT', 'startCall EXCEPTION | $e');
      _setState(state.value.copyWith(status: CallStatus.ended));
      _scheduleReset();
    }
  }

  void _startRingTimer() {
    _ringTimer?.cancel();
    _cpLog('OUT', 'ringTimer started | timeout=30s callId=${state.value.callId}');
    _ringTimer = Timer(const Duration(seconds: 30), () async {
      if (state.value.status == CallStatus.calling) {
        final callId = state.value.callId;
        _cpLog('OUT', 'ringTimer FIRED → noAnswer | callId=$callId');
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
    _cpLog('OUT', 'callerStatusPoll started | interval=4s callId=$callId');
    _callerStatusPollTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      if (state.value.status != CallStatus.calling) {
        _callerStatusPollTimer?.cancel();
        return;
      }
      try {
        final statusData = await _get('/calls/$callId/status');
        final s = statusData['status'] as String?;
        _cpLog('OUT', 'callerStatusPoll tick | callId=$callId backendStatus=$s');
        if (s == 'active') {
          _callerStatusPollTimer?.cancel();
          if (state.value.status == CallStatus.calling) {
            _cpLog('OUT', 'callerStatusPoll → RECOVERED call_accepted | callId=$callId');
            await onCallAccepted({
              if (statusData['accepted_at'] != null) 'accepted_at': statusData['accepted_at'],
            });
          }
        } else if (s == 'missed' || s == 'ended' || s == 'rejected') {
          _callerStatusPollTimer?.cancel();
          if (state.value.status == CallStatus.calling) {
            _cpLog('OUT', 'callerStatusPoll → terminated | callId=$callId status=$s');
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
    _cpLog('IN', 'onIncomingCall received | callId=${data['call_id']} caller=${data['caller_username']} calleeToken=${data['callee_token'] != null ? "EXISTS" : "MISSING"} livekitUrl=${data['livekit_url'] != null ? "EXISTS" : "MISSING"}');
    _resetTimer?.cancel();

    final incomingCallId = data['call_id'] is int
        ? data['call_id']
        : int.tryParse(data['call_id'].toString());

    if (incomingCallId != null && incomingCallId == _lastEndedCallId) {
      _cpLog('IN', 'ghostCall BLOCKED | incoming=$incomingCallId == lastEnded=$_lastEndedCallId');
      return;
    }

    if (hasActiveCall) {
      _cpLog('IN', 'hasActiveCall BUSY_REJECT | currentStatus=${state.value.status} currentCallId=${state.value.callId} incomingCallId=$incomingCallId');
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
        _cpLog('IN', 'backendStatus check | callId=$incomingCallId status=$backendStatus');
        if (backendStatus == 'ended' || backendStatus == 'rejected' || backendStatus == 'missed') {
          _cpLog('IN', 'backendStatus SKIPPED (already terminated) | callId=$incomingCallId');
          return;
        }
      } catch (e) {
        _cpLog('IN', 'backendStatus check FAILED (continuing) | $e');
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
    _cpLog('SOUND', 'playNotification triggered');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (state.value.status == CallStatus.ringing) {
        FlutterRingtonePlayer().playNotification();
      }
    });
  }

  void startRingtoneAndVibration() async {
    _cpLog('SOUND', 'startRingtoneAndVibration CALLED | status=${state.value.status}');
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (state.value.status != CallStatus.ringing) return;
      
      _cpLog('SOUND', 'ringtone PLAY | platform=${defaultTargetPlatform.name} looping=true');
      FlutterRingtonePlayer().playRingtone(
        looping: true,
      );

      if (defaultTargetPlatform == TargetPlatform.iOS) {
        _ringtoneLoopTimer?.cancel();
        _cpLog('SOUND', 'iOS ringtoneLoopTimer started | interval=3s');
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
    _cpLog('SOUND', 'stopRingtoneAndVibration CALLED | status=${state.value.status}');
    _ringtoneLoopTimer?.cancel();
    _ringtoneLoopTimer = null;
    _hapticLoopTimer?.cancel();
    _hapticLoopTimer = null;
    FlutterRingtonePlayer().stop();
    Vibration.cancel();
  }

  Future<void> acceptCall() async {
    _cpLog('IN', 'acceptCall TRIGGERED | status=${state.value.status} callId=${state.value.callId}');
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
    _cpLog('IN', 'mic status check | status=$permStatus');
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
    
    _cpLog('IN', 'pre-connect check | livekitUrl=${state.value.livekitUrl != null ? "EXISTS" : "NULL"} calleeToken=${state.value.calleeToken != null ? "EXISTS" : "NULL"}');

    if (state.value.livekitUrl != null && state.value.calleeToken != null) {
      _cpLog('IN', 'pre-connect _joinRoom starting (callee, no await)');
      _joinRoom(
        livekitUrl: state.value.livekitUrl!,
        token: state.value.calleeToken!,
      ).catchError((e) {
        _cpLog('IN', 'pre-connect _joinRoom ERROR | $e');
      });
    } else {
      _cpLog('IN', 'pre-connect _joinRoom SKIPPED | url or calleeToken is null');
    }

    _cpLog('IN', 'POST /calls/$callId/accept → request (retry max=4)');
    try {
      Map<String, dynamic>? data;
      int retryCount = 0;
      while (retryCount < 4) {
        try {
          _cpLog('IN', 'POST /calls/$callId/accept attempt=${retryCount + 1}');
          data = await _post('/calls/$callId/accept');
          _cpLog('IN', 'POST /calls/$callId/accept SUCCESS | acceptedAt=${data?['accepted_at']}');
          break;
        } catch (e) {
          retryCount++;
          _cpLog('IN', 'POST /calls/$callId/accept RETRY | attempt=$retryCount error=$e');
          if (retryCount >= 4) rethrow;
          await Future.delayed(Duration(milliseconds: 500 * retryCount));
        }
      }
      if (data == null) throw Exception('Accept data is null');

      if (data['accepted_at'] != null) {
        _setState(state.value.copyWith(
          acceptedAt: DateTime.parse(data['accepted_at']),
        ));
      }
    } catch (e, stack) {
      _cpLog('IN', 'acceptCall FAILED after retries | $e');
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
    _cpLog('OUT', 'call_accepted WS event received | acceptedAt=${data['accepted_at']}');
    _ringTimer?.cancel();
    _callerStatusPollTimer?.cancel();
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
    _cpLog('END', 'call_ended WS event received → hangUpLocally');
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
      _cpLog('LK', '_joinRoom starting | url=$livekitUrl tokenLen=${token.length} status=${state.value.status}');
      
      // We must fulfill CallKit BEFORE enabling the microphone and connecting on iOS!
      // This prevents the AudioSession from defaulting to SoloAmbient (Speaker) and jumping to VoiceChat.
      if (Platform.isIOS && state.value.callId != null && state.value.status == CallStatus.connecting) {
        final uuid = formatToUuid(state.value.callId!.toString());
        _cpLog('LK', 'iOS CallKit fulfillAccept | uuid=$uuid');
        const MethodChannel('com.teqlif/callkit').invokeMethod('fulfillAccept', {'uuid': uuid}).catchError((e) {
          _cpLog('LK', 'fulfillAccept ERROR | $e');
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
        _cpLog('LK', 'AudioSession configure | category=playAndRecord mode=voiceChat speaker=false');
        final session = await AudioSession.instance;
        await session.configure(AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
          avAudioSessionMode: AVAudioSessionMode.voiceChat,
          avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.allowBluetooth | AVAudioSessionCategoryOptions.allowBluetoothA2dp,
        ));
        await Hardware.instance.setSpeakerphoneOn(false);
        _cpLog('LK', 'AudioSession configure OK');
      } catch (e) {
        _cpLog('LK', 'AudioSession pre-config ERROR | $e');
      }

      _cpLog('LK', 'room.connect() → calling LiveKit');
      await _room!.connect(livekitUrl, token, roomOptions: const RoomOptions(defaultAudioOutputOptions: AudioOutputOptions(speakerOn: false)));
      _cpLog('LK', 'room.connect() SUCCESS');

      _cpLog('LK', 'setMicrophoneEnabled(true) calling');
      await _room!.localParticipant?.setMicrophoneEnabled(true);
      _cpLog('LK', 'setMicrophoneEnabled(true) done');
      await Future.delayed(const Duration(milliseconds: 500));
      await Hardware.instance.setSpeakerphoneOn(false);
      
      _roomEventsSubscription = _room!.events.listen(_onRoomEvent);
      
      bool peerAlreadyJoined = _room!.remoteParticipants.isNotEmpty;
      _cpLog('LK', 'peerAlreadyJoined=$peerAlreadyJoined status=${state.value.status}');
      if (state.value.status == CallStatus.connecting || peerAlreadyJoined) {
        _setState(state.value.copyWith(status: CallStatus.connected));
        _startElapsedTimer();
        _cpLog('LK', 'setState(connected) → call is CONNECTED in _joinRoom');
      } else {
        _cpLog('LK', 'joined LiveKit → waiting for peer to join');
      }
      
      await WakelockPlus.enable();

      _peerTimeoutTimer?.cancel();
      _cpLog('LK', 'peerTimeoutTimer started | 15s');
      _peerTimeoutTimer = Timer(const Duration(seconds: 15), () {
        if (_room != null && _room!.remoteParticipants.isEmpty) {
          if (state.value.status == CallStatus.connected) {
            _cpLog('LK', 'peerTimeoutTimer FIRED → peer did not join in 15s → endCall');
            endCall();
          }
        }
      });
      
      await _setupAudioInterruptionListener();
    } catch (e) {
      _cpLog('LK', '_joinRoom EXCEPTION | $e');
      _hangUpLocally(status: CallStatus.ended);
      await _disconnectRoom();
    }
  }

  void _onRoomEvent(RoomEvent event) {
    _cpLog('LK', 'roomEvent | ${event.runtimeType}');
    if (event is RoomDisconnectedEvent) {
      _cpLog('LK', 'RoomDisconnected → hangUpLocally');
      _hangUpLocally(status: CallStatus.ended);
    } else if (event is RoomReconnectingEvent) {
      _setState(state.value.copyWith(status: CallStatus.reconnecting));
    } else if (event is RoomReconnectedEvent) {
      if (state.value.status == CallStatus.reconnecting) {
        _setState(state.value.copyWith(status: CallStatus.connected));
      }
    } else if (event is ParticipantConnectedEvent) {
      _cpLog('LK', 'ParticipantConnected → peer joined | peerCount=${_room?.remoteParticipants.length}');
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
    _cpLog('UI', 'toggleMute | newMuted=$muted');
    await _room?.localParticipant?.setMicrophoneEnabled(!muted);
    _setState(state.value.copyWith(isMuted: muted));
  }

  Future<void> setSpeaker(bool enabled) async {
    _cpLog('UI', 'setSpeaker | enabled=$enabled');
    try {
      await Hardware.instance.setSpeakerphoneOn(enabled);
    } catch (e) {
      _cpLog('UI', 'setSpeaker ERROR | $e');
    }
    _setState(state.value.copyWith(isSpeaker: enabled));
  }
  Future<void> endCall() async {
    _cpLog('END', 'endCall TRIGGERED by user | prevStatus=${state.value.status} callId=${state.value.callId}');
    if (state.value.status == CallStatus.ended || state.value.status == CallStatus.idle) {
      _cpLog('END', 'endCall SKIPPED | already ended/idle');
      return;
    }
    final callId = state.value.callId;
    _callerStatusPollTimer?.cancel();
    if (callId != null) {
      _cpLog('END', 'POST /calls/$callId/end fire-and-forget');
      _post('/calls/$callId/end').catchError((_) async {
        _cpLog('END', 'POST /calls/$callId/end retry');
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
    _cpLog('END', '_hangUpLocally called | targetStatus=$status prevStatus=${state.value.status} callId=${state.value.callId}');
    if (_isHangingUp) {
      _cpLog('END', '_hangUpLocally SKIPPED | already hanging up');
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
      
      _cpLog('END', 'disconnectRoom starting');
      await _disconnectRoom();
      _cpLog('END', 'disconnectRoom done');
      WakelockPlus.disable();

      _cpLog('END', 'CallKit.endCall | callId=${state.value.callId}');
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
      _cpLog('LK', 'room.disconnect() calling');
      await _room!.disconnect();
      _cpLog('LK', 'room.disconnect() done → dispose()');
      await _room!.dispose();
      _room = null;
      _cpLog('LK', 'room disposed | _room=null');
    } else {
      _cpLog('LK', '_disconnectRoom: room was already null');
    }
  }

  void reset() {
    _cpLog('END', 'reset() called | callId=${state.value.callId} status=${state.value.status}');
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
      _cpLog('END', '_lastEndedCallId set | callId=$_lastEndedCallId');
    }

    _setState(const CallState());
    _cpLog('END', 'reset() done → state=idle');
  }

  void _scheduleReset() {
    _resetTimer?.cancel();
    _cpLog('END', 'scheduleReset 2s scheduled | status=${state.value.status}');
    _resetTimer = Timer(const Duration(seconds: 2), reset);
  }

  bool get hasActiveCall =>
      state.value.status == CallStatus.calling ||
      state.value.status == CallStatus.ringing ||
      state.value.status == CallStatus.connecting ||
      state.value.status == CallStatus.connected ||
      state.value.status == CallStatus.reconnecting;
}
