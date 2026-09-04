import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vibration/vibration.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../config/api.dart';
import '../core/app_exception.dart';
import 'push_notification_service.dart';
import 'ws_service.dart';
import '../models/call_event.dart';
import '../call/state/call_status.dart';
import '../call/state/call_role.dart';
import '../call/state/call_state_machine.dart';
import '../call/state/end_reason.dart';
import '../call/repository/call_repository.dart';
import '../call/hardware/call_hardware_adapter.dart';
import '../call/hardware/ios_call_hardware_adapter.dart';
import '../call/hardware/android_call_hardware_adapter.dart';
import '../call/notif/call_notif_adapter.dart';
import '../call/notif/ios_call_notif_adapter.dart';
import '../call/notif/android_call_notif_adapter.dart';
import '../call/state/call_state.dart';
import '../call/room/call_room_adapter.dart';
import '../call/routing/call_screen_router.dart';
import '../call/group/group_call_manager.dart';
import '../ui_library/components/overlays/teq_toast.dart';
import 'localization_service.dart';

// Re-export: mevcut tüm importlar call_service.dart üzerinden çalışmaya devam eder.
export '../call/state/call_status.dart';
export '../call/state/call_role.dart';
export '../call/state/end_reason.dart';
export '../call/state/call_state.dart';
export '../call/repository/call_repository.dart' show CallStartResult, CallAcceptResult, ActiveCallResult, CalleeTokenResult;

void _cpLog(String phase, String msg) {
  debugPrint('[CALL_PROCESS][${DateTime.now().toIso8601String()}][$phase] $msg');
}

class CallService {
  CallService._() {
    _roomAdapter = CallRoomAdapter(
      hardware: _hardware,
      preventCallScreenAutoOpen: preventCallScreenAutoOpen,
      getState: () => state.value,
      setState: _setState,
      onConnected: (ctx) => _transitionToConnected(context: ctx),
      endCall: endCall,
    );
    _groupManager = GroupCallManager(
      repository: _repository,
      getState: () => state.value,
      setState: _setState,
      hangUpLocally: ({required status, endReason}) => _hangUpLocally(status: status, endReason: endReason),
      joinRoom: ({required livekitUrl, required token}) => _roomAdapter.joinRoom(livekitUrl: livekitUrl, token: token),
      onAudioSessionActivated: _hardware.onAudioSessionActivated,
    );
    _hardware.init();
    if (Platform.isIOS) {
      _initCallkitChannelHandler();
    }
  }
  static final CallService instance = CallService._();

  final _repository = CallRepository();
  final _router = CallScreenRouter();

  final ValueNotifier<CallState> state = ValueNotifier(const CallState());
  ValueNotifier<bool> get isCallScreenVisible => _router.isCallScreenVisible;
  ValueNotifier<bool> get preventCallScreenAutoOpen => _router.preventCallScreenAutoOpen;

  // Arama sayacı: CallState'ten bağımsız notifier — her saniye setState() tetiklemez.
  // CallScreen bu notifier'ı doğrudan dinler; overlay ve diğer listener'lar etkilenmez.
  final ValueNotifier<Duration> elapsed = ValueNotifier(Duration.zero);

  // Typed event stream — all signaling sources (WS, FCM, CallKit) emit here.
  // Consumers can listen without depending on the raw Map<String, dynamic> format.
  final _eventController = StreamController<CallSignal>.broadcast();
  Stream<CallSignal> get callEventStream => _eventController.stream;

  /// acceptedAt backing field accessor — use instead of state.value.acceptedAt internally.
  DateTime? get acceptedAt => _acceptedAt ?? state.value.acceptedAt;

  /// Current call role — null when idle. Used by CallScreenRouter (Step 6).
  CallRole? get currentRole => _currentRole;

  late final CallRoomAdapter _roomAdapter;
  late final GroupCallManager _groupManager;
  Timer? _ringTimer; // 30s no-answer timeout
  Timer? _elapsedTimer;
  Timer? _resetTimer; // To prevent delayed reset overwriting new calls
  Timer? _callerStatusPollTimer; // Poll /status while in calling state (WS kayıp event recovery)
  Timer? _connectingTimeoutTimer; // 15s guard: connecting → endCall if TrackSubscribed never fires
  Timer? _networkLostInWaitingTimer; // D-1: 20s after network_lost in waiting → ended

  // V2.0 CallStateMachine: role-aware transition guard.
  // startCall → caller, onIncomingCall → callee, reset → null.
  CallRole? _currentRole;

  // Platform-specific audio hardware adapter (iOS / Android).
  final CallHardwareAdapter _hardware = Platform.isIOS
      ? IosCallHardwareAdapter()
      : AndroidCallHardwareAdapter();

  // Platform-specific notification / token adapter (Step 7).
  final CallNotifAdapter _notif = Platform.isIOS
      ? IosCallNotifAdapter()
      : AndroidCallNotifAdapter();

  /// Exposed for PushNotificationService token registration delegation (Step 7).
  CallNotifAdapter get notifAdapter => _notif;

  bool _isHangingUp = false;   // Eş zamanlı _hangUpLocally çağrılarını önler
  // WS connection lock: true while an active call is holding the WsService lock.
  // Ensures background lifecycle doesn't close the socket mid-call.
  bool _wsLockHeld = false;

  // Synchronous dedup guard: WS + FCM + CallKit aynı call_id ile ~150ms arayla gelir.
  // İlk çağrı _activeIncomingCallId'yi set eder; sonrakiler erken döner.
  // reset() + _hangUpLocally'de null'a çekilir.
  int? _activeIncomingCallId;
  // Exposed so PushNotificationService can guard CallEventActionCallDecline:
  // if this matches the declining callId, onIncomingCall is still in-flight
  // (backendStatus HTTP pending) — Android foreground dismiss fired too early.
  int? get activeIncomingCallId => _activeIncomingCallId;

  // Pre-connect başlama zamanı — acceptCall'da kaç ms önce başladığını ölçer.
  DateTime? _preConnectStartedAt;

  static const _callkitChannel = MethodChannel('com.teqlif/callkit');

  // iOS: CallKit audio session aktive olduğunda native'den sinyal alır.
  void _initCallkitChannelHandler() {
    _callkitChannel.setMethodCallHandler((call) async {
      if (call.method == 'audioSessionActivated') {
        _cpLog('LK', 'audioSessionActivated received from CallKit native');
        _hardware.onAudioSessionActivated();
      }
    });
  }

  // Backing field for acceptedAt — avoids calling→calling / connecting→connecting self-transitions.
  // Set when we learn the accepted timestamp (WS or /accept response).
  // Included in CallState when transitioning to connected so widgets can read it from state.
  DateTime? _acceptedAt;

  Timer? _statsTimer;               // WebRTC audio stats polling (5s)
  Timer? _ringbackFallbackTimer;    // Fallback: call_ringing WS gelmezse 3s sonra ringback başlat
  StreamSubscription<List<ConnectivityResult>>? _networkSub;  // Network change monitor
  ConnectivityResult? _prevNetworkType;  // For networkChange false-positive suppression

  // ── Helpers ──────────────────────────────────────────────────────────────

  void _setState(CallState s) {
    final oldStatus = state.value.status;
    if (oldStatus != s.status) {
      final validated = CallStateMachine.transition(
        current: oldStatus,
        next: s.status,
        role: _currentRole,
      );
      if (validated == null) {
        _cpLog(
          'STATE',
          'WARN blocked transition ${oldStatus.name} → ${s.status.name} | role=${_currentRole?.name ?? "unknown"} callId=${s.callId}',
        );
        assert(false, 'Invalid state transition: ${oldStatus.name} → ${s.status.name} | role=${_currentRole?.name}');
        return;
      }
    }
    _cpLog('STATE', '${oldStatus.name} → ${s.status.name} | callId=${s.callId} | role=${_currentRole?.name ?? "unknown"}${s.status == CallStatus.ended && s.endReason != null ? " | endReason=${s.endReason!.name}" : ""}');
    final oldPoor = state.value.isPoorConnection;

    // Pre-sync elapsed BEFORE notifying listeners so the first connected frame
    // shows the correct time instead of 00:00 (timer 00:00 flash fix).
    if (oldStatus != CallStatus.active && s.status == CallStatus.active) {
      final at = s.acceptedAt ?? _acceptedAt ?? state.value.acceptedAt;
      if (at != null) {
        final already = DateTime.now().toUtc().difference(at.toUtc());
        if (already.inMilliseconds > 0) elapsed.value = already;
      }
    }

    state.value = s;
    
    if (oldStatus != s.status) {
      _handleStatusChange(oldStatus, s.status);
    }
    
    if (!oldPoor && s.isPoorConnection && s.status == CallStatus.active) {
      _hardware.playWeakSound();
    }
  }

  static bool _isActiveCallStatus(CallStatus s) =>
      CallStateMachine.isActiveCallState(s);

  void _handleStatusChange(CallStatus oldStatus, CallStatus newStatus) {
    // Acquire WS connection lock when entering first active-call state so the
    // background lifecycle observer cannot close the socket mid-call.
    if (!_wsLockHeld && _isActiveCallStatus(newStatus)) {
      _wsLockHeld = true;
      WsService.acquireConnectionLock('call-${state.value.callId}-$newStatus');
    }
    // Release lock when leaving all active-call states (terminal or idle).
    if (_wsLockHeld && !_isActiveCallStatus(newStatus)) {
      _wsLockHeld = false;
      WsService.releaseConnectionLock('call-${state.value.callId}-$newStatus');
    }

    // Cancel connecting timeout whenever we leave connecting state
    if (oldStatus == CallStatus.connecting) {
      _connectingTimeoutTimer?.cancel();
    }

    if (newStatus == CallStatus.connecting) {
      _connectingTimeoutTimer?.cancel();
      _cpLog('TIMER', 'connectingTimeoutTimer started | 15s callId=${state.value.callId}');
      _connectingTimeoutTimer = Timer(const Duration(seconds: 15), () {
        if (state.value.status == CallStatus.connecting) {
          _cpLog('TIMER', 'connectingTimeoutTimer FIRED | stuck 15s in connecting → endCall | callId=${state.value.callId}');
          endCall();
        }
      });
    }

    // Cancel fallback timer when leaving waiting/dialing
    if (oldStatus == CallStatus.waiting || oldStatus == CallStatus.dialing) {
      _ringbackFallbackTimer?.cancel();
      _ringbackFallbackTimer = null;
    }

    if (newStatus == CallStatus.dialing) {
      _hardware.setupAudioSession(); // audio session hazırla; ringback call_ringing'de başlar
    } else if (newStatus == CallStatus.waiting) {
      // call_ringing WS 3s içinde gelmezse ringback'i yine de başlat (WS delivery güvencesi)
      _ringbackFallbackTimer?.cancel();
      _ringbackFallbackTimer = Timer(const Duration(seconds: 3), () {
        if (state.value.status == CallStatus.waiting || state.value.status == CallStatus.dialing) {
          _cpLog('RING', 'ringbackFallbackTimer FIRED → startRingback (no call_ringing in 3s) | callId=${state.value.callId}');
          _hardware.startRingback();
        }
      });
    } else if (newStatus == CallStatus.ended) {
      _hardware.stopRingback();
      final endReason = state.value.endReason;
      final wasConnected = oldStatus == CallStatus.active || oldStatus == CallStatus.connecting;
      _hardware.playEndedSound(wasConnected: wasConnected, endReason: endReason);
    } else if (newStatus == CallStatus.active || newStatus == CallStatus.idle) {
      _hardware.stopAllSounds();
    }
  }

  // ── Outgoing Call ─────────────────────────────────────────────────────────

  Future<void> startCall({
    required int calleeId,
    required String calleeUsername,
    required String? calleeAvatar,
  }) async {
    _cpLog('OUT', 'startCall ENTERED | calleeId=$calleeId calleeUsername=$calleeUsername');
    _currentRole = CallRole.caller;
    _resetTimer?.cancel();
    // If previous call just ended and reset timer was pending, clear elapsed now.
    if (state.value.status == CallStatus.ended) {
      elapsed.value = Duration.zero;
    }
    if (hasActiveCall) {
      _cpLog('OUT', 'startCall BLOCKED | hasActiveCall=true currentStatus=${state.value.status}');
      return;
    }

    final permStatus = await _hardware.requestMicPermission();
    _cpLog('OUT', 'mic permission | status=$permStatus');
    if (permStatus != PermissionStatus.granted) {
      _setState(
        state.value.copyWith(
          status: CallStatus.ended,
          endReason: EndReason.permissionDenied,
          permPermanentlyDenied: permStatus.isPermanentlyDenied,
        ),
      );
      _scheduleReset();
      return;
    }

    _setState(
      CallState(
        status: CallStatus.dialing,
        otherUserId: calleeId,
        otherUsername: calleeUsername,
        otherAvatar: calleeAvatar,
      ),
    );

    _startNetworkMonitor(); // D-6: dialing/waiting network_lost'u kapsasın
    try {
      final startResult = await _repository.startCall(calleeId);
      _cpLog('OUT', 'POST /calls/start e2ee=NO');
      _setState(
        state.value.copyWith(
          status: CallStatus.waiting,
          callId: startResult.callId,
          roomName: startResult.roomName,
          livekitUrl: startResult.livekitUrl,
          token: startResult.token,
        ),
      );

      await _notif.reportCallStarted(
        callId: startResult.callId,
        calleeName: calleeUsername,
        calleeAvatar: calleeAvatar,
      );

      _startRingTimer();
      _cpLog('HW', 'wakelock ENABLE | reason=startCall status=calling');
      await WakelockPlus.enable();

      // WhatsApp-like Pre-Connection: Arayan kişi beklemeden LiveKit'e bağlanır.
      _cpLog('OUT', 'pre-connect _joinRoom starting (WhatsApp-like)');
      await _roomAdapter.joinRoom(
        livekitUrl: startResult.livekitUrl,
        token: startResult.token,
      );
      _cpLog('OUT', 'pre-connect _joinRoom finished');

      // WS kayıp event recovery: call_accepted WS'den gelmezse poll ile yakala
      _startCallerStatusPoll(startResult.callId);
    } on AppException catch (e) {
      _cpLog('OUT', 'startCall AppException | code=${e.code}');
      if (e.code == 'USER_BUSY') {
        _setState(state.value.copyWith(status: CallStatus.ended, endReason: EndReason.busy));
        _scheduleReset();
      } else if (e.code == 'CALL_FORBIDDEN') {
        _cpLog('OUT', 'CALL_FORBIDDEN → teqToast');
        _setState(state.value.copyWith(status: CallStatus.ended, endReason: EndReason.callForbidden));
        _scheduleReset();
        TeqToast.error(
          LocalizationService.readCacheSync(LocalizationService.activeLang)
              .tOr('callForbiddenToast', 'Bu kullanıcıyı şu an arayamazsın'),
        );
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
    _cpLog('OUT', 'ringTimer started | timeout=15s callId=${state.value.callId}');
    _ringTimer = Timer(const Duration(seconds: 15), () async {
      if (state.value.status == CallStatus.waiting) {
        final callId = state.value.callId;
        _cpLog('OUT', 'ringTimer FIRED → noAnswer | callId=$callId');
        if (callId != null) {
          _repository.reportMissed(callId);
        }
        _setState(state.value.copyWith(status: CallStatus.ended, endReason: EndReason.noAnswer));
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
      if (state.value.status != CallStatus.waiting) {
        _callerStatusPollTimer?.cancel();
        return;
      }
      try {
        final s = await _repository.getCallStatus(callId);
        _cpLog('OUT', 'callerStatusPoll tick | callId=$callId backendStatus=$s status=${state.value.status}');
        if (s == 'active') {
          _callerStatusPollTimer?.cancel();
          if (state.value.status == CallStatus.waiting) {
            _cpLog('OUT', 'callerStatusPoll → RECOVERED call_accepted | callId=$callId');
            await onCallAccepted({});
          }
        } else if (s == 'missed' || s == 'ended' || s == 'rejected') {
          _callerStatusPollTimer?.cancel();
          if (state.value.status == CallStatus.waiting) {
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
    _currentRole = CallRole.callee;
    _resetTimer?.cancel();

    final incomingCallId = data['call_id'] is int
        ? data['call_id']
        : int.tryParse(data['call_id'].toString());

    // Synchronous dedup: WS + FCM + CallKit aynı call_id için ~150ms arayla gelir.
    // _activeIncomingCallId ilk çağrıda await öncesinde set edilir — sonraki tüm kaynaklar erken döner.
    // Bu check + set atomik (tek-threaded Dart): iki çağrı aynı anda bu satırı geçemez.
    if (incomingCallId != null) {
      if (incomingCallId == _activeIncomingCallId) {
        _cpLog('IN', 'onIncomingCall DEDUP BLOCKED | callId=$incomingCallId source=$source (WS/FCM/CallKit duplicate)');
        return;
      }
      _activeIncomingCallId = incomingCallId; // Synchronously set BEFORE first await
    }

    if (incomingCallId != null && _lastEndedCallId != null && incomingCallId <= _lastEndedCallId!) {
      _cpLog('IN', 'ghostCall BLOCKED | incoming=$incomingCallId <= lastEnded=$_lastEndedCallId (stale FCM/delayed push)');
      await _notif.reportCallEnded(callId: incomingCallId.toString());
      _cpLog('IN', 'ghostCall BLOCKED → notification dismissed | callId=$incomingCallId');
      _activeIncomingCallId = null; // Blocked — reset so next real call can proceed
      return;
    }

    if (hasActiveCall) {
      _cpLog('IN', 'hasActiveCall BUSY_REJECT | currentStatus=${state.value.status} currentCallId=${state.value.callId} incomingCallId=$incomingCallId');
      if (incomingCallId != null && incomingCallId != state.value.callId) {
        _repository.rejectCall(incomingCallId);
        // Dismiss the stale incoming notification so the user cannot tap Accept/Decline
        // on it later (which would fire duplicate call_rejected events to the caller).
        await _notif.reportCallEnded(callId: incomingCallId.toString());
        _cpLog('IN', 'hasActiveCall BUSY_REJECT → notification dismissed | callId=$incomingCallId');
      }
      _activeIncomingCallId = null; // Rejected — reset so future calls aren't blocked
      return;
    }

    if (incomingCallId != null) {
      try {
        final backendStatus = await _repository.getCallStatus(incomingCallId);
        _cpLog('IN', 'backendStatus check | callId=$incomingCallId status=$backendStatus');
        if (backendStatus == 'ended' || backendStatus == 'rejected' || backendStatus == 'missed') {
          _cpLog('IN', 'backendStatus SKIPPED (already terminated) | callId=$incomingCallId');
          // Dismiss the Android notification — FCM already called showCallkitIncoming so the
          // notification is visible even though we won't ring. Without this endCall the user
          // can tap "Accept" minutes later and get a phantom CallScreen (the "tekrar arama
          // geliyor" UX bug).
          await _notif.reportCallEnded(callId: incomingCallId.toString());
          _cpLog('IN', 'backendStatus TERMINATED → notification dismissed | callId=$incomingCallId');
          _activeIncomingCallId = null;
          return;
        }
      } catch (e) {
        _cpLog('IN', 'backendStatus check FAILED (continuing) | $e');
      }
    }

    final calleeToken = data['callee_token'] as String?;
    final livekitUrl = data['livekit_url'] as String?;

    final wasAlreadyRinging = state.value.status == CallStatus.ringing;

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
    // Guard 3 in push_notification_service only needs to block the Android foreground
    // race (FCM decline arriving while HTTP is in-flight, ~150-300ms). Once state is
    // ringing, hasActiveCall guards future duplicates — clear so real user declines
    // (e.g. iOS lock-screen Decline button) are not incorrectly blocked.
    _activeIncomingCallId = null;

    // Pre-connect: LK odaya ringing sırasında bağlan → acceptance'da sadece mic aktive et.
    // Empty string guard: VoIP payload'da callee_token/livekit_url yoksa AppDelegate "" döner.
    // "" != null → null-check geçer ama _roomAdapter.joinRoom("","") → malformed URI → exception → endCall.
    // isEmpty kontrolü ile HTTP fetch fallback'e düşüyoruz.
    if ((calleeToken == null || calleeToken.isEmpty || livekitUrl == null || livekitUrl.isEmpty) && incomingCallId != null) {
      // VoIP push (iOS): payload'da token yok → önce fetch, sonra pre-connect.
      _cpLog('IN', 'calleeToken/livekitUrl missing or empty — proactive fetch starting | callId=$incomingCallId source=$source');
      _fetchAndStoreCalleeToken(incomingCallId);
    } else if (calleeToken != null && calleeToken.isNotEmpty && livekitUrl != null && livekitUrl.isNotEmpty && incomingCallId != null && _roomAdapter.room == null && !_roomAdapter.isJoiningRoom) {
      // WS path (Android foreground): token payload'da hazır → pre-connect hemen başlat.
      // iOS VoIP push path'i _fetchAndStoreCalleeToken üzerinden zaten pre-connect yapar.
      _preConnectStartedAt = DateTime.now();
      _cpLog('IN', 'callee pre-connect (WS token path): _joinRoom starting immediately | callId=$incomingCallId preConnectStartUtc=${_preConnectStartedAt!.toUtc().toIso8601String()} source=$source');
      _roomAdapter.joinRoom(livekitUrl: livekitUrl, token: calleeToken).catchError((e) {
        _cpLog('IN', 'callee pre-connect (WS token path) _joinRoom ERROR | $e callId=$incomingCallId');
      });
    }

    // playNotification: sadece idle→ringing geçişinde ve native call screen yokken çal.
    // wasAlreadyRinging: WS replay veya FCM+WS çift teslimat guard'ı.
    // CallEventActionCallIncoming (Android): native call screen + system ringtone gösteriliyor,
    //   Flutter'ın notification sesi audio focus çalarak native ringtone'u kesiyor → atla.
    final shouldPlayNotification = !wasAlreadyRinging &&
        !(Platform.isAndroid && source == 'CallEventActionCallIncoming');
    if (shouldPlayNotification) {
      playNotification();
    } else {
      _cpLog('IN', 'playNotification SKIPPED | wasAlreadyRinging=$wasAlreadyRinging source=$source');
    }
  }

  /// VoIP push path için callee LK token'ını arka planda çeker ve state'e yazar.
  /// Kullanıcı kabul ettiğinde pre-connect başlatılabilmesi için ringing sırasında çalışır.
  Future<void> _fetchAndStoreCalleeToken(int callId) async {
    final fetchStartAt = DateTime.now();
    _cpLog('IN', '_fetchCalleeToken start | callId=$callId fetchStartUtc=${fetchStartAt.toUtc().toIso8601String()}');
    try {
      final tokenResult = await _repository.getCalleeToken(callId);
      final fetchEndAt = DateTime.now();
      final httpMs = fetchEndAt.difference(fetchStartAt).inMilliseconds;
      final token = tokenResult.token;
      final url = tokenResult.livekitUrl;
      final room = tokenResult.roomName;
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
        if (_roomAdapter.room == null && !_roomAdapter.isJoiningRoom && token != null && url != null) {
          _preConnectStartedAt = DateTime.now();
          _cpLog('IN', 'callee pre-connect _joinRoom starting during ringing | callId=$callId preConnectStartUtc=${_preConnectStartedAt!.toUtc().toIso8601String()} fetchHttpMs=$httpMs');
          _roomAdapter.joinRoom(livekitUrl: url, token: token).catchError((e) {
            _cpLog('IN', 'callee pre-connect _joinRoom ERROR | $e');
          });
        } else {
          _cpLog('IN', '_fetchCalleeToken: pre-connect _joinRoom SKIPPED | roomNull=${_roomAdapter.room == null} isJoining=$_roomAdapter.isJoiningRoom tokenOk=${token != null} urlOk=${url != null}');
        }
      } else {
        _cpLog('IN', '_fetchCalleeToken discarded (state changed) | callId=$callId status=${state.value.status.name}');
      }
    } catch (e) {
      _cpLog('IN', '_fetchCalleeToken FAILED (acceptCall response-token fallback will be used) | $e');
    }
  }

  void playNotification() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (state.value.status == CallStatus.ringing) {
        _hardware.playNotification();
      }
    });
  }

  void startRingtoneAndVibration() {
    _cpLog('SOUND', 'startRingtoneAndVibration CALLED | status=${state.value.status}');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (state.value.status != CallStatus.ringing) return;
      _hardware.startRinger();
    });
  }

  void stopRingtoneAndVibration() {
    _cpLog('SOUND', 'stopRingtoneAndVibration CALLED | status=${state.value.status}');
    _hardware.stopRinger();
  }

  Future<void> acceptCall() async {
    _cpLog('IN', 'acceptCall TRIGGERED | status=${state.value.status} callId=${state.value.callId}');
    if (state.value.status == CallStatus.connecting || state.value.status == CallStatus.active) {
      return;
    }
    final callId = state.value.callId;
    if (callId == null) {
      return;
    }
    if (state.value.status == CallStatus.connecting || state.value.status == CallStatus.active) {
      return;
    }

    _resetTimer?.cancel();
    stopRingtoneAndVibration();

    // Mic permission check BEFORE connecting transition (VoIP.md §15.2):
    // - .request() shows OS dialog (vs .status which is silent) → user sees the prompt
    // - denied: ringing → ended + /reject fire-and-forget (caller notified immediately)
    // - permanentlyDenied: state stays ringing; UI shows modal (§15.3); user can go to Settings
    final permStatus = await _hardware.requestMicPermission();
    _cpLog('IN', 'mic permission | status=$permStatus');
    if (!permStatus.isGranted) {
      if (permStatus.isPermanentlyDenied) {
        // State stays at ringing — UI (IncomingCallScreen/IncomingCallBar) shows modal.
        // Ringtone was already stopped above; restart not needed.
        _cpLog('IN', 'mic permanentlyDenied | ringing stays, permPermanentlyDenied=true → UI modal');
        _setState(state.value.copyWith(permPermanentlyDenied: true));
      } else {
        // denied: end the call immediately, notify caller via /reject.
        _cpLog('IN', 'mic denied | ringing → ended, /reject fire-and-forget');
        _repository.rejectCall(callId);
        _hangUpLocally(
          status: CallStatus.ended,
          endReason: EndReason.permissionDenied,
        );
        try {
          await PushNotificationService.showWarningNotification();
        } catch (_) {}
      }
      return;
    }

    // Transition to connecting only after mic permission confirmed.
    _setState(state.value.copyWith(status: CallStatus.connecting));

    // Snapshot token/url — may be set by _fetchAndStoreCalleeToken (proactive fetch)
    final preConnectUrl = state.value.livekitUrl;
    final preConnectToken = state.value.calleeToken;

    final preConnectAgeMs = _preConnectStartedAt != null
        ? DateTime.now().difference(_preConnectStartedAt!).inMilliseconds
        : -1;
    _cpLog(
      'IN',
      'acceptCall pre-connect check | roomReady=${_roomAdapter.room != null} isJoining=$_roomAdapter.isJoiningRoom '
      'tokenReady=${preConnectToken != null} urlReady=${preConnectUrl != null} '
      'preConnectAgeMs=$preConnectAgeMs nowUtc=${DateTime.now().toUtc().toIso8601String()}',
    );

    if (_roomAdapter.room != null && !_roomAdapter.isJoiningRoom) {
      // _fetchAndStoreCalleeToken pre-connect tamamlandı → sadece audio aktive et.
      // Bu yol: callee pre-connect ÇALIŞIYOR (WhatsApp kalitesi).
      _cpLog('IN', 'acceptCall: callee pre-connect ROOM READY → _activateCalleeAudio | preConnectAgeMs=$preConnectAgeMs');
      _roomAdapter.activateCalleeAudio().catchError((e) {
        _cpLog('IN', 'acceptCall _activateCalleeAudio ERROR | $e');
      });
    } else if (_roomAdapter.isJoiningRoom) {
      // Pre-connect room.connect() devam ediyor (_room null veya non-null olabilir).
      // _joinRoom else bloğu status=connecting + callStatusAtEntry=ringing detektörü devralacak.
      _cpLog('IN', 'acceptCall: callee pre-connect IN PROGRESS (_joinRoom running) → _activateCalleeAudio deferred | preConnectAgeMs=$preConnectAgeMs');
    } else if (preConnectUrl != null && preConnectToken != null) {
      // Token hazır ama _joinRoom henüz başlamadı → callee rolüyle başlat.
      // Bu yol: token fetch tamam ama pre-connect başlatılamamış (edge case).
      _cpLog('IN', 'acceptCall: token ready, room NULL → _joinRoom now (isCallee=true) | preConnectAgeMs=$preConnectAgeMs');
      _roomAdapter.joinRoom(livekitUrl: preConnectUrl, token: preConnectToken).catchError((e) {
        _cpLog('IN', 'acceptCall _joinRoom (callee token) ERROR | $e');
      });
    } else {
      // Pre-connect hiç başlamamış — FALLBACK: /accept response token kullanılacak.
      // Bu yol: CallEventActionCallIncoming handle edilmemişse veya token fetch başarısızsa.
      _cpLog('IN', 'acceptCall: NO pre-connect (room=null, isJoining=false, token=${preConnectToken != null}) → FALLBACK to /accept response token');
    }

    try {
      final acceptResult = await _repository.acceptCall(
        callId,
        shouldAbort: () => state.value.status != CallStatus.connecting,
      );

      if (acceptResult.acceptedAt != null) {
        final parsedAt = acceptResult.acceptedAt!;
        final nowUtc = DateTime.now().toUtc();
        _cpLog('TIMER', 'acceptedAt SET [CALLEE/accept-response] | acceptedAt=${parsedAt.toIso8601String()} nowUtc=${nowUtc.toIso8601String()} httpRTT=${nowUtc.difference(parsedAt).inMilliseconds}ms');
        // Use backing field — avoids connecting→connecting self-transition rebuild.
        _acceptedAt = parsedAt;
      } else {
        _cpLog('TIMER', 'acceptedAt MISSING in /accept response — timer will use local clock');
      }

      // FALLBACK: hiç pre-connect başlamadıysa response token ile LiveKit'e bağlan.
      if (_roomAdapter.room == null && !_roomAdapter.isJoiningRoom) {
        final responseToken = acceptResult.token;
        final responseLkUrl = acceptResult.livekitUrl ?? preConnectUrl;
        _cpLog('IN', 'acceptCall FALLBACK: _joinRoom with RESPONSE token | tokenLen=${responseToken?.length} url=$responseLkUrl');
        if (responseToken != null && responseLkUrl != null) {
          _roomAdapter.joinRoom(livekitUrl: responseLkUrl, token: responseToken).catchError((e) {
            _cpLog('IN', 'acceptCall _joinRoom (response token) ERROR | $e');
          });
        } else {
          _cpLog('IN', 'acceptCall: response token/url null — cannot join LiveKit');
          _hangUpLocally(status: CallStatus.ended);
        }
      }
    } on AppException catch (e) {
      if (e.code == 'ABORTED') {
        _cpLog('IN', 'acceptCall ABORTED | status=${state.value.status.name}');
        return;
      }
      _cpLog('IN', 'acceptCall FAILED | $e');
      _hangUpLocally(status: CallStatus.ended);
    } catch (e) {
      _cpLog('IN', 'acceptCall FAILED after retries | $e');
      _hangUpLocally(status: CallStatus.ended);
    }
  }

  Future<void> rejectCall() async {
    final currentStatus = state.value.status;
    if (currentStatus == CallStatus.ended) return;
    // Call already accepted — stale reject from UI must not call /reject.
    if (currentStatus == CallStatus.connecting ||
        currentStatus == CallStatus.active ||
        currentStatus == CallStatus.reconnecting) {
      _cpLog('IN', 'rejectCall SKIPPED | status=${currentStatus.name} (call already accepted — use endCall)');
      return;
    }
    final callId = state.value.callId;
    // Optimistic reset: bar disappears immediately; HTTP fires in background.
    // Same pattern as endCall() fire-and-forget — user intent is unambiguous.
    reset();
    if (callId != null) {
      _repository.rejectCall(callId);
    }
  }

  // ── Called when caller gets call_accepted WS event ────────────────────────

  Future<void> onCallAccepted(Map<String, dynamic> data) async {
    _cpLog('OUT', 'call_accepted WS event received | acceptedAt=${data['accepted_at']} currentStatus=${state.value.status.name}');
    _ringTimer?.cancel();
    _callerStatusPollTimer?.cancel();

    // PART 1: acceptedAt — always update regardless of current status.
    // Critical for iOS: TrackSubscribed fires ~1.65s BEFORE this WS arrives,
    // so status is already `connected` when we get here. Without this unconditional
    // update, acceptedAt stays null → durationMs=-1 in analytics.
    if (data['accepted_at'] != null && _acceptedAt == null && state.value.acceptedAt == null) {
      final parsedAt = DateTime.parse(data['accepted_at'] as String);
      final nowUtc = DateTime.now().toUtc();
      _cpLog('TIMER', 'acceptedAt SET [CALLER/WS] | acceptedAt=${parsedAt.toIso8601String()} nowUtc=${nowUtc.toIso8601String()} wsLag=${nowUtc.difference(parsedAt).inMilliseconds}ms');
      // Use backing field — avoids calling→calling self-transition rebuild.
      _acceptedAt = parsedAt;
      // Correct elapsed timer if TrackSubscribed already transitioned us to connected.
      // Without this, the elapsed timer starts from zero even though the call started ~1.65s ago.
      if (state.value.status == CallStatus.active) {
        final correctedElapsed = nowUtc.difference(parsedAt);
        if (!correctedElapsed.isNegative && correctedElapsed.inSeconds < 300) {
          elapsed.value = correctedElapsed;
          _cpLog('TIMER', 'elapsed CORRECTED from acceptedAt | correctedMs=${correctedElapsed.inMilliseconds} (WS arrived after TrackSubscribed)');
        }
      }
    }

    // PART 2: State transition + mic activation, conditional on current status.

    // iOS race: TrackSubscribed fires ~1.65s before WS → already connected.
    // TrackSubscribed pre-enables mic (see _onRoomEvent), but call _ensureMicEnabled
    // as a safety net in case pre-enable failed or was skipped.
    if (state.value.status == CallStatus.active) {
      _cpLog('OUT', 'call_accepted WS arrived after connected (iOS race) → ensureMicEnabled | callId=${state.value.callId}');
      _roomAdapter.ensureMicEnabled('onCallAccepted-already-connected');
      return;
    }

    // Poll recovery or duplicate WS: already transitioning.
    if (state.value.status == CallStatus.connecting) {
      _cpLog('OUT', 'call_accepted: already connecting — skip state-change, ensureMicEnabled | callId=${state.value.callId}');
      _roomAdapter.ensureMicEnabled('onCallAccepted-already-connecting');
      return;
    }

    _resetTimer?.cancel();
    _cpLog('OUT', 'call_accepted → state=connecting | callId=${state.value.callId}');
    _setState(state.value.copyWith(status: CallStatus.connecting));

    // D-10: Caller mic activation delegated to CallRoomAdapter (fast/standard path).
    _roomAdapter.activateCallerMic();
  }

  void onCallRejected() async {
    if (state.value.status != CallStatus.waiting) {
      _cpLog('END', 'onCallRejected SKIPPED | status=${state.value.status} (not waiting — stale/duplicate event)');
      return;
    }
    stopRingtoneAndVibration();
    _ringTimer?.cancel();
    _setState(state.value.copyWith(status: CallStatus.ended, endReason: EndReason.rejected));
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

  void onCallRinging() {
    if (state.value.status != CallStatus.waiting && state.value.status != CallStatus.dialing) {
      _cpLog('RING', 'onCallRinging SKIPPED | status=${state.value.status} (not waiting/dialing)');
      return;
    }
    _ringbackFallbackTimer?.cancel();
    _ringbackFallbackTimer = null;
    _cpLog('RING', 'call_ringing WS → startRingback | callId=${state.value.callId}');
    _hardware.startRingback();
  }

  void onCallUnreachable() {
    if (!hasActiveCall) {
      _cpLog('RING', 'onCallUnreachable SKIPPED | no active call');
      return;
    }
    _cpLog('RING', 'call_unreachable WS → ended+unreachable | callId=${state.value.callId}');
    _ringbackFallbackTimer?.cancel();
    _ringbackFallbackTimer = null;
    _ringTimer?.cancel();
    _callerStatusPollTimer?.cancel();
    _setState(state.value.copyWith(status: CallStatus.ended, endReason: EndReason.unreachable));
    _scheduleReset();
  }

  void onCallMissed({int? callId}) async {
    if (state.value.status == CallStatus.ended && state.value.endReason == EndReason.missed) return;
    // Guard: no active call in state → stale event after reset(), ignore.
    if (state.value.callId == null) {
      _cpLog('END', 'onCallMissed SKIPPED | no active call (state.callId=null) incoming=$callId (stale event)');
      return;
    }
    // Guard: a connected/reconnecting call cannot be missed — stale queued FCM.
    if (state.value.status == CallStatus.active ||
        state.value.status == CallStatus.reconnecting) {
      _cpLog('END', 'onCallMissed SKIPPED | call already connected | incoming=$callId current=${state.value.callId}');
      return;
    }
    // Guard: no call_id in event → cannot verify target call, ignore.
    if (callId == null) {
      _cpLog('END', 'onCallMissed SKIPPED | no call_id in event | current=${state.value.callId} (stale queued FCM)');
      return;
    }
    // Guard: callId mismatch → event for a different call, ignore.
    if (callId != state.value.callId) {
      _cpLog('END', 'onCallMissed SKIPPED | callId mismatch incoming=$callId current=${state.value.callId}');
      return;
    }
    stopRingtoneAndVibration();
    _setState(state.value.copyWith(status: CallStatus.ended, endReason: EndReason.missed));
    if (await Vibration.hasVibrator() == true) {
      _cpLog('HW', 'haptic VIBRATE | pattern=[200,100,200] reason=missed');
      Vibration.vibrate(pattern: [200, 100, 200]);
    }
    _scheduleReset();
  }


  // ── Connected State Transition (T12 — single source of truth) ────────────

  /// Her "calling/connecting → connected" geçişini buradan yap.
  /// [context]: log etiketleme için (TrackSubscribed, TrackUnmuted, peerAlready…)
  void _transitionToConnected({required String context}) {
    if (state.value.status == CallStatus.active) return;
    final nowUtc = DateTime.now().toUtc();
    final acceptedAt = state.value.acceptedAt;
    final audioLag = acceptedAt != null ? nowUtc.difference(acceptedAt.toUtc()).inMilliseconds : -1;
    _cpLog('TIMER', 'CONNECTED | context=$context acceptedAt=${acceptedAt?.toIso8601String() ?? "NULL"} acceptToAudioMs=$audioLag');
    stopRingtoneAndVibration();
    _setState(state.value.copyWith(status: CallStatus.active, acceptedAt: _acceptedAt));
    _startElapsedTimer();
    _hardware.startProximitySensor(onNear: () {
      if (state.value.status == CallStatus.active && _hardware.isSpeaker.value) {
        setSpeaker(false);
      }
    });
    _startStatsMonitor();
    _startNetworkMonitor();
    // T6: Notify backend so connected_at is stamped for accurate duration.
    final callId = state.value.callId;
    if (callId != null) {
      _repository.reportConnected(callId);
    }
  }

  // ── WebRTC Audio Health Monitor ───────────────────────────────────────────
  // Polls room state every 5s during connected calls.
  // Granular packet-loss stats use LiveKit's internal stats engine via ConnectionQuality events.
  // This periodic log captures one-way audio (remoteParticipants empty mid-call).

  void _startStatsMonitor() {
    _statsTimer?.cancel();
    _cpLog('LK', 'statsMonitor START | interval=5s callId=${state.value.callId}');
    _statsTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (state.value.status != CallStatus.active || _roomAdapter.room == null) {
        _statsTimer?.cancel();
        return;
      }
      final remotePeerCount = _roomAdapter.room!.remoteParticipants.length;
      final quality = state.value.isPoorConnection ? 'POOR' : 'OK';
      _cpLog('LK', 'healthTick | remotePeers=$remotePeerCount quality=$quality callId=${state.value.callId}');
      if (remotePeerCount == 0 && state.value.status == CallStatus.active) {
        _cpLog('LK', 'healthTick: NO REMOTE PEERS (one-way audio risk) | callId=${state.value.callId}');
      }
    });
  }

  void _stopStatsMonitor() {
    _statsTimer?.cancel();
    _statsTimer = null;
  }

  // ── Network Change Monitor (logs only — LiveKit handles reconnect) ────────

  void _startNetworkMonitor() {
    _networkSub?.cancel();
    _prevNetworkType = null;
    _cpLog('LK', 'networkMonitor START | callId=${state.value.callId}');
    _networkSub = Connectivity().onConnectivityChanged.listen((results) {
      const activeStatuses = {
        CallStatus.dialing,
        CallStatus.waiting,
        CallStatus.connecting,
        CallStatus.active,
        CallStatus.reconnecting,
      };
      if (!activeStatuses.contains(state.value.status)) return;

      final newType = results.isNotEmpty ? results.first : ConnectivityResult.none;
      if (newType == _prevNetworkType) return; // same type → connectivity_plus false positive
      final prevType = _prevNetworkType;
      _prevNetworkType = newType;

      if (newType == ConnectivityResult.none) {
        _cpLog('LK', 'networkChange → network_lost | status=${state.value.status.name} callId=${state.value.callId}');
        _handleNetworkLost();
      } else if (prevType == ConnectivityResult.none) {
        _cpLog('LK', 'networkChange → network_restored | status=${state.value.status.name} callId=${state.value.callId}');
        _handleNetworkRestored();
      }
    });
  }

  void _handleNetworkLost() {
    final status = state.value.status;
    switch (status) {
      case CallStatus.dialing:
      case CallStatus.connecting:
        _cpLog('LK', 'network_lost in $status → ended');
        _hangUpLocally(status: CallStatus.ended, endReason: EndReason.error);
      case CallStatus.waiting:
        // D-1: 20s bekle; hiccup ise network_restored iptal eder
        _cpLog('TIMER', 'D-1 network_lost in waiting → 20s timer started');
        _networkLostInWaitingTimer?.cancel();
        _networkLostInWaitingTimer = Timer(const Duration(seconds: 20), () {
          if (state.value.status == CallStatus.waiting) {
            _cpLog('TIMER', 'D-1 timer fired: waiting + network_lost timeout → ended');
            _hangUpLocally(status: CallStatus.ended, endReason: EndReason.error);
          }
        });
      default:
        // active → reconnecting: LiveKit kendi reconnect mekanizması, müdahale etme
        // reconnecting: timer_peer_expired zaten yönetiyor
        break;
    }
  }

  void _handleNetworkRestored() {
    if (state.value.status == CallStatus.waiting) {
      _networkLostInWaitingTimer?.cancel();
      _networkLostInWaitingTimer = null;
      _cpLog('TIMER', 'D-1 timer CANCELLED — network restored in waiting');
    }
    // reconnecting: LiveKit retry kendi devam eder, ek aksiyon yok
  }

  void _stopNetworkMonitor() {
    _networkSub?.cancel();
    _networkSub = null;
  }

  void _startElapsedTimer() {
    _elapsedTimer?.cancel();
    final acceptedAt = _acceptedAt ?? state.value.acceptedAt;
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
      if (state.value.status == CallStatus.active) {
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
    await _roomAdapter.room?.localParticipant?.setMicrophoneEnabled(!muted);
    _setState(state.value.copyWith(isMuted: muted));
  }

  Future<void> setSpeaker(bool enabled) async {
    _cpLog('UI', 'setSpeaker | enabled=$enabled');
    _cpLog('HW', 'speakerphone SET | enabled=$enabled context=setSpeaker userAction=true');
    await _hardware.setSpeaker(enabled); // sets _hardware.isSpeaker.value
  }
  Future<void> endCall() async {
    _cpLog('END', 'endCall TRIGGERED by user | prevStatus=${state.value.status} callId=${state.value.callId}');
    if (state.value.status == CallStatus.ended || state.value.status == CallStatus.idle) {
      _cpLog('END', 'endCall SKIPPED | already ended/idle');
      return;
    }
    // Guard: CallEventActionCallEnded fires twice (endCall + endCallAlls transactions) while
    // _hangUpLocally is already in progress. Without this guard both events pass the status
    // check (status is still connected/calling during async hangup) and each posts to backend.
    if (_isHangingUp) {
      _cpLog('END', 'endCall SKIPPED | _isHangingUp (duplicate CallKit event)');
      return;
    }
    final callId = state.value.callId;
    _callerStatusPollTimer?.cancel();
    if (callId != null) {
      _repository.endCall(callId);
    }
    await _hangUpLocally(status: CallStatus.ended);
  }

  // ── Internal Cleanup ──────────────────────────────────────────────────────

  Future<void> _hangUpLocally({
    required CallStatus status,
    EndReason? endReason,
    bool? permPermanentlyDenied,
  }) async {
    _cpLog('END', '_hangUpLocally called | targetStatus=$status endReason=$endReason prevStatus=${state.value.status} callId=${state.value.callId}');
    if (_isHangingUp) {
      _cpLog('END', '_hangUpLocally SKIPPED | already hanging up');
      return;
    }
    // Ghost state guard: geç gelen WS/FCM event'leri (call_ended/call_missed) zaten idle/ended
    // olan state'i ended'a geçirmesin — kullanıcı ekrandan döndükten sonra gereksiz pop tetikler.
    // ended guard: FCM + WS call_ended aynı anda gelebilir → ikinci çağrı atlanır.
    if (state.value.status == CallStatus.idle || state.value.status == CallStatus.ended) {
      _cpLog('END', '_hangUpLocally SKIPPED | already ${state.value.status.name} (late WS/FCM event ignored) | targetStatus=$status');
      return;
    }

    final prevStatus = state.value.status;
    _isHangingUp = true;
    try {
      if (prevStatus == status) {
        return;
      }
      _callerStatusPollTimer?.cancel();
      stopRingtoneAndVibration();
      _ringTimer?.cancel();
      _elapsedTimer?.cancel();

      // Arama süresi logu — analytics ve gözlem için.
      final effectiveAcceptedAt = _acceptedAt ?? state.value.acceptedAt;
      final callDurationMs = effectiveAcceptedAt != null
          ? DateTime.now().toUtc().difference(effectiveAcceptedAt.toUtc()).inMilliseconds
          : -1;
      _cpLog('END', 'call DURATION | callId=${state.value.callId} acceptedAt=${effectiveAcceptedAt?.toIso8601String() ?? "NULL"} durationMs=$callDurationMs durationSec=${callDurationMs > 0 ? callDurationMs ~/ 1000 : -1}');

      _cpLog('END', 'disconnectRoom starting');
      await _disconnectRoom();
      _cpLog('END', 'disconnectRoom done');
      _cpLog('HW', 'wakelock DISABLE | context=_hangUpLocally');
      WakelockPlus.disable();

      // §16.2.5 — platform bildir (CallNotifAdapter)
      await _notif.reportCallEnded(callId: state.value.callId?.toString());
      await _notif.endAllCalls();

      // SwipeLiveScreen bağlamında arama bitti → stream hoparlörden devam etmeli.
      // reset() preventCallScreenAutoOpen'ı temizlemeden önce flag'i oku.
      final wasInSwipeLive = preventCallScreenAutoOpen.value;
      // SwipeLive: speaker=true bırak (stream hoparlöre dönsün).
      // Standart: earpiece'e sıfırla.
      _cpLog('HW', 'speakerphone SET | enabled=$wasInSwipeLive context=_hangUpLocally swipeLive=$wasInSwipeLive');
      await _hardware.setSpeaker(wasInSwipeLive);
      // iOS: voiceChat modu ile playAndRecord session'ı açık kalır → turuncu nokta göstergesi.
      // Arama sonrası deactivate et; SwipeLiveScreen ve diğer ses kaynakları session'ı devralabilir.
      // Android impl is a no-op — call unconditionally.
      await _hardware.teardownAudioSession();

      // Bütün donanım/native işlemler bittikten sonra state'i güncelliyoruz
      // Böylece UI katmanı (SwipeLiveScreen) tepki verdiğinde her şey hazır oluyor.
      _setState(state.value.copyWith(
        status: status,
        endReason: endReason,
        permPermanentlyDenied: permPermanentlyDenied,
      ));
      _scheduleReset();
    } finally {
      _isHangingUp = false;
    }
  }

  Future<void> _disconnectRoom() async {
    _elapsedTimer?.cancel();
    _callerStatusPollTimer?.cancel();
    _connectingTimeoutTimer?.cancel();
    _networkLostInWaitingTimer?.cancel();
    _networkLostInWaitingTimer = null;
    _stopStatsMonitor();
    _hardware.stopProximitySensor();
    _stopNetworkMonitor();
    _hardware.stopAllSounds(); // Safety net: stop ringback + any one-shot sounds
    await _roomAdapter.disconnect();
  }

  // Called by IncomingCallScreen when user taps [Ayarlar'a Git] on the
  // permanentlyDenied modal. Clears the flag so accept can be retried on return.
  void clearPermPermanentlyDenied() {
    _setState(state.value.copyWith(permPermanentlyDenied: false));
  }

  void reset() {
    _cpLog('END', 'reset() called | callId=${state.value.callId} status=${state.value.status}');
    _resetTimer?.cancel();
    _callerStatusPollTimer?.cancel();
    _connectingTimeoutTimer?.cancel();
    _networkLostInWaitingTimer?.cancel();
    _networkLostInWaitingTimer = null;
    stopRingtoneAndVibration();
    _ringbackFallbackTimer?.cancel();
    _ringbackFallbackTimer = null;
    _ringTimer?.cancel();
    _elapsedTimer?.cancel();
    _disconnectRoom();
    // Safety net: release WS lock if still held (error path bypassed _handleStatusChange).
    if (_wsLockHeld) {
      _wsLockHeld = false;
      WsService.releaseConnectionLock('call-reset-safety');
    }
    _cpLog('HW', 'wakelock DISABLE | context=reset');
    WakelockPlus.disable();
    _notif.endAllCalls();
    _hardware.resetAfterCall(); // iOS: _audioSessionActivated flag + Completer sıfırla
    _preConnectStartedAt = null;
    _activeIncomingCallId = null; // Dedup guard sıfırla — yeni aramalara açık
    _acceptedAt = null;
    _currentRole = null; // Role sıfırla — bir sonraki arama başlangıcında set edilir
    elapsed.value = Duration.zero; // elapsed notifier'ı sıfırla
    _stopStatsMonitor();
    _hardware.stopProximitySensor();
    _stopNetworkMonitor();
    _cpLog('TIMER', 'elapsed notifier RESET | value=Duration.zero');

    if (state.value.callId != null) {
      _lastEndedCallId = state.value.callId;
      _cpLog('END', '_lastEndedCallId set | callId=$_lastEndedCallId');
    }

    preventCallScreenAutoOpen.value = false;
    _setState(const CallState());
    _cpLog('END', 'reset() done → state=idle');
  }

  void _scheduleReset() {
    _resetTimer?.cancel();
    _cpLog('END', 'scheduleReset 2s scheduled | status=${state.value.status}');
    _resetTimer = Timer(const Duration(seconds: 2), reset);
  }

  bool get hasActiveCall =>
      state.value.status == CallStatus.dialing ||
      state.value.status == CallStatus.waiting ||
      state.value.status == CallStatus.ringing ||
      state.value.status == CallStatus.connecting ||
      state.value.status == CallStatus.active ||
      state.value.status == CallStatus.reconnecting;

  // ── Crash / Reconnect Recovery ────────────────────────────────────────────

  /// Queries GET /calls/active and restores call state if a call is in progress.
  ///
  /// Called in three situations:
  ///   1. WS "connected" event fires after reconnect (IncomingCallOverlay)
  ///   2. App cold-start / login restore (AuthService / main.dart)
  ///   3. FCM call_accepted push arrives while callId is null (killed app)
  ///
  /// Guards: if state is already non-idle this is a no-op — avoids clobbering
  /// an in-progress call that the caller may have resumed normally.
  Future<void> checkActiveCall() async {
    final currentStatus = state.value.status;
    _cpLog('RECOVERY', 'checkActiveCall ENTER | currentStatus=${currentStatus.name}');

    if (currentStatus != CallStatus.idle) {
      _cpLog('RECOVERY', 'checkActiveCall SKIPPED | non-idle state=${currentStatus.name} (no-op)');
      return;
    }

    try {
      final activeCall = await _repository.getActiveCall();

      if (activeCall == null) {
        _cpLog('RECOVERY', 'checkActiveCall → no active call (idle confirmed)');
        return;
      }

      final callId     = activeCall.callId;
      final callStatus = activeCall.status;
      final role       = activeCall.role;
      final roomName   = activeCall.roomName;
      final lkUrl      = activeCall.livekitUrl;
      final freshToken = activeCall.token;
      final otherUser  = activeCall.otherUser;
      final otherUserId   = otherUser['id'] as int?;
      final otherUsername = otherUser['username'] as String?;
      final otherAvatar   = otherUser['avatar']   as String?;
      final acceptedAt    = activeCall.acceptedAt;

      _cpLog(
        'RECOVERY',
        'checkActiveCall → active call found | call_id=$callId status=$callStatus role=$role '
        'other=$otherUsername tokenLen=${freshToken.length}',
      );

      // Dedup: if this callId is already in memory from a concurrent path, skip.
      if (state.value.callId == callId && state.value.status != CallStatus.idle) {
        _cpLog('RECOVERY', 'checkActiveCall DEDUP | call_id=$callId already in state=${state.value.status.name}');
        return;
      }

      if (callStatus == 'calling' && role == 'caller') {
        // Restore outgoing call — we're waiting for the callee to answer.
        _cpLog('RECOVERY', 'checkActiveCall → RESTORE calling (outgoing) | call_id=$callId callee=$otherUsername');
        _setState(CallState(
          status:       CallStatus.waiting,
          callId:       callId,
          roomName:     roomName,
          livekitUrl:   lkUrl,
          token:        freshToken,
          otherUserId:  otherUserId,
          otherUsername: otherUsername,
          otherAvatar:  otherAvatar,
        ));
        // Resume the poll so we detect acceptance without relying on WS alone.
        _startCallerStatusPoll(callId);

      } else if (callStatus == 'calling' && role == 'callee') {
        // We were being ringed. Reconstruct onIncomingCall with known data.
        // If the ARQ timeout already fired (status flipped to "missed" server-side),
        // the /active endpoint returns null and we never reach here.
        _cpLog('RECOVERY', 'checkActiveCall → RESTORE ringing (incoming) | call_id=$callId caller=$otherUsername');
        await onIncomingCall({
          'call_id':        callId,
          'room_name':      roomName,
          'livekit_url':    lkUrl,
          'callee_token':   freshToken,
          'caller_id':      otherUserId,
          'caller_username': otherUsername,
          'caller_avatar':  otherAvatar,
          '_source':        'checkActiveCall',
        });

      } else if (callStatus == 'active') {
        // Call is live — re-join the LiveKit room with a fresh token.
        _cpLog(
          'RECOVERY',
          'checkActiveCall → RESTORE active (reconnecting to LK room) | '
          'call_id=$callId role=$role other=$otherUsername',
        );
        _setState(CallState(
          status:       CallStatus.reconnecting,
          callId:       callId,
          roomName:     roomName,
          livekitUrl:   lkUrl,
          token:        freshToken,
          calleeToken:  role == 'callee' ? freshToken : null,
          otherUserId:  otherUserId,
          otherUsername: otherUsername,
          otherAvatar:  otherAvatar,
          acceptedAt:   acceptedAt,
        ));
        // Sync elapsed timer immediately so the call-screen shows real duration.
        if (acceptedAt != null) {
          final alreadyElapsed = DateTime.now().toUtc().difference(acceptedAt.toUtc());
          if (alreadyElapsed.inMilliseconds > 0) elapsed.value = alreadyElapsed;
          _cpLog('RECOVERY', 'checkActiveCall → elapsed synced | ${alreadyElapsed.inSeconds}s');
        }
        _roomAdapter.joinRoom(livekitUrl: lkUrl, token: freshToken).catchError((e) {
          _cpLog('RECOVERY', 'checkActiveCall _joinRoom ERROR | $e — forcing ended');
          _hangUpLocally(status: CallStatus.ended);
        });

      } else {
        _cpLog('RECOVERY', 'checkActiveCall → unhandled state | status=$callStatus role=$role');
      }
    } catch (e) {
      _cpLog('RECOVERY', 'checkActiveCall FAILED | $e (non-fatal, call proceeds without recovery)');
    }
  }

  /// Single entry point for all call signaling events.
  ///
  /// Parse raw WS/FCM payload → typed [CallSignal] → publish to [callEventStream]
  /// → delegate to existing handler. All signaling sources should eventually
  /// converge here for unified logging, typing, and observability.
  void processEvent(Map<String, dynamic> data) {
    final signal = CallSignal.fromMap(data);
    _cpLog('EVENT', 'processEvent | type=${data["type"]} → ${signal.runtimeType}');

    if (!_eventController.isClosed) {
      _eventController.add(signal);
    }

    switch (signal) {
      case IncomingCallSignal():
        onIncomingCall(signal.toMap());
      case CallAcceptedSignal():
        onCallAccepted({'type': 'call_accepted', 'call_id': signal.callId});
      case CallRejectedSignal():
        onCallRejected();
      case CallEndedSignal():
        onCallEnded();
      case CallMissedSignal():
        onCallMissed(callId: signal.callId);
      case WsConnectedSignal():
        checkActiveCall();
      case IncomingCallTapSignal() ||
            IncomingCallAutoAcceptSignal() ||
            UnknownCallSignal():
        // Handled by IncomingCallOverlay via the raw stream.
        _cpLog('EVENT', 'processEvent: delegated to overlay | type=${data["type"]}');
    }
  }

  // ── Following list for invite modal ───────────────────────────────────────

  Room? get room => _roomAdapter.room;

  // ── Adapter state notifiers (D-7) ─────────────────────────────────────────
  // UI listens to these instead of reading from CallState.
  ValueNotifier<bool> get isSpeaker => _hardware.isSpeaker;
  ValueNotifier<bool> get localVideoEnabled => _roomAdapter.localVideoEnabled;
  ValueNotifier<bool> get remoteVideoEnabled => _roomAdapter.remoteVideoEnabled;

  // ── Video (D-10) — delegate to CallRoomAdapter ───────────────────────────

  Future<void> toggleCamera() => _roomAdapter.toggleCamera();
  Future<void> switchCamera() => _roomAdapter.switchCamera();

  // ── Grup Arama (D-9) — delegate to GroupCallManager ─────────────────────

  Future<void> inviteToCall(int inviteeId) => _groupManager.inviteToCall(inviteeId);
  Future<void> acceptGroupInvite() => _groupManager.acceptGroupInvite();
  Future<void> rejectGroupInvite() => _groupManager.rejectGroupInvite();

  /// Grup aramasına davet yoluyla katılan misafirin gruptan ayrılması.
  /// endCall()'dan farklı olarak aramayı herkes için bitirmez — sadece kendisi ayrılır.
  Future<void> leaveGroupCall() => _groupManager.leaveGroupCall();

  Future<void> removeParticipant(int userId) => _groupManager.removeParticipant(userId);
  void onGroupInviteReceived(Map<String, dynamic> data) => _groupManager.onGroupInviteReceived(data);
  void onParticipantJoined(Map<String, dynamic> data) => _groupManager.onParticipantJoined(data);
  void onParticipantLeft(Map<String, dynamic> data) => _groupManager.onParticipantLeft(data);
  void onParticipantRemoved(Map<String, dynamic> data) => _groupManager.onParticipantRemoved(data);
  void onParticipantRejected(Map<String, dynamic> data) => _groupManager.onParticipantRejected(data);
  void onParticipantTimeout(Map<String, dynamic> data) => _groupManager.onParticipantTimeout(data);
}
