import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:audio_session/audio_session.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../hardware/call_hardware_adapter.dart';
import '../notif/call_notif_adapter.dart';
import '../state/call_state.dart';
import '../state/call_status.dart';

// Manages the LiveKit Room lifecycle and translates LiveKit events into
// domain callbacks (onConnected, endCall, setState).
class CallRoomAdapter {
  final CallHardwareAdapter hardware;
  final ValueNotifier<bool> preventCallScreenAutoOpen;
  final CallState Function() getState;
  final void Function(CallState) setState;
  final void Function(String context) onConnected;
  final void Function() endCall;

  CallRoomAdapter({
    required this.hardware,
    required this.preventCallScreenAutoOpen,
    required this.getState,
    required this.setState,
    required this.onConnected,
    required this.endCall,
  });

  // ── Media state notifiers (D-7) ───────────────────────────────────────────
  // Owned by adapter; CallService exposes via getters. UI listens directly.
  final ValueNotifier<bool> localVideoEnabled = ValueNotifier<bool>(false);
  final ValueNotifier<bool> remoteVideoEnabled = ValueNotifier<bool>(false);

  Room? _room;
  Function? _roomEventsSubscription;
  StreamSubscription<AudioInterruptionEvent>? _audioInterruptionSub;
  Timer? _peerTimeoutTimer;
  bool _isJoiningRoom = false;

  Room? get room => _room;
  bool get isJoiningRoom => _isJoiningRoom;

  void _log(String phase, String msg) =>
      debugPrint('[CALL_PROCESS][${DateTime.now().toIso8601String()}][$phase] $msg');

  // ── joinRoom ──────────────────────────────────────────────────────────────

  Future<void> joinRoom({
    required String livekitUrl,
    required String token,
  }) async {
    if (_isJoiningRoom) {
      _log('LK', '_joinRoom SKIPPED — already joining (double call guard)');
      return;
    }
    _isJoiningRoom = true;
    _room = Room();

    // callStatus'u snapshot alıyoruz — async boyunca değişebilir
    final callStatusAtEntry = getState().status;
    final isCalleeRole = callStatusAtEntry == CallStatus.connecting;

    try {
      _log('LK', '_joinRoom starting | url=$livekitUrl tokenLen=${token.length} status=$callStatusAtEntry isCallee=$isCalleeRole');

      // ── Android Callee: notify CallKit UI that call is connected ───────────
      // iOS: CallKit audio session lifecycle is handled by the adapter's waitForCallkitAudio().
      if (Platform.isAndroid && isCalleeRole && getState().callId != null) {
        final uuid = CallNotifAdapter.formatCallId(getState().callId!.toString());
        _log('LK', 'Android callee: onCallConnected | uuid=$uuid');
        await hardware.onCallConnected(uuid);
      }

      // ── Ağ bağlantısı (audio session gerektirmez) ────────────────────────────
      // Opus DTX (Discontinuous Transmission): sessizlikte paket gönderilmez → %40 bant genişliği tasarrufu.
      // audioBitrate=16000: WhatsApp-grade voice quality (12kbps telephone / 16kbps HD voice / 48kbps music).
      const audioPublishOpts = AudioPublishOptions(dtx: true, audioBitrate: 16000);
      _log('LK', 'room.connect() → calling LiveKit | dtx=true bitrate=16kbps e2ee=false');

      await _room!.connect(
        livekitUrl,
        token,
        roomOptions: RoomOptions(
          defaultAudioOutputOptions: const AudioOutputOptions(speakerOn: false),
          defaultAudioPublishOptions: audioPublishOpts,
        ),
      );
      _log('LK', 'room.connect() SUCCESS');

      // ── iOS Callee: wait for CallKit didActivateAudioSession ───────────────
      if (Platform.isIOS && isCalleeRole) {
        _log('LK', 'iOS callee: waitForCallkitAudio');
        await hardware.waitForCallkitAudio();
      }

      // ── Audio session + mic: Rol bazlı aktivasyon ─────────────────────────────
      // CALLEE: LK bağlantısından sonra hemen ses oturumunu yapılandır ve miki aç.
      // CALLER pre-connect: ATLA — ringtone ses oturumu aktifken voice-chat ayarı
      //   onu keser. Mikrofon ve ses oturumu, callee kabul ettikten sonra
      //   onCallAccepted() içinde etkinleştirilir.
      if (isCalleeRole) {
        try {
          final speakerTarget = preventCallScreenAutoOpen.value;
          _log('LK', 'configureVoiceChat | role=callee speakerEnabled=$speakerTarget');
          await hardware.configureVoiceChat(speakerEnabled: speakerTarget);
          _log('LK', 'configureVoiceChat OK | role=callee');
        } catch (e) {
          _log('LK', 'configureVoiceChat ERROR | role=callee $e');
        }
        _log('LK', 'setMicrophoneEnabled(true) calling | role=callee');
        _log('HW', 'microphone ENABLE | context=_joinRoom-callee');
        await _room!.localParticipant?.setMicrophoneEnabled(true);
        _log('LK', 'setMicrophoneEnabled(true) done | role=callee');
        await Future.delayed(const Duration(milliseconds: 300));
        final speakerTargetPostMic = preventCallScreenAutoOpen.value;
        _log('HW', 'speakerphone SET | enabled=$speakerTargetPostMic context=_joinRoom-callee-post-mic');
        await hardware.setSpeaker(speakerTargetPostMic);
      } else {
        // Network-only pre-connect (caller=calling veya callee=ringing): standart ses atlandı.
        // callStatusAtEntry: caller=calling, callee-pre-connect=ringing

        if (callStatusAtEntry == CallStatus.waiting) {
          // Both platforms: network-only pre-connect — mic starts on acceptance via standard path.
          // Android pre-publish (muted track for fast unmute) was removed: it took
          // AUDIOFOCUS_GAIN via STREAM_VOICE_CALL which starved the ringback player, causing
          // it to stop after one loop. The ~1s acceptance latency is preferable to broken audio.
          // iOS: room.connect() overrides AVAudioSession → ringback restore needed.
          // Android: room.connect() has no audio-session effect → no restore needed.
          _log('LK', 'caller pre-connect: network-only (no mic pre-publish) | callId=${getState().callId}');
          _log('HW', 'microphone SKIPPED (caller pre-connect) | ringback=preserved mic-will-start-on-acceptance');
          if (Platform.isIOS) {
            // room.connect() internally overrides AVAudioSession to SoloAmbient → ringback stops.
            // resumeAfterRoomConnect() restores playAndRecord/voiceChat and resumes ringback.
            final postConnectStatus = getState().status;
            if (postConnectStatus == CallStatus.waiting || postConnectStatus == CallStatus.connecting) {
              await hardware.resumeAfterRoomConnect();
            }
          }
        } else {
          // callee pre-connect (ringing): ringtone korunuyor, mic yok
          _log('LK', 'AudioSession/mic SKIPPED | preConnectRole=${callStatusAtEntry.name} (ringtone preserved)');
        }

        // Kenar durum: accept/onCallAccepted bu room.connect() sırasında tetiklendiyse.
        if (getState().status == CallStatus.connecting) {
          if (callStatusAtEntry == CallStatus.ringing) {
            // Callee pre-connect: acceptCall, room.connect() sırasında geldi.
            // activateCalleeAudio iOS audio session + mic'i doğru sırayla açar.
            _log('LK', 'callee pre-connect: accept fired during room.connect() → _activateCalleeAudio');
            activateCalleeAudio().catchError((e) {
              _log('LK', '_activateCalleeAudio ERROR (pre-connect edge case) | $e');
            });
          } else {
            // Caller: onCallAccepted, room.connect() sırasında geldi.
            // Pre-publish yoksa (standard path) setMicrophoneEnabled çağrılır.
            _log('LK', 'caller: call_accepted already received during pre-connect → enabling mic');
            final micPubs = _room!.localParticipant?.audioTrackPublications;
            if (micPubs != null && micPubs.isNotEmpty) {
              final pub = micPubs.first;
              if (pub.muted) {
                _log('HW', 'microphone UNMUTE | context=_joinRoom-caller-late-accept fastPath=true stopOnMute=false');
                await pub.unmute(stopOnMute: false);
                _log('LK', 'caller mic unmuted (late-accept-during-preconnect) | done');
              } else {
                _log('LK', 'caller: pre-published track already unmuted | done');
              }
            } else {
              // Pre-publish çalışmadıysa standard yol
              _log('LK', 'caller late-accept: no pre-published track → standard setMicEnabled');
              _log('HW', 'microphone ENABLE | context=_joinRoom-caller-late-accept standardPath=true');
              await _room!.localParticipant?.setMicrophoneEnabled(true);
              _log('LK', 'caller mic enabled (late, accepted-during-preconnect, standard) | done');
            }
          }
        }
      }

      _roomEventsSubscription = _room!.events.listen(_onRoomEvent);

      bool peerAlreadyJoined = _room!.remoteParticipants.isNotEmpty;
      _log('LK', 'peerAlreadyJoined=$peerAlreadyJoined status=${getState().status.name}');
      if (peerAlreadyJoined) {
        _peerTimeoutTimer?.cancel();
        // Callee pre-connect sırasında (ringing) arayan oda da olabilir.
        // Kullanıcı kabul etmeden connected set etme.
        if (getState().status == CallStatus.ringing) {
          _log('LK', 'peerAlreadyJoined during callee pre-connect (ringing) → waiting for acceptCall');
        } else {
          // Peer odada ama ses track'ı henüz subscribe edilmemiş olabilir.
          // connected state'i TrackSubscribed'da set edilecek — gerçek ses akışını bekle.
          final anyAudioSubscribed = _room!.remoteParticipants.values.any(
            (p) => p.trackPublications.values.any(
              (pub) => pub.subscribed && pub.kind == TrackType.AUDIO,
            ),
          );
          if (anyAudioSubscribed) {
            _log('LK', 'peerAlreadyJoined + audioSubscribed → connected immediately');
            onConnected('peerAlreadyJoined');
          } else {
            _log('LK', 'peerAlreadyJoined but audio not yet subscribed → waiting for TrackSubscribed');
          }
        }
      } else {
        _log('LK', 'joined LiveKit → waiting for peer (ParticipantConnectedEvent)');
        _peerTimeoutTimer?.cancel();
        // Callee pre-connect sırasında (ringing) peer timeout başlatma.
        // Kullanıcı reddetse zaten reset() timeout'u iptal eder; gereksiz endCall riski var.
        if (getState().status != CallStatus.ringing) {
          _log('LK', 'peerTimeoutTimer started | 40s');
          _peerTimeoutTimer = Timer(const Duration(seconds: 40), () {
            if (_room != null && _room!.remoteParticipants.isEmpty) {
              _log('LK', 'peerTimeoutTimer FIRED → peer did not join in 40s → endCall | status=${getState().status}');
              endCall();
            }
          });
        } else {
          _log('LK', 'peerTimeoutTimer SKIPPED during callee pre-connect (ringing)');
        }
      }

      _log('HW', 'wakelock ENABLE | reason=_joinRoom-complete status=${getState().status.name}');
      await WakelockPlus.enable();

      _isJoiningRoom = false;
      _log('LK', '_joinRoom complete | _isJoiningRoom reset');
      await _setupAudioInterruptionListener();
    } catch (e) {
      _log('LK', '_joinRoom EXCEPTION | $e');
      _isJoiningRoom = false;
      // Pre-connect failure (ringing/calling): user hasn't accepted yet — preserve the call.
      // The CallKit screen stays visible; acceptCall() will retry _joinRoom with a fresh token.
      if (callStatusAtEntry == CallStatus.ringing || callStatusAtEntry == CallStatus.waiting) {
        _log('LK', '_joinRoom EXCEPTION in pre-connect ($callStatusAtEntry) — call preserved');
      } else {
        endCall();
      }
    }
  }

  // ── activateCalleeAudio ───────────────────────────────────────────────────

  /// Callee pre-connect sonrası audio session + mic aktivasyonu.
  /// Çağrıldığında _room bağlı olmalı; iOS'ta CallKit audio session sinyali beklenir.
  Future<void> activateCalleeAudio() async {
    final activateStartAt = DateTime.now();
    _log('IN', '_activateCalleeAudio START | status=${getState().status} startUtc=${activateStartAt.toUtc().toIso8601String()}');

    if (Platform.isIOS) {
      await hardware.waitForCallkitAudio();
      final s = getState().status;
      if (s == CallStatus.ended || s == CallStatus.idle) {
        _log('IN', '_activateCalleeAudio: call already ended after audio wait — aborting | status=${s.name}');
        return;
      }
    } else if (Platform.isAndroid && getState().callId != null) {
      final uuid = CallNotifAdapter.formatCallId(getState().callId!.toString());
      _log('IN', '_activateCalleeAudio: Android onCallConnected | uuid=$uuid');
      await hardware.onCallConnected(uuid);
    }

    try {
      _log('IN', '_activateCalleeAudio: configureVoiceChat');
      final speakerTarget = preventCallScreenAutoOpen.value;
      await hardware.configureVoiceChat(speakerEnabled: speakerTarget);
      _log('IN', '_activateCalleeAudio: configureVoiceChat OK | speakerEnabled=$speakerTarget');
    } catch (e) {
      _log('IN', '_activateCalleeAudio: configureVoiceChat ERROR | $e');
    }

    _log('IN', '_activateCalleeAudio: setMicrophoneEnabled(true)');
    _log('HW', 'microphone ENABLE | context=_activateCalleeAudio');
    await _room?.localParticipant?.setMicrophoneEnabled(true);
    await Future.delayed(const Duration(milliseconds: 300));
    final speakerTargetPostMic = preventCallScreenAutoOpen.value;
    _log('HW', 'speakerphone SET | enabled=$speakerTargetPostMic context=_activateCalleeAudio-post-mic swipeLive=$speakerTargetPostMic');
    await hardware.setSpeaker(speakerTargetPostMic);
    final totalMs = DateTime.now().difference(activateStartAt).inMilliseconds;
    _log('IN', '_activateCalleeAudio DONE | totalMs=$totalMs');

    // Pre-connect sırasında (ringing) TrackSubscribed skipped edildi.
    // Şimdi connecting state'indeyiz; remote audio zaten subscribe edilmişse
    // yeni TrackSubscribed gelmez → burada kontrol et.
    if (getState().status == CallStatus.connecting && _room != null) {
      final anyAudioSubscribed = _room!.remoteParticipants.values.any(
        (p) => p.trackPublications.values.any(
          (pub) => pub.subscribed && pub.kind == TrackType.AUDIO,
        ),
      );
      _log('IN', '_activateCalleeAudio: post-audio check | anyAudioSubscribed=$anyAudioSubscribed');
      if (anyAudioSubscribed) {
        _log('LK', '_activateCalleeAudio: remote audio already subscribed → connected immediately');
        onConnected('activateCalleeAudio-alreadySubscribed');
        if (Platform.isAndroid) {
          final speakerTarget = preventCallScreenAutoOpen.value;
          _log('HW', 'speakerphone SET | enabled=$speakerTarget context=_activateCalleeAudio-already-subscribed swipeLive=$speakerTarget');
          Hardware.instance.setSpeakerphoneOn(speakerTarget);
          hardware.isSpeaker.value = speakerTarget;
        }
      }
    }
  }

  // ── _onRoomEvent ──────────────────────────────────────────────────────────

  void _onRoomEvent(RoomEvent event) {
    _log('LK', 'roomEvent | ${event.runtimeType}');
    if (event is RoomDisconnectedEvent) {
      final s = getState().status;
      // Only call endCall() from an active-call state. Terminal states (ended, idle)
      // and callee pre-connect (ringing) reach here via reset()/_disconnectRoom()
      // cleanup — calling endCall() would double-post /end.
      if (s == CallStatus.idle ||
          s == CallStatus.ended ||
          s == CallStatus.ringing) {
        _log('LK', 'RoomDisconnected SKIPPED | status=${s.name} (terminal or pre-connect — cleanup-triggered disconnect)');
        return;
      }
      _log('LK', 'RoomDisconnected → endCall | status=${s.name}');
      endCall();
    } else if (event is RoomReconnectingEvent) {
      setState(getState().copyWith(status: CallStatus.reconnecting));
    } else if (event is RoomReconnectedEvent) {
      if (getState().status == CallStatus.reconnecting) {
        setState(getState().copyWith(status: CallStatus.active));
      }
    } else if (event is ParticipantConnectedEvent) {
      _log('LK', 'ParticipantConnected → peer joined | peerCount=${_room?.remoteParticipants.length} status=${getState().status.name}');
      _peerTimeoutTimer?.cancel();
      // Mic sadece connecting state'inde açılır — kabul sonrası ses aktivasyon aşaması.
      // calling: caller pre-connect (kabul bekleniyor) → mic kapalı kalmalı.
      // ringing: callee pre-connect (kullanıcı henüz kabul etmedi) → mic kapalı kalmalı.
      // connecting: call_accepted geldi, ses aktivasyonu başladı → mic açılabilir.
      // connected: mic zaten açık, tekrar açmaya gerek yok.
      if (getState().status == CallStatus.connecting) {
        final micPubs = _room?.localParticipant?.audioTrackPublications;
        if (micPubs == null || micPubs.isEmpty) {
          _log('LK', 'ParticipantConnected: mic not yet published → enabling now');
          _log('HW', 'microphone ENABLE | context=ParticipantConnected-mic-not-published status=connecting');
          _room?.localParticipant?.setMicrophoneEnabled(true);
        } else {
          _log('HW', 'microphone ALREADY ENABLED | context=ParticipantConnected pubCount=${micPubs.length}');
        }
      } else {
        _log('LK', 'ParticipantConnected: mic enable SKIPPED | status=${getState().status.name} (pre-connect guard)');
        _log('HW', 'microphone ENABLE SKIPPED | context=ParticipantConnected status=${getState().status.name}');
      }
    } else if (event is TrackSubscribedEvent) {
      // Uzak ses track'ı abone oldu → callee'nin sesi gerçekten akıyor.
      // 1. AudioSession → voice-chat mode (ringtone session'dan geçiş)
      // 2. Ringtone durdur
      // 3. connected state → _handleStatusChange stops _audioPlayer (ringing.wav)
      _log('LK', 'TrackSubscribed | kind=${event.track.kind} status=${getState().status.name}');
      if (event.track.kind == TrackType.AUDIO) {
        // ringing: callee pre-connect — caller'ın muted track'i subscribe edildi.
        // calling: callee pre-connect sırasında arayan bekliyorken callee muted track publish eder.
        // Her iki durumda da AudioSession ve ringtone'a dokunma — callee henüz kabul etmedi.
        // Gerçek geçiş: calling→connecting (call_accepted WS), ringing→connecting (acceptCall).
        // connecting→connected TrackUnmutedEvent (callee unmutes) veya yeni TrackSubscribed ile olur.
        if (getState().status == CallStatus.ringing || getState().status == CallStatus.waiting) {
          _log('LK', 'TrackSubscribed AUDIO during ${getState().status.name} (pre-connect) | muted track subscribed → skip AudioSession configure + ringtone stop');
          return;
        }

        // Muted track subscription: gerçek ses henüz akmıyor → TrackUnmuted'ı bekle.
        // Nadir senaryo: ağ gecikmesi veya callee mic warmup sırasında track muted gelebilir.
        if (event.publication.muted) {
          _log('LK', 'TrackSubscribed AUDIO but muted | status=${getState().status.name} → wait for TrackUnmuted');
          return;
        }

        _log('LK', 'TrackSubscribed AUDIO (unmuted) → voice AudioSession → ringing stop → connected');
        // Configure audio session asynchronously before transition so audio routing is ready.
        // iOS: speakerphone state update happens inside configureVoiceChat callback.
        // Android: speakerphone is set synchronously in the block below.
        Future(() async {
          try {
            final speakerTarget = preventCallScreenAutoOpen.value;
            _log('HW', 'configureVoiceChat | context=TrackSubscribed speakerEnabled=$speakerTarget');
            await hardware.configureVoiceChat(speakerEnabled: speakerTarget);
            if (Platform.isIOS) {
              hardware.isSpeaker.value = speakerTarget;
            }
            _log('LK', 'TrackSubscribed: configureVoiceChat OK');
          } catch (e) {
            _log('LK', 'TrackSubscribed: configureVoiceChat ERROR | $e');
          }
        });
        if (getState().status == CallStatus.waiting || getState().status == CallStatus.connecting) {
          final preTransitionStatus = getState().status;
          onConnected('TrackSubscribed-${preTransitionStatus.name}');
          // P0 FIX: iOS caller mic race.
          // iOS skips mic pre-publish during pre-connect (to preserve ringback AVAudioSession).
          // call_accepted WS arrives ~1.65s AFTER TrackSubscribed, so we must enable mic HERE
          // instead of waiting for the WS. onCallAccepted will see status=connected and call
          // _ensureMicEnabled as a safety net when the WS finally arrives.
          if (Platform.isIOS && preTransitionStatus == CallStatus.waiting) {
            _log('LK', 'TrackSubscribed: iOS caller mic pre-enable (before WS) | callId=${getState().callId}');
            _log('HW', 'microphone ENABLE | context=TrackSubscribed-iOS-caller-preemptive platform=iOS');
            _room?.localParticipant?.setMicrophoneEnabled(true).catchError((e) {
              _log('LK', 'TrackSubscribed iOS caller mic ERROR | $e');
              return null;
            });
          }
          if (Platform.isAndroid) {
            final speakerTarget = preventCallScreenAutoOpen.value;
            _log('HW', 'speakerphone SET | enabled=$speakerTarget context=TrackSubscribed-Android swipeLive=$speakerTarget');
            hardware.setSpeaker(speakerTarget); // sets hardware.isSpeaker.value
          }
        }
      } else if (event.track.kind == TrackType.VIDEO) {
        _log('LK', 'TrackSubscribed VIDEO | participant=${event.participant.identity}');
        remoteVideoEnabled.value = true;
      }
    } else if (event is TrackUnsubscribedEvent) {
      if (event.track.kind == TrackType.VIDEO) {
        _log('LK', 'TrackUnsubscribed VIDEO | participant=${event.participant.identity}');
        remoteVideoEnabled.value = false;
      }
    } else if (event is TrackMutedEvent) {
      final isRemote = event.participant != _room?.localParticipant;
      _log('LK', 'TrackMuted | kind=${event.publication.kind} isRemote=$isRemote');
      if (isRemote && event.publication.kind == TrackType.VIDEO) {
        _log('LK', 'TrackMuted remote VIDEO → remoteVideoEnabled=false');
        remoteVideoEnabled.value = false;
      }
    } else if (event is TrackUnmutedEvent) {
      // Fallback: a previously-subscribed muted track was unmuted.
      // Android no longer pre-publishes during calling state, so this path is rare.
      // Still handles edge cases (e.g. track re-negotiation, network recovery).
      final isRemote = event.participant != _room?.localParticipant;
      _log('LK', 'TrackUnmuted | kind=${event.publication.kind} isRemote=$isRemote status=${getState().status.name}');
      if (isRemote && event.publication.kind == TrackType.VIDEO) {
        _log('LK', 'TrackUnmuted remote VIDEO → remoteVideoEnabled=true');
        remoteVideoEnabled.value = true;
      } else if (isRemote && event.publication.kind == TrackType.AUDIO && getState().status == CallStatus.connecting) {
        _log('LK', 'TrackUnmuted AUDIO remote → connecting→connected (Android unmuted pre-published track)');
        Future(() async {
          try {
            final speakerTarget = preventCallScreenAutoOpen.value;
            _log('HW', 'configureVoiceChat | context=TrackUnmuted speakerEnabled=$speakerTarget');
            await hardware.configureVoiceChat(speakerEnabled: speakerTarget);
            // configureVoiceChat does not call setSpeaker internally — isSpeaker set below
            if (Platform.isIOS) {
              hardware.isSpeaker.value = speakerTarget;
            }
            _log('LK', 'TrackUnmuted: configureVoiceChat OK');
          } catch (e) {
            _log('LK', 'TrackUnmuted: configureVoiceChat ERROR | $e');
          }
        });
        onConnected('TrackUnmuted');
        if (Platform.isAndroid) {
          final speakerTarget = preventCallScreenAutoOpen.value;
          _log('HW', 'speakerphone SET | enabled=$speakerTarget context=TrackUnmuted-Android swipeLive=$speakerTarget');
          hardware.setSpeaker(speakerTarget); // sets hardware.isSpeaker.value
        }
      }
    } else if (event is LocalTrackPublishedEvent) {
      if (event.publication.kind == TrackType.VIDEO) {
        _log('LK', 'LocalTrackPublished VIDEO');
        localVideoEnabled.value = true;
      }
    } else if (event is TrackPublishedEvent) {
      if (event.publication.kind == TrackType.VIDEO) {
        _log('LK', 'RemoteTrackPublished VIDEO | participant=${event.participant.identity}');
        // remoteVideoEnabled is set in TrackSubscribedEvent when track is actually receivable
      }
    } else if (event is LocalTrackUnpublishedEvent) {
      if (event.publication.kind == TrackType.VIDEO) {
        _log('LK', 'LocalTrackUnpublished VIDEO');
        localVideoEnabled.value = false;
      }
    } else if (event is TrackUnpublishedEvent) {
      if (event.publication.kind == TrackType.VIDEO) {
        _log('LK', 'RemoteTrackUnpublished VIDEO | participant=${event.participant.identity}');
        remoteVideoEnabled.value = false;
      }
    } else if (event is ParticipantConnectionQualityUpdatedEvent) {
      final isLocal = event.participant == _room?.localParticipant;
      final isLost = event.connectionQuality == ConnectionQuality.lost;
      final isPoor = event.connectionQuality == ConnectionQuality.poor || isLost;
      if (isLocal) {
        if (getState().isPoorConnection != isPoor) {
          _log('LK', 'LocalQuality=${event.connectionQuality.name} isPoor=$isPoor');
          setState(getState().copyWith(isPoorConnection: isPoor));
        }
      } else {
        // T9: Remote katılımcının bağlantısı kesiliyorsa peer tarafında da göster.
        // LiveKit RoomReconnecting kendi tarafı için status=reconnecting seti yapıyor.
        // Karşı taraf için isPoorConnection zaten varsa onu yeniden kullan.
        if (getState().isPoorConnection != isPoor) {
          _log('LK', 'RemoteQuality=${event.connectionQuality.name} isPoor=$isPoor → updating isPoorConnection for peer');
          setState(getState().copyWith(isPoorConnection: isPoor));
        }
      }
    }
  }

  // ── _setupAudioInterruptionListener ──────────────────────────────────────

  Future<void> _setupAudioInterruptionListener() async {
    _audioInterruptionSub?.cancel();
    final session = await AudioSession.instance;
    _audioInterruptionSub = session.interruptionEventStream.listen((event) {
      if (event.begin) {
        // Only save/restore mic during active call states where mic is expected to be on.
        // During ringing/calling, isMuted defaults to false but mic was never activated —
        // blindly setting isMuted=true here would cause interruption-end to re-enable the mic.
        final micIsActive = getState().status == CallStatus.active ||
            getState().status == CallStatus.connecting;
        if (micIsActive && !getState().isMuted) {
          _log('HW', 'microphone DISABLE | context=audioInterruption-begin isMuted=false→true');
          _room?.localParticipant?.setMicrophoneEnabled(false);
          setState(getState().copyWith(isMuted: true));
        }
      } else {
        if (getState().isMuted) {
          _log('HW', 'microphone ENABLE | context=audioInterruption-end isMuted=true→false');
          _room?.localParticipant?.setMicrophoneEnabled(true);
          setState(getState().copyWith(isMuted: false));
        }
      }
    });
  }

  // ── disconnect ────────────────────────────────────────────────────────────

  Future<void> disconnect() async {
    _peerTimeoutTimer?.cancel();
    _roomEventsSubscription?.call();
    _audioInterruptionSub?.cancel();
    _isJoiningRoom = false;
    localVideoEnabled.value = false;
    remoteVideoEnabled.value = false;
    if (_room != null) {
      _log('LK', 'room.disconnect() calling');
      await _room!.disconnect();
      _log('LK', 'room.disconnect() done → dispose()');
      await _room!.dispose();
      _room = null;
      _log('LK', 'room disposed | _room=null _isJoiningRoom=false');
    } else {
      _log('LK', '_disconnectRoom: room was already null | _isJoiningRoom=false');
    }
  }

  // ── Mic/Video track control (D-10) ────────────────────────────────────────

  /// Caller mic activation on call_accepted. Two paths:
  /// FAST PATH — pre-published muted track exists → unmute.
  /// STANDARD PATH — no pre-publish → setMicrophoneEnabled(true).
  void activateCallerMic() {
    if (_room == null) {
      _log('HW', 'microphone ACTIVATE SKIPPED | context=activateCallerMic room=null');
      return;
    }
    final micPubs = _room!.localParticipant?.audioTrackPublications;
    if (micPubs != null && micPubs.isNotEmpty) {
      final pub = micPubs.first;
      if (pub.muted) {
        _log('HW', 'microphone UNMUTE | context=activateCallerMic fastPath=true stopOnMute=false');
        pub.unmute(stopOnMute: false).catchError((e) {
          _log('HW', 'microphone ENABLE (unmute-fallback) | context=activateCallerMic');
          _room!.localParticipant?.setMicrophoneEnabled(true);
          return null;
        });
      } else {
        _log('HW', 'microphone ALREADY ENABLED+UNMUTED | context=activateCallerMic pub.sid=${pub.sid}');
      }
    } else {
      _log('HW', 'microphone ENABLE | context=activateCallerMic standardPath=true (no publications)');
      _room!.localParticipant?.setMicrophoneEnabled(true).catchError((e) {
        _log('HW', 'microphone ENABLE ERROR | context=activateCallerMic $e');
        return null;
      });
    }
  }

  /// Mic state recovery for iOS race condition: WS arrived after TrackSubscribed.
  /// No-op if room is null or mic is already enabled.
  void ensureMicEnabled(String context) {
    if (_room == null) {
      _log('HW', 'microphone ENSURE SKIPPED | context=$context room=null');
      return;
    }
    final micPubs = _room!.localParticipant?.audioTrackPublications;
    if (micPubs == null || micPubs.isEmpty) {
      _log('HW', 'microphone ENABLE | context=$context standardPath=true (no publications)');
      _room!.localParticipant?.setMicrophoneEnabled(true).catchError((e) {
        _log('HW', 'microphone ENABLE ERROR | context=$context $e');
        return null;
      });
      return;
    }
    final pub = micPubs.first;
    if (pub.muted) {
      _log('HW', 'microphone UNMUTE | context=$context fastPath=true pub.sid=${pub.sid}');
      pub.unmute(stopOnMute: false).catchError((e) {
        _log('HW', 'microphone ENABLE (unmute-fallback) | context=$context $e');
        _room!.localParticipant?.setMicrophoneEnabled(true);
        return null;
      });
    } else {
      _log('HW', 'microphone ALREADY ENABLED+UNMUTED | context=$context pub.sid=${pub.sid}');
    }
  }

  Future<void> toggleCamera() async {
    if (_room == null || getState().status != CallStatus.active) {
      _log('VIDEO', 'toggleCamera: SKIPPED | room=${_room != null} status=${getState().status.name}');
      return;
    }
    final enabled = localVideoEnabled.value;
    _log('VIDEO', 'toggleCamera | current=$enabled → ${!enabled}');
    localVideoEnabled.value = !enabled;
    try {
      await _room!.localParticipant?.setCameraEnabled(!enabled);
    } catch (e) {
      _log('VIDEO', 'toggleCamera ERROR | $e');
      localVideoEnabled.value = enabled; // revert
    }
  }

  Future<void> switchCamera() async {
    if (_room == null || !localVideoEnabled.value) {
      _log('VIDEO', 'switchCamera: SKIPPED | roomNull=${_room == null} videoEnabled=${localVideoEnabled.value}');
      return;
    }
    _log('VIDEO', 'switchCamera invoked');
    try {
      final pub = _room!.localParticipant?.videoTrackPublications
          .firstWhere((p) => p.source == TrackSource.camera);
      if (pub?.track is LocalVideoTrack) {
        final cameras = await Hardware.instance.videoInputs();
        _log('VIDEO', 'switchCamera | available=${cameras.length}');
        if (cameras.length < 2) return;
        final currentId = (pub!.track as LocalVideoTrack).mediaStreamTrack.getSettings()['deviceId'] as String?;
        final next = cameras.firstWhere(
          (c) => c.deviceId != currentId,
          orElse: () => cameras.first,
        );
        await (pub.track as LocalVideoTrack).switchCamera(next.deviceId);
        _log('VIDEO', 'switchCamera OK | device=${next.label}');
      }
    } catch (e) {
      _log('VIDEO', 'switchCamera ERROR | $e');
    }
  }
}
