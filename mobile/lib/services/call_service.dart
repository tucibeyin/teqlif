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
      // calling: zil çalınıyor, callee henüz cevaplamadı.
      // connecting: callee kabul etti ama TrackSubscribed henüz gelmedi.
      // Her iki durumda da ringtone devam etmeli — ses gerçekten akana dek.
      if (state.value.status == CallStatus.calling || state.value.status == CallStatus.connecting) {
        _cpLog('HW', 'audioPlayer RESTART | source=ringing.wav onComplete status=${state.value.status.name}');
        await _audioPlayer.play(ap.AssetSource('sounds/ringing.wav'));
      }
    });
    if (Platform.isIOS) {
      _initCallkitChannelHandler();
    }
  }
  static final CallService instance = CallService._();

  final ValueNotifier<CallState> state = ValueNotifier(const CallState());
  final isCallScreenVisible = ValueNotifier<bool>(false);
  final preventCallScreenAutoOpen = ValueNotifier<bool>(false);

  // Arama sayacı: CallState'ten bağımsız notifier — her saniye setState() tetiklemez.
  // CallScreen bu notifier'ı doğrudan dinler; overlay ve diğer listener'lar etkilenmez.
  final ValueNotifier<Duration> elapsed = ValueNotifier(Duration.zero);

  Room? _room;
  Function? _roomEventsSubscription;
  StreamSubscription<AudioInterruptionEvent>? _audioInterruptionSubscription;
  Timer? _ringTimer; // 30s no-answer timeout
  Timer? _elapsedTimer;
  Timer? _peerTimeoutTimer; // Timeout if other user doesn't join LiveKit room
  Timer? _ringtoneLoopTimer; // For iOS ringtone looping
  Timer? _resetTimer; // To prevent delayed reset overwriting new calls
  Timer? _callerStatusPollTimer; // Poll /status while in calling state (WS kayıp event recovery)

  bool _isHangingUp = false;   // Eş zamanlı _hangUpLocally çağrılarını önler
  bool _isJoiningRoom = false; // Çift _joinRoom çağrısını önler
  Completer<void>? _callkitAudioReady; // iOS: didActivateAudioSession sinyali

  // Race condition fix: didActivateAudioSession, _joinRoom'daki Completer'dan önce gelebilir.
  // VoIP push auto-accept senaryosunda bu kaçınılmaz: kullanıcı lock screen'den kabul eder,
  // action.fulfill() → didActivateAudioSession senkron ateşlenir, Flutter henüz hazır değildir.
  // Flag sayesinde sinyal kaybolmaz — _joinRoom Completer'ı bulunca anında tamamlar.
  bool _audioSessionActivated = false;

  // Pre-connect başlama zamanı — acceptCall'da kaç ms önce başladığını ölçer.
  DateTime? _preConnectStartedAt;

  static const _callkitChannel = MethodChannel('com.teqlif/callkit');

  // iOS: CallKit audio session aktive olduğunda native'den sinyal alır.
  void _initCallkitChannelHandler() {
    _callkitChannel.setMethodCallHandler((call) async {
      if (call.method == 'audioSessionActivated') {
        _cpLog('LK', 'audioSessionActivated received from CallKit native | completerReady=${_callkitAudioReady != null}');
        _audioSessionActivated = true; // Flag: sinyal erken gelse de kaybolmaz
        if (_callkitAudioReady != null && !_callkitAudioReady!.isCompleted) {
          _callkitAudioReady!.complete();
        }
      }
    });
  }

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
      _cpLog('HW', 'audioPlayer PLAY | source=weak.wav poorConnection=true');
      _cpLog('SOUND', 'weak.wav PLAY | poorConnection detected');
      _audioPlayer.setReleaseMode(ReleaseMode.release);
      _audioPlayer.play(AssetSource('sounds/weak.wav'));
    }
  }

  void _handleStatusChange(CallStatus oldStatus, CallStatus newStatus) {
    if (newStatus == CallStatus.calling) {
      AudioSession.instance.then((session) async {
        try {
          _cpLog('HW', 'audioSession CONFIGURE | context=ringtone category=playAndRecord mode=voiceChat androidUsage=notificationRingtone');
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
          _cpLog('HW', 'speakerphone SET | enabled=false context=ringtone-start');
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
          _cpLog('HW', 'audioSession CONFIGURE ERROR | context=ringtone $e');
          debugPrint('[LIVE_SCREEN_CALL] AudioSession prep error: $e');
        }

        _audioPlayer.setReleaseMode(ReleaseMode.loop);
        if (state.value.status == CallStatus.calling) {
          if (Platform.isIOS) {
            await Future.delayed(const Duration(milliseconds: 600));
          }
          if (state.value.status == CallStatus.calling) {
            _cpLog('HW', 'audioPlayer PLAY | source=ringing.wav mode=loop device=earpiece');
            _cpLog('SOUND', 'ringing.wav PLAY | mode=loop earpiece');
            _audioPlayer.play(AssetSource('sounds/ringing.wav'));
          }
        }
      });
    } else if (newStatus == CallStatus.busy || newStatus == CallStatus.rejected) {
      _cpLog('HW', 'audioPlayer PLAY | source=busy.wav mode=release reason=$newStatus');
      _cpLog('SOUND', 'busy.wav PLAY | reason=$newStatus');
      _audioPlayer.setReleaseMode(ReleaseMode.release);
      _audioPlayer.play(AssetSource('sounds/busy.wav'));
    } else if (newStatus == CallStatus.ended) {
      if (oldStatus == CallStatus.connected || oldStatus == CallStatus.connecting) {
        _cpLog('HW', 'audioPlayer PLAY | source=ended.wav mode=release wasConnected=true');
        _cpLog('SOUND', 'ended.wav PLAY | wasConnected=true');
        _audioPlayer.setReleaseMode(ReleaseMode.release);
        _audioPlayer.play(AssetSource('sounds/ended.wav'));
      } else {
        _cpLog('HW', 'audioPlayer STOP | reason=ended-without-connection');
        _cpLog('SOUND', 'audioPlayer.stop | ended without connection');
        _audioPlayer.stop();
      }
    } else if (newStatus == CallStatus.connected || newStatus == CallStatus.idle) {
      _cpLog('HW', 'audioPlayer STOP | reason=$newStatus');
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
      _cpLog('HW', 'wakelock ENABLE | reason=startCall status=calling');
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
    } catch (e) {
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
    _cpLog('OUT', 'callerStatusPoll started | interval=2s callId=$callId');
    _callerStatusPollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (state.value.status != CallStatus.calling) {
        _callerStatusPollTimer?.cancel();
        return;
      }
      try {
        final statusData = await _get('/calls/$callId/status');
        final s = statusData['status'] as String?;
        _cpLog('OUT', 'callerStatusPoll tick | callId=$callId backendStatus=$s status=${state.value.status}');
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
    final source = data['_source'] as String? ?? 'overlay/ws';
    _cpLog('IN', 'onIncomingCall received | source=$source callId=${data['call_id']} caller=${data['caller_username']} calleeToken=${data['callee_token'] != null ? "EXISTS" : "MISSING"} livekitUrl=${data['livekit_url'] != null ? "EXISTS" : "MISSING"} nowUtc=${DateTime.now().toUtc().toIso8601String()}');
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

    final calleeToken = data['callee_token'] as String?;
    final livekitUrl = data['livekit_url'] as String?;

    _setState(
      CallState(
        status: CallStatus.ringing,
        callId: incomingCallId,
        roomName: data['room_name'] as String?,
        livekitUrl: livekitUrl,
        calleeToken: calleeToken,
        otherUserId: data['caller_id'] is int
            ? data['caller_id']
            : int.tryParse(data['caller_id'].toString()),
        otherUsername: data['caller_username'] as String?,
        otherAvatar: data['caller_avatar'] as String?,
      ),
    );

    // VoIP push path: callee_token push payload'ında gelmez (JWT güvenlik).
    // Proaktif fetch ile kullanıcı kabul ettiğinde pre-connect hazır olur.
    if ((calleeToken == null || livekitUrl == null) && incomingCallId != null) {
      _cpLog('IN', 'calleeToken/livekitUrl missing — proactive fetch starting | callId=$incomingCallId');
      _fetchAndStoreCalleeToken(incomingCallId);
    }

    playNotification();
  }

  /// VoIP push path için callee LK token'ını arka planda çeker ve state'e yazar.
  /// Kullanıcı kabul ettiğinde pre-connect başlatılabilmesi için ringing sırasında çalışır.
  Future<void> _fetchAndStoreCalleeToken(int callId) async {
    final fetchStartAt = DateTime.now();
    _cpLog('IN', '_fetchCalleeToken start | callId=$callId fetchStartUtc=${fetchStartAt.toUtc().toIso8601String()}');
    try {
      final data = await _get('/calls/$callId/callee-token');
      final fetchEndAt = DateTime.now();
      final httpMs = fetchEndAt.difference(fetchStartAt).inMilliseconds;
      final token = data['token'] as String?;
      final url = data['livekit_url'] as String?;
      final room = data['room_name'] as String?;
      _cpLog('IN', '_fetchCalleeToken result | tokenLen=${token?.length} url=${url != null} room=$room httpMs=$httpMs');
      if (state.value.status == CallStatus.ringing && state.value.callId == callId) {
        _setState(state.value.copyWith(
          calleeToken: token,
          livekitUrl: url,
          roomName: room,
        ));
        _cpLog('IN', '_fetchCalleeToken stored → pre-connect ready | callId=$callId httpMs=$httpMs');

        // Callee Pre-Connect: Kullanıcı kabul etmeden önce LK ağ bağlantısını kur.
        // Mic/ses oturumu YOK — sadece TCP+TLS+ICE handshake.
        // Kullanıcı kabul edince _joinRoom atlanır, sadece mic etkinleştirilir.
        // Reddetme/timeout durumunda reset() → _disconnectRoom() temizler.
        if (_room == null && !_isJoiningRoom && token != null && url != null) {
          _preConnectStartedAt = DateTime.now();
          _cpLog('IN', 'callee pre-connect _joinRoom starting during ringing | callId=$callId preConnectStartUtc=${_preConnectStartedAt!.toUtc().toIso8601String()} fetchHttpMs=$httpMs');
          _joinRoom(livekitUrl: url, token: token).catchError((e) {
            _cpLog('IN', 'callee pre-connect _joinRoom ERROR | $e');
          });
        } else {
          _cpLog('IN', '_fetchCalleeToken: pre-connect _joinRoom SKIPPED | roomNull=${_room == null} isJoining=$_isJoiningRoom tokenOk=${token != null} urlOk=${url != null}');
        }
      } else {
        _cpLog('IN', '_fetchCalleeToken discarded (state changed) | callId=$callId status=${state.value.status.name}');
      }
    } catch (e) {
      _cpLog('IN', '_fetchCalleeToken FAILED (acceptCall response-token fallback will be used) | $e');
    }
  }

  /// Callee pre-connect sonrası audio session + mic aktivasyonu.
  /// Çağrıldığında _room bağlı olmalı; iOS'ta CallKit audio session sinyali beklenir.
  Future<void> _activateCalleeAudio() async {
    final activateStartAt = DateTime.now();
    _cpLog('IN', '_activateCalleeAudio START | status=${state.value.status} audioSessionActivated=$_audioSessionActivated startUtc=${activateStartAt.toUtc().toIso8601String()}');

    if (Platform.isIOS) {
      if (_audioSessionActivated) {
        _cpLog('IN', '_activateCalleeAudio: audioSessionActivated flag=true → no wait | waitMs=0');
        _cpLog('HW', 'audioSessionActivated SKIPPED WAIT | flag=true already received');
      } else {
        _callkitAudioReady ??= Completer<void>();
        final waitStartAt = DateTime.now();
        _cpLog('IN', '_activateCalleeAudio: waiting for didActivateAudioSession (max 4s) | waitStartUtc=${waitStartAt.toUtc().toIso8601String()}');
        _cpLog('HW', 'didActivateAudioSession WAITING | callkitAudioReady created maxWait=4s');
        await _callkitAudioReady!.future.timeout(
          const Duration(seconds: 4),
          onTimeout: () {
            final waitMs = DateTime.now().difference(waitStartAt).inMilliseconds;
            _cpLog('IN', '_activateCalleeAudio: audioSessionActivated TIMEOUT after ${waitMs}ms → proceeding');
            _cpLog('HW', 'didActivateAudioSession TIMEOUT | waitMs=$waitMs → proceeding without signal');
          },
        );
        final waitMs = DateTime.now().difference(waitStartAt).inMilliseconds;
        _cpLog('IN', '_activateCalleeAudio: audioSessionActivated received | waitMs=$waitMs');
        _cpLog('HW', 'didActivateAudioSession RECEIVED | waitMs=$waitMs');
        _callkitAudioReady = null;
      }
    } else if (Platform.isAndroid && state.value.callId != null) {
      final uuid = _formatToUuid(state.value.callId!.toString());
      _cpLog('IN', '_activateCalleeAudio: Android setCallConnected | uuid=$uuid');
      FlutterCallkitIncoming.setCallConnected(uuid).catchError((e) {
        _cpLog('IN', '_activateCalleeAudio setCallConnected ERROR | $e');
      });
      await Future.delayed(const Duration(milliseconds: 200));
    }

    try {
      _cpLog('IN', '_activateCalleeAudio: AudioSession configure voiceChat');
      _cpLog('HW', 'audioSession CONFIGURE | context=_activateCalleeAudio category=playAndRecord mode=voiceChat');
      final session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionMode: AVAudioSessionMode.voiceChat,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.allowBluetooth |
            AVAudioSessionCategoryOptions.allowBluetoothA2dp,
      ));
      _cpLog('HW', 'speakerphone SET | enabled=false context=_activateCalleeAudio-post-configure');
      await Hardware.instance.setSpeakerphoneOn(false);
      _cpLog('IN', '_activateCalleeAudio: AudioSession configure OK');
    } catch (e) {
      _cpLog('IN', '_activateCalleeAudio: AudioSession configure ERROR | $e');
    }

    _cpLog('IN', '_activateCalleeAudio: setMicrophoneEnabled(true)');
    _cpLog('HW', 'microphone ENABLE | context=_activateCalleeAudio');
    await _room?.localParticipant?.setMicrophoneEnabled(true);
    await Future.delayed(const Duration(milliseconds: 300));
    _cpLog('HW', 'speakerphone SET | enabled=false context=_activateCalleeAudio-post-mic');
    await Hardware.instance.setSpeakerphoneOn(false);
    final totalMs = DateTime.now().difference(activateStartAt).inMilliseconds;
    _cpLog('IN', '_activateCalleeAudio DONE | totalMs=$totalMs');
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

      _cpLog('HW', 'ringtonePlayer PLAY | platform=${defaultTargetPlatform.name} looping=true context=incoming-call');
      _cpLog('SOUND', 'ringtone PLAY | platform=${defaultTargetPlatform.name} looping=true');
      FlutterRingtonePlayer().playRingtone(looping: true);

      if (defaultTargetPlatform == TargetPlatform.iOS) {
        _ringtoneLoopTimer?.cancel();
        _cpLog('HW', 'ringtoneLoopTimer START | interval=3s platform=iOS');
        _cpLog('SOUND', 'iOS ringtoneLoopTimer started | interval=3s');
        _ringtoneLoopTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
          _cpLog('HW', 'ringtonePlayer PLAY | platform=iOS loopTick');
          FlutterRingtonePlayer().playRingtone();
        });

        _hapticLoopTimer?.cancel();
        _cpLog('HW', 'hapticLoopTimer START | interval=2s platform=iOS');
        _hapticLoopTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
          if (await Vibration.hasVibrator() == true) {
            _cpLog('HW', 'haptic VIBRATE | platform=iOS loopTick');
            Vibration.vibrate();
          }
        });
      }

      if (await Vibration.hasVibrator() == true && defaultTargetPlatform != TargetPlatform.iOS) {
        _cpLog('HW', 'haptic VIBRATE | pattern=[2000,500,2000,500] repeat=0 platform=Android');
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
    _cpLog('HW', 'ringtonePlayer STOP | context=stopRingtoneAndVibration');
    FlutterRingtonePlayer().stop();
    _cpLog('HW', 'haptic CANCEL | context=stopRingtoneAndVibration');
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

    // Snapshot token/url — may be set by _fetchAndStoreCalleeToken (proactive fetch)
    final preConnectUrl = state.value.livekitUrl;
    final preConnectToken = state.value.calleeToken;

    final preConnectAgeMs = _preConnectStartedAt != null
        ? DateTime.now().difference(_preConnectStartedAt!).inMilliseconds
        : -1;
    _cpLog(
      'IN',
      'acceptCall pre-connect check | roomReady=${_room != null} isJoining=$_isJoiningRoom '
      'tokenReady=${preConnectToken != null} urlReady=${preConnectUrl != null} '
      'preConnectAgeMs=$preConnectAgeMs nowUtc=${DateTime.now().toUtc().toIso8601String()}',
    );

    if (_room != null) {
      // _fetchAndStoreCalleeToken pre-connect tamamlandı → sadece audio aktive et.
      // Bu yol: callee pre-connect ÇALIŞIYOR (WhatsApp kalitesi).
      _cpLog('IN', 'acceptCall: callee pre-connect ROOM READY → _activateCalleeAudio | preConnectAgeMs=$preConnectAgeMs');
      _activateCalleeAudio().catchError((e) {
        _cpLog('IN', 'acceptCall _activateCalleeAudio ERROR | $e');
      });
    } else if (_isJoiningRoom) {
      // Pre-connect room.connect() devam ediyor.
      // _joinRoom else bloğu status=connecting + callStatusAtEntry=ringing detektörü devralacak.
      _cpLog('IN', 'acceptCall: callee pre-connect IN PROGRESS (_joinRoom running) → _activateCalleeAudio deferred | preConnectAgeMs=$preConnectAgeMs');
    } else if (preConnectUrl != null && preConnectToken != null) {
      // Token hazır ama _joinRoom henüz başlamadı → callee rolüyle başlat.
      // Bu yol: token fetch tamam ama pre-connect başlatılamamış (edge case).
      _cpLog('IN', 'acceptCall: token ready, room NULL → _joinRoom now (isCallee=true) | preConnectAgeMs=$preConnectAgeMs');
      _joinRoom(livekitUrl: preConnectUrl, token: preConnectToken).catchError((e) {
        _cpLog('IN', 'acceptCall _joinRoom (callee token) ERROR | $e');
      });
    } else {
      // Pre-connect hiç başlamamış — FALLBACK: /accept response token kullanılacak.
      // Bu yol: CallEventActionCallIncoming handle edilmemişse veya token fetch başarısızsa.
      _cpLog('IN', 'acceptCall: NO pre-connect (room=null, isJoining=false, token=${preConnectToken != null}) → FALLBACK to /accept response token');
    }

    _cpLog('IN', 'POST /calls/$callId/accept → request (retry max=4)');
    try {
      Map<String, dynamic>? data;
      int retryCount = 0;
      while (retryCount < 4) {
        try {
          _cpLog('IN', 'POST /calls/$callId/accept attempt=${retryCount + 1}');
          data = await _post('/calls/$callId/accept');
          _cpLog('IN', 'POST /calls/$callId/accept SUCCESS | acceptedAt=${data['accepted_at']} tokenLen=${(data['token'] as String?)?.length}');
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
        final parsedAt = DateTime.parse(data['accepted_at']);
        final nowUtc = DateTime.now().toUtc();
        _cpLog('TIMER', 'acceptedAt SET [CALLEE/accept-response] | acceptedAt=${parsedAt.toIso8601String()} nowUtc=${nowUtc.toIso8601String()} httpRTT=${nowUtc.difference(parsedAt).inMilliseconds}ms');
        _setState(state.value.copyWith(acceptedAt: parsedAt));
      } else {
        _cpLog('TIMER', 'acceptedAt MISSING in /accept response — timer will use local clock');
      }

      // FALLBACK: hiç pre-connect başlamadıysa response token ile LiveKit'e bağlan.
      if (_room == null && !_isJoiningRoom) {
        final responseToken = data['token'] as String?;
        final responseLkUrl = (data['livekit_url'] as String?) ?? preConnectUrl;
        _cpLog('IN', 'acceptCall FALLBACK: _joinRoom with RESPONSE token | tokenLen=${responseToken?.length} url=$responseLkUrl');
        if (responseToken != null && responseLkUrl != null) {
          _joinRoom(livekitUrl: responseLkUrl, token: responseToken).catchError((e) {
            _cpLog('IN', 'acceptCall _joinRoom (response token) ERROR | $e');
          });
        } else {
          _cpLog('IN', 'acceptCall: response token/url null — cannot join LiveKit');
          _hangUpLocally(status: CallStatus.ended);
        }
      }
    } catch (e) {
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
    // Ringtone intentionally NOT stopped here.
    // ringing.wav (_audioPlayer) TrackSubscribed event'te durur — ses gerçekten
    // akmaya başladığında. Bu sayede "zil → sessizlik → ses" yerine
    // "zil → ses" geçişi olur (WhatsApp pattern).

    // Guard: zaten connecting/connected → mükerrer çağrı, dön.
    if (state.value.status == CallStatus.connecting || state.value.status == CallStatus.connected) {
      _cpLog('OUT', 'call_accepted SKIPPED (already ${state.value.status.name})');
      return;
    }

    _resetTimer?.cancel();

    // acceptedAt ve status=connecting tek setState'te — ara calling→calling paraziti kalkar.
    if (data['accepted_at'] != null) {
      final parsedAt = DateTime.parse(data['accepted_at']);
      final nowUtc = DateTime.now().toUtc();
      _cpLog('TIMER', 'acceptedAt SET [CALLER/WS] | acceptedAt=${parsedAt.toIso8601String()} nowUtc=${nowUtc.toIso8601String()} wsLag=${nowUtc.difference(parsedAt).inMilliseconds}ms');
      _setState(state.value.copyWith(acceptedAt: parsedAt, status: CallStatus.connecting));
    } else {
      _cpLog('TIMER', 'acceptedAt MISSING in call_accepted WS payload — timer will use local clock');
      _setState(state.value.copyWith(status: CallStatus.connecting));
    }

    // Caller mikrofon aktivasyonu: iki yol
    // FAST PATH: Pre-connect'te muted track yayınlandıysa → sadece unmute (~50ms, re-negotiation yok).
    // STANDARD PATH: Pre-publish başarısızsa → setMicrophoneEnabled(true) (1.5s).
    if (_room != null) {
      final micPubs = _room!.localParticipant?.audioTrackPublications;
      if (micPubs != null && micPubs.isNotEmpty) {
        final pub = micPubs.first;
        if (pub.muted) {
          _cpLog('OUT', 'call_accepted → FAST PATH: unmuting pre-published track | pubSid=${pub.sid}');
          _cpLog('HW', 'microphone UNMUTE | context=onCallAccepted-caller fastPath=true stopOnMute=false prePublishedTrack audioCapture=wasAlreadyActive');
          // stopOnMute:false → capture zaten çalışıyor, sadece RTP akışı başlıyor.
          pub.unmute(stopOnMute: false).catchError((e) {
            _cpLog('OUT', 'caller mic unmute ERROR | $e → fallback to setMicEnabled');
            _cpLog('HW', 'microphone ENABLE (unmute-fallback) | context=onCallAccepted-caller');
            _room!.localParticipant?.setMicrophoneEnabled(true);
            return null;
          });
        } else {
          _cpLog('OUT', 'call_accepted → mic already published+unmuted | no action needed');
          _cpLog('HW', 'microphone ALREADY ENABLED+UNMUTED | context=onCallAccepted-caller pubSid=${pub.sid}');
        }
      } else {
        // Pre-publish başarısız veya hiç yayınlanmadı → standart yol
        _cpLog('OUT', 'call_accepted → STANDARD PATH: setMicrophoneEnabled (no pre-publish) | AudioSession deferred to TrackSubscribed');
        _cpLog('HW', 'microphone ENABLE | context=onCallAccepted-caller standardPath=true audioSessionDeferred=true');
        _room!.localParticipant?.setMicrophoneEnabled(true).catchError((e) {
          _cpLog('OUT', 'caller mic enable ERROR | $e');
          return null;
        });
      }
    } else {
      _cpLog('OUT', 'call_accepted: _room is null — mic will be enabled when _joinRoom completes');
    }
  }

  void onCallRejected() async {
    if (state.value.status == CallStatus.rejected) return;
    stopRingtoneAndVibration();
    _ringTimer?.cancel();
    _setState(state.value.copyWith(status: CallStatus.rejected));
    if (await Vibration.hasVibrator() == true) {
      _cpLog('HW', 'haptic VIBRATE | pattern=[200,100,200,100,200] reason=rejected');
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
      _cpLog('HW', 'haptic VIBRATE | pattern=[200,100,200] reason=missed');
      Vibration.vibrate(pattern: [200, 100, 200]);
    }
    _scheduleReset();
  }

  // ── LiveKit Room ──────────────────────────────────────────────────────────

  Future<void> _joinRoom({
    required String livekitUrl,
    required String token,
  }) async {
    if (_isJoiningRoom) {
      _cpLog('LK', '_joinRoom SKIPPED — already joining (double call guard)');
      return;
    }
    _isJoiningRoom = true;
    _room = Room();

    // callStatus'u snapshot alıyoruz — async boyunca değişebilir
    final callStatusAtEntry = state.value.status;
    final isCalleeRole = callStatusAtEntry == CallStatus.connecting;

    try {
      _cpLog('LK', '_joinRoom starting | url=$livekitUrl tokenLen=${token.length} status=$callStatusAtEntry isCallee=$isCalleeRole');

      // ── iOS Callee: didActivateAudioSession sinyali bekle ───────────────────
      // action.fulfill() AppDelegate.onAccept'te anında çağrılır.
      // fulfill() → CallKit → provider(_:didActivate:) → didActivateAudioSession → Flutter signal.
      //
      // Race condition: VoIP push auto-accept senaryosunda kullanıcı lock screen'den kabul eder.
      // didActivateAudioSession bu kodu çalışmadan önce ateşlenir (717ms önce, log'dan).
      // Çözüm: _audioSessionActivated flag'i. Sinyal erken geldiyse Completer'ı anında tamamla.
      if (Platform.isIOS && isCalleeRole) {
        _callkitAudioReady = Completer<void>();
        if (_audioSessionActivated) {
          _callkitAudioReady!.complete();
          _cpLog('LK', 'iOS callee: audioSessionActivated already received (early signal, flag=true) — no wait');
        } else {
          _cpLog('LK', 'iOS callee: waiting for didActivateAudioSession signal from CallKit');
        }
        // Android callee: setCallConnected (audio session yok, direkt çalışır)
      } else if (Platform.isAndroid && isCalleeRole && state.value.callId != null) {
        final uuid = _formatToUuid(state.value.callId!.toString());
        _cpLog('LK', 'Android callee: setCallConnected | uuid=$uuid');
        FlutterCallkitIncoming.setCallConnected(uuid).catchError((e) {
          _cpLog('LK', 'setCallConnected ERROR | $e');
        });
        // Android'de audio session yok — kısa bekleme yeterli
        await Future.delayed(const Duration(milliseconds: 200));
      }

      // ── Ağ bağlantısı (audio session gerektirmez) ────────────────────────────
      _cpLog('LK', 'room.connect() → calling LiveKit');
      await _room!.connect(livekitUrl, token, roomOptions: const RoomOptions(defaultAudioOutputOptions: AudioOutputOptions(speakerOn: false)));
      _cpLog('LK', 'room.connect() SUCCESS');

      // ── iOS Callee: audio session aktive olana kadar bekle ───────────────────
      if (Platform.isIOS && isCalleeRole && _callkitAudioReady != null) {
        _cpLog('LK', 'iOS callee: waiting for audioSessionActivated (max 4s)');
        await _callkitAudioReady!.future.timeout(
          const Duration(seconds: 4),
          onTimeout: () {
            _cpLog('LK', 'audioSessionActivated TIMEOUT — CallKit may not have activated audio. Proceeding anyway.');
          },
        );
        _callkitAudioReady = null;
      }

      // ── Audio session + mic: Rol bazlı aktivasyon ─────────────────────────────
      // CALLEE: LK bağlantısından sonra hemen ses oturumunu yapılandır ve miki aç.
      // CALLER pre-connect: ATLA — ringtone ses oturumu aktifken voice-chat ayarı
      //   onu keser. Mikrofon ve ses oturumu, callee kabul ettikten sonra
      //   onCallAccepted() içinde etkinleştirilir.
      if (isCalleeRole) {
        try {
          _cpLog('LK', 'AudioSession configure | role=callee category=playAndRecord mode=voiceChat');
          _cpLog('HW', 'audioSession CONFIGURE | context=_joinRoom-callee category=playAndRecord mode=voiceChat');
          final session = await AudioSession.instance;
          await session.configure(AudioSessionConfiguration(
            avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
            avAudioSessionMode: AVAudioSessionMode.voiceChat,
            avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.allowBluetooth | AVAudioSessionCategoryOptions.allowBluetoothA2dp,
          ));
          _cpLog('HW', 'speakerphone SET | enabled=false context=_joinRoom-callee-post-configure');
          await Hardware.instance.setSpeakerphoneOn(false);
          _cpLog('LK', 'AudioSession configure OK | role=callee');
        } catch (e) {
          _cpLog('LK', 'AudioSession configure ERROR | role=callee $e');
        }
        _cpLog('LK', 'setMicrophoneEnabled(true) calling | role=callee');
        _cpLog('HW', 'microphone ENABLE | context=_joinRoom-callee');
        await _room!.localParticipant?.setMicrophoneEnabled(true);
        _cpLog('LK', 'setMicrophoneEnabled(true) done | role=callee');
        await Future.delayed(const Duration(milliseconds: 300));
        _cpLog('HW', 'speakerphone SET | enabled=false context=_joinRoom-callee-post-mic');
        await Hardware.instance.setSpeakerphoneOn(false);
      } else {
        // Network-only pre-connect (caller=calling veya callee=ringing): standart ses atlandı.
        // callStatusAtEntry: caller=calling, callee-pre-connect=ringing

        if (callStatusAtEntry == CallStatus.calling) {
          // WhatsApp-kalitesi FAST PATH:
          // AudioSession zaten playAndRecord+voiceChat modunda (ringtone için ayarlandı).
          // setMicrophoneEnabled(true) → WebRTC müzakeresi tamamlanır → pub.mute(stopOnMute:false) → RTP sessiz.
          // stopOnMute:false önemli: mikrofon capture'ı durmaz, sadece RTP paketleri gönderilmez.
          // Acceptance gelince pub.unmute(stopOnMute:false) ~50ms — re-start yok, re-negotiation yok.
          _cpLog('LK', 'caller pre-connect: pre-publishing MUTED audio track for fast acceptance | callId=${state.value.callId}');
          _cpLog('HW', 'microphone CAPTURE START (muted pre-connect) | audioCapture=active rtpTransmission=paused stopOnMute=false ringtone=preserved');
          try {
            await _room!.localParticipant?.setMicrophoneEnabled(true);
            final micPubs = _room!.localParticipant?.audioTrackPublications;
            if (micPubs != null && micPubs.isNotEmpty) {
              final pub = micPubs.first;
              // stopOnMute:false → capture çalışır, RTP paketleri gönderilmez.
              await pub.mute(stopOnMute: false);
              _cpLog('LK', 'muted audio track pre-published | sid=${pub.sid} muted=${pub.muted} waiting for call_accepted to unmute');
              _cpLog('HW', 'microphone MUTED (pre-connect) | track=published rtpMuted=true audioCapture=active stopOnMute=false');
            } else {
              _cpLog('LK', 'pre-publish muted track: no publications after setMicEnabled (micPubs empty) | standard path on acceptance');
            }
          } catch (e) {
            _cpLog('LK', 'pre-publish muted track ERROR | $e → standard setMicEnabled path will be used on acceptance');
            _cpLog('HW', 'microphone CAPTURE (muted pre-connect) FAILED | fallback=standard on acceptance');
          }
        } else {
          // callee pre-connect (ringing): ringtone korunuyor, mic yok
          _cpLog('LK', 'AudioSession/mic SKIPPED | preConnectRole=${callStatusAtEntry.name} (ringtone preserved)');
        }

        // Kenar durum: accept/onCallAccepted bu room.connect() sırasında tetiklendiyse.
        if (state.value.status == CallStatus.connecting) {
          if (callStatusAtEntry == CallStatus.ringing) {
            // Callee pre-connect: acceptCall, room.connect() sırasında geldi.
            // _activateCalleeAudio iOS audio session + mic'i doğru sırayla açar.
            _cpLog('LK', 'callee pre-connect: accept fired during room.connect() → _activateCalleeAudio');
            _activateCalleeAudio().catchError((e) {
              _cpLog('LK', '_activateCalleeAudio ERROR (pre-connect edge case) | $e');
            });
          } else {
            // Caller: onCallAccepted, room.connect() sırasında geldi.
            // Muted track zaten yayınlandı — sadece unmute et.
            _cpLog('LK', 'caller: call_accepted already received during pre-connect → unmuting pre-published track');
            final micPubs = _room!.localParticipant?.audioTrackPublications;
            if (micPubs != null && micPubs.isNotEmpty) {
              final pub = micPubs.first;
              if (pub.muted) {
                _cpLog('HW', 'microphone UNMUTE | context=_joinRoom-caller-late-accept fastPath=true stopOnMute=false');
                await pub.unmute(stopOnMute: false);
                _cpLog('LK', 'caller mic unmuted (late-accept-during-preconnect) | done');
              } else {
                _cpLog('LK', 'caller: pre-published track already unmuted | done');
              }
            } else {
              // Pre-publish çalışmadıysa standard yol
              _cpLog('LK', 'caller late-accept: no pre-published track → standard setMicEnabled');
              _cpLog('HW', 'microphone ENABLE | context=_joinRoom-caller-late-accept standardPath=true');
              await _room!.localParticipant?.setMicrophoneEnabled(true);
              _cpLog('LK', 'caller mic enabled (late, accepted-during-preconnect, standard) | done');
            }
          }
        }
      }

      _roomEventsSubscription = _room!.events.listen(_onRoomEvent);

      bool peerAlreadyJoined = _room!.remoteParticipants.isNotEmpty;
      _cpLog('LK', 'peerAlreadyJoined=$peerAlreadyJoined status=${state.value.status.name}');
      if (peerAlreadyJoined) {
        _peerTimeoutTimer?.cancel();
        // Callee pre-connect sırasında (ringing) arayan oda da olabilir.
        // Kullanıcı kabul etmeden connected set etme.
        if (state.value.status == CallStatus.ringing) {
          _cpLog('LK', 'peerAlreadyJoined during callee pre-connect (ringing) → waiting for acceptCall');
        } else {
          // Peer odada ama ses track'ı henüz subscribe edilmemiş olabilir.
          // connected state'i TrackSubscribed'da set edilecek — gerçek ses akışını bekle.
          final anyAudioSubscribed = _room!.remoteParticipants.values.any(
            (p) => p.trackPublications.values.any(
              (pub) => pub.subscribed && pub.kind == TrackType.AUDIO,
            ),
          );
          if (anyAudioSubscribed) {
            _cpLog('LK', 'peerAlreadyJoined + audioSubscribed → connected immediately');
            final nowUtc = DateTime.now().toUtc();
            final acceptedAt = state.value.acceptedAt;
            final audioLag = acceptedAt != null ? nowUtc.difference(acceptedAt.toUtc()).inMilliseconds : -1;
            _cpLog('TIMER', 'peerAlreadyJoined → CONNECTED | acceptedAt=${acceptedAt?.toIso8601String() ?? "NULL"} nowUtc=${nowUtc.toIso8601String()} acceptToAudioMs=$audioLag');
            stopRingtoneAndVibration();
            _setState(state.value.copyWith(status: CallStatus.connected));
            _startElapsedTimer();
          } else {
            _cpLog('LK', 'peerAlreadyJoined but audio not yet subscribed → waiting for TrackSubscribed');
          }
        }
      } else {
        _cpLog('LK', 'joined LiveKit → waiting for peer (ParticipantConnectedEvent)');
        _peerTimeoutTimer?.cancel();
        // Callee pre-connect sırasında (ringing) peer timeout başlatma.
        // Kullanıcı reddetse zaten reset() timeout'u iptal eder; gereksiz endCall riski var.
        if (state.value.status != CallStatus.ringing) {
          _cpLog('LK', 'peerTimeoutTimer started | 25s');
          _peerTimeoutTimer = Timer(const Duration(seconds: 25), () {
            if (_room != null && _room!.remoteParticipants.isEmpty) {
              _cpLog('LK', 'peerTimeoutTimer FIRED → peer did not join in 25s → endCall | status=${state.value.status}');
              endCall();
            }
          });
        } else {
          _cpLog('LK', 'peerTimeoutTimer SKIPPED during callee pre-connect (ringing)');
        }
      }

      _cpLog('HW', 'wakelock ENABLE | reason=_joinRoom-complete status=${state.value.status.name}');
      await WakelockPlus.enable();

      _isJoiningRoom = false;
      _cpLog('LK', '_joinRoom complete | _isJoiningRoom reset');
      await _setupAudioInterruptionListener();
    } catch (e) {
      _cpLog('LK', '_joinRoom EXCEPTION | $e');
      _isJoiningRoom = false;
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
      _cpLog('LK', 'ParticipantConnected → peer joined | peerCount=${_room?.remoteParticipants.length} status=${state.value.status.name}');
      _peerTimeoutTimer?.cancel();
      // Mic sadece connecting state'inde açılır — kabul sonrası ses aktivasyon aşaması.
      // calling: caller pre-connect (kabul bekleniyor) → mic kapalı kalmalı.
      // ringing: callee pre-connect (kullanıcı henüz kabul etmedi) → mic kapalı kalmalı.
      // connecting: call_accepted geldi, ses aktivasyonu başladı → mic açılabilir.
      // connected: mic zaten açık, tekrar açmaya gerek yok.
      if (state.value.status == CallStatus.connecting) {
        final micPubs = _room?.localParticipant?.audioTrackPublications;
        if (micPubs == null || micPubs.isEmpty) {
          _cpLog('LK', 'ParticipantConnected: mic not yet published → enabling now');
          _cpLog('HW', 'microphone ENABLE | context=ParticipantConnected-mic-not-published status=connecting');
          _room?.localParticipant?.setMicrophoneEnabled(true);
        } else {
          _cpLog('HW', 'microphone ALREADY ENABLED | context=ParticipantConnected pubCount=${micPubs.length}');
        }
      } else {
        _cpLog('LK', 'ParticipantConnected: mic enable SKIPPED | status=${state.value.status.name} (pre-connect guard)');
        _cpLog('HW', 'microphone ENABLE SKIPPED | context=ParticipantConnected status=${state.value.status.name}');
      }
    } else if (event is TrackSubscribedEvent) {
      // Uzak ses track'ı abone oldu → callee'nin sesi gerçekten akıyor.
      // 1. AudioSession → voice-chat mode (ringtone session'dan geçiş)
      // 2. Ringtone durdur
      // 3. connected state → _handleStatusChange stops _audioPlayer (ringing.wav)
      _cpLog('LK', 'TrackSubscribed | kind=${event.track.kind}');
      if (event.track.kind == TrackType.AUDIO) {
        _cpLog('LK', 'TrackSubscribed AUDIO → voice AudioSession → ringing stop → connected');
        // AudioSession'ı ses akışı başlamadan hemen önce voice-chat moduna geçir.
        // iOS: speakerphone AudioSession sonrası set edilir (async callback).
        // Android: speakerphone aşağıdaki senkron blokta hemen set edilir — callback'te tekrar edilmez.
        AudioSession.instance.then((session) async {
          try {
            _cpLog('HW', 'audioSession CONFIGURE | context=TrackSubscribed category=playAndRecord mode=voiceChat');
            await session.configure(AudioSessionConfiguration(
              avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
              avAudioSessionMode: AVAudioSessionMode.voiceChat,
              avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.allowBluetooth | AVAudioSessionCategoryOptions.allowBluetoothA2dp,
            ));
            if (Platform.isIOS) {
              _cpLog('HW', 'speakerphone SET | enabled=false context=TrackSubscribed-post-configure platform=iOS');
              await Hardware.instance.setSpeakerphoneOn(false);
            }
            _cpLog('LK', 'TrackSubscribed: AudioSession voice configure OK');
          } catch (e) {
            _cpLog('LK', 'TrackSubscribed: AudioSession configure ERROR | $e');
          }
        });
        stopRingtoneAndVibration();
        if (state.value.status == CallStatus.calling || state.value.status == CallStatus.connecting) {
          final nowUtc = DateTime.now().toUtc();
          final acceptedAt = state.value.acceptedAt;
          final audioLag = acceptedAt != null ? nowUtc.difference(acceptedAt.toUtc()).inMilliseconds : -1;
          _cpLog('TIMER', 'TrackSubscribed → CONNECTED | role=${state.value.status.name} acceptedAt=${acceptedAt?.toIso8601String() ?? "NULL"} nowUtc=${nowUtc.toIso8601String()} acceptToAudioMs=$audioLag');
          _setState(state.value.copyWith(status: CallStatus.connected));
          _startElapsedTimer();
        }
        if (Platform.isAndroid) {
          _cpLog('HW', 'speakerphone SET | enabled=false context=TrackSubscribed-Android isSpeaker=false');
          Hardware.instance.setSpeakerphoneOn(false);
          _setState(state.value.copyWith(isSpeaker: false));
        }
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
        if (!state.value.isMuted) {
          _cpLog('HW', 'microphone DISABLE | context=audioInterruption-begin isMuted=false→true');
          _room?.localParticipant?.setMicrophoneEnabled(false);
          _setState(state.value.copyWith(isMuted: true));
        }
      } else {
        if (state.value.isMuted) {
          _cpLog('HW', 'microphone ENABLE | context=audioInterruption-end isMuted=true→false');
          _room?.localParticipant?.setMicrophoneEnabled(true);
          _setState(state.value.copyWith(isMuted: false));
        }
      }
    });
  }

  void _startElapsedTimer() {
    _elapsedTimer?.cancel();
    final acceptedAt = state.value.acceptedAt;
    final nowUtc = DateTime.now().toUtc();
    final alreadyElapsed = acceptedAt != null ? nowUtc.difference(acceptedAt.toUtc()) : Duration.zero;
    _cpLog('TIMER', '_startElapsedTimer CALLED | acceptedAt=${acceptedAt?.toIso8601String() ?? "NULL"} nowUtc=${nowUtc.toIso8601String()} alreadyElapsed=${alreadyElapsed.inMilliseconds}ms status=${state.value.status.name}');

    // İlk frame'de doğru elapsed göster — "00:00 flash → 00:04 jump" önlenir.
    // elapsed ValueNotifier ile güncellenir — _setState çağırılmaz, listener paraziti olmaz.
    if (alreadyElapsed.inMilliseconds > 0) {
      final fmt = '${alreadyElapsed.inMinutes.remainder(60).toString().padLeft(2, "0")}:${alreadyElapsed.inSeconds.remainder(60).toString().padLeft(2, "0")}';
      _cpLog('TIMER', '_startElapsedTimer: immediate elapsed sync | alreadyElapsed=${alreadyElapsed.inMilliseconds}ms → UI gösterir: $fmt');
      elapsed.value = alreadyElapsed;
    }

    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.value.status == CallStatus.connected) {
        final Duration newElapsed;
        if (state.value.acceptedAt != null) {
          newElapsed = DateTime.now().toUtc().difference(state.value.acceptedAt!.toUtc());
          if (newElapsed.inSeconds <= 5) {
            _cpLog('TIMER', 'tick [acceptedAt] | elapsed=${newElapsed.inMilliseconds}ms (${newElapsed.inSeconds}s) acceptedAt=${state.value.acceptedAt?.toIso8601String()}');
          }
        } else {
          newElapsed = elapsed.value + const Duration(seconds: 1);
          if (newElapsed.inSeconds <= 5) {
            _cpLog('TIMER', 'tick [localClock] | elapsed=${newElapsed.inSeconds}s (no acceptedAt)');
          }
        }
        // ValueNotifier.value güncelle — _setState DEĞİL.
        // Bu sayede overlay._onCallState ve CallScreen._onStateChange saniyede tetiklenmez.
        elapsed.value = newElapsed;
      }
    });
  }

  // ── Active Call Controls ──────────────────────────────────────────────────

  Future<void> toggleMute() async {
    final muted = !state.value.isMuted;
    _cpLog('UI', 'toggleMute | newMuted=$muted');
    _cpLog('HW', 'microphone ${muted ? "DISABLE" : "ENABLE"} | context=toggleMute userAction=true');
    await _room?.localParticipant?.setMicrophoneEnabled(!muted);
    _setState(state.value.copyWith(isMuted: muted));
  }

  Future<void> setSpeaker(bool enabled) async {
    _cpLog('UI', 'setSpeaker | enabled=$enabled');
    _cpLog('HW', 'speakerphone SET | enabled=$enabled context=setSpeaker userAction=true');
    try {
      await Hardware.instance.setSpeakerphoneOn(enabled);
    } catch (e) {
      _cpLog('UI', 'setSpeaker ERROR | $e');
      _cpLog('HW', 'speakerphone SET ERROR | enabled=$enabled $e');
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
      _post('/calls/$callId/end').catchError((e) {
        _cpLog('END', 'POST /calls/$callId/end retry | $e');
        Future.delayed(const Duration(milliseconds: 500)).then((_) {
          _post('/calls/$callId/end').catchError((e2) {
            _cpLog('END', 'POST /calls/$callId/end retry2 FAILED | $e2');
            return <String, dynamic>{};
          });
        });
        return <String, dynamic>{};
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

      // Arama süresi logu — analytics ve gözlem için.
      final callDurationMs = state.value.acceptedAt != null
          ? DateTime.now().toUtc().difference(state.value.acceptedAt!.toUtc()).inMilliseconds
          : -1;
      _cpLog('END', 'call DURATION | callId=${state.value.callId} acceptedAt=${state.value.acceptedAt?.toIso8601String() ?? "NULL"} durationMs=$callDurationMs durationSec=${callDurationMs > 0 ? callDurationMs ~/ 1000 : -1}');
      
      _cpLog('END', 'disconnectRoom starting');
      await _disconnectRoom();
      _cpLog('END', 'disconnectRoom done');
      _cpLog('HW', 'wakelock DISABLE | context=_hangUpLocally');
      WakelockPlus.disable();

      _cpLog('END', 'CallKit.endCall | callId=${state.value.callId}');
      if (state.value.callId != null) {
        await FlutterCallkitIncoming.endCall(_formatToUuid(state.value.callId.toString()));
      }
      await FlutterCallkitIncoming.endAllCalls();

      // CallKit ve LiveKit kapandıktan sonra global ses oturumunu hoparlöre yönlendir.
      try {
        _cpLog('HW', 'speakerphone SET | enabled=true context=_hangUpLocally-post-callkit');
        await Hardware.instance.setSpeakerphoneOn(true);
      } catch (e) {
        _cpLog('HW', 'speakerphone SET ERROR | context=_hangUpLocally $e');
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

    _isJoiningRoom = false;
    if (_room != null) {
      _cpLog('LK', 'room.disconnect() calling');
      await _room!.disconnect();
      _cpLog('LK', 'room.disconnect() done → dispose()');
      await _room!.dispose();
      _room = null;
      _cpLog('LK', 'room disposed | _room=null _isJoiningRoom=false');
    } else {
      _cpLog('LK', '_disconnectRoom: room was already null | _isJoiningRoom=false');
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
    _cpLog('HW', 'wakelock DISABLE | context=reset');
    WakelockPlus.disable();
    FlutterCallkitIncoming.endAllCalls();
    _audioSessionActivated = false; // Sonraki çağrı için iOS audio flag'i sıfırla
    _callkitAudioReady = null;
    _preConnectStartedAt = null;
    elapsed.value = Duration.zero; // elapsed notifier'ı sıfırla
    _cpLog('TIMER', 'elapsed notifier RESET | value=Duration.zero');

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
