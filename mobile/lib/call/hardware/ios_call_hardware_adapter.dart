import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:audioplayers/audioplayers.dart' hide AVAudioSessionCategory;
import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:livekit_client/livekit_client.dart' show Hardware;
import 'package:permission_handler/permission_handler.dart';
import 'package:vibration/vibration.dart';
import '../state/end_reason.dart';
import 'call_hardware_adapter.dart';

class IosCallHardwareAdapter extends CallHardwareAdapter {
  // ── Audio players ───────────────────────────────────────────────────────────

  // Pre-loaded ringback (caller ringing.wav — loop).
  final _ringbackPlayer = AudioPlayer();
  bool _ringbackPreloaded = false;

  // One-shot sounds: busy.wav, ended.wav, weak.wav.
  final _audioPlayer = AudioPlayer();

  // iOS ringtone loop timer (FlutterRingtonePlayer doesn't support true looping on iOS).
  Timer? _ringtoneLoopTimer;

  // ── CallKit audio session lifecycle ─────────────────────────────────────────

  // Set to true when didActivateAudioSession fires; prevents Completer miss on
  // early signal (action.fulfill() fires synchronously before Flutter is ready).
  bool _audioSessionActivated = false;

  // Completed when didActivateAudioSession is received.
  Completer<void>? _callkitAudioReady;

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  @override
  Future<void> init() async {
    await _preloadRingback();
    await _prewarmAudioSession();
  }

  Future<void> _preloadRingback() async {
    try {
      await _ringbackPlayer.setReleaseMode(ReleaseMode.loop);
      await _ringbackPlayer.setAudioContext(ap.AudioContext(
        iOS: ap.AudioContextIOS(
          category: ap.AVAudioSessionCategory.playAndRecord,
          options: {
            ap.AVAudioSessionOptions.allowBluetooth,
            ap.AVAudioSessionOptions.allowBluetoothA2DP,
          },
        ),
      ));
      await _ringbackPlayer.setSource(ap.AssetSource('sounds/ringing.wav'));
      _ringbackPreloaded = true;
      log('SOUND', 'ringing.wav PRE-LOADED in ringbackPlayer | ready for instant resume()');
    } catch (e) {
      log('SOUND', 'ringing.wav pre-load FAILED | $e → fallback to play(AssetSource)');
    }
  }

  Future<void> _prewarmAudioSession() async {
    try {
      log('HW', 'audioSession PRE-WARM (iOS) | category=soloAmbient');
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.soloAmbient,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
      ));
    } catch (e) {
      log('HW', 'audioSession pre-warm ERROR | $e');
    }
  }

  @override
  void dispose() {
    _ringtoneLoopTimer?.cancel();
    _ringbackPlayer.dispose();
    _audioPlayer.dispose();
    FlutterRingtonePlayer().stop();
    Vibration.cancel();
  }

  @override
  void resetAfterCall() {
    _audioSessionActivated = false;
    _callkitAudioReady = null;
  }

  // ── Permissions ─────────────────────────────────────────────────────────────

  @override
  Future<PermissionStatus> requestMicPermission() async {
    final status = await Permission.microphone.request();
    log('PERM', 'mic permission | status=${status.name}');
    return status;
  }

  // ── Audio session ───────────────────────────────────────────────────────────

  @override
  Future<void> setupAudioSession() async {
    try {
      log('HW', 'audioSession CONFIGURE | context=dialing category=playAndRecord mode=voiceChat');
      final session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionMode: AVAudioSessionMode.voiceChat,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.allowBluetooth |
            AVAudioSessionCategoryOptions.allowBluetoothA2dp,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.sonification,
          flags: AndroidAudioFlags.none,
          usage: AndroidAudioUsage.voiceCommunication,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransientMayDuck,
        androidWillPauseWhenDucked: false,
      ));
      log('HW', 'speakerphone SET | enabled=false context=dialing');
      await Hardware.instance.setSpeakerphoneOn(false);
    } catch (e) {
      log('HW', 'audioSession CONFIGURE ERROR | context=dialing $e');
    }
  }

  @override
  Future<void> teardownAudioSession() async {
    try {
      log('HW', 'audioSession DEACTIVATE | platform=iOS');
      final session = await AudioSession.instance;
      await session.setActive(false);
    } catch (e) {
      log('HW', 'audioSession DEACTIVATE ERROR | $e');
    }
  }

  @override
  Future<void> resumeAfterRoomConnect() async {
    // room.connect() internally overrides AVAudioSession to soloAmbient → ringback stops.
    // Restore playAndRecord/voiceChat and resume ringback if it was interrupted.
    try {
      log('HW', 'audioSession CONFIGURE | context=resumeAfterRoomConnect category=playAndRecord');
      final session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionMode: AVAudioSessionMode.voiceChat,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.allowBluetooth |
            AVAudioSessionCategoryOptions.allowBluetoothA2dp,
      ));
      if (_ringbackPlayer.state != PlayerState.playing) {
        await _ringbackPlayer.setReleaseMode(ReleaseMode.loop);
        await _ringbackPlayer.seek(Duration.zero);
        await _ringbackPlayer.resume();
        log('SOUND', 'ringbackPlayer RESUMED after LiveKit SoloAmbient override');
      } else {
        log('SOUND', 'ringbackPlayer STILL PLAYING after room.connect() (no interruption)');
      }
    } catch (e) {
      log('SOUND', 'resumeAfterRoomConnect ERROR | $e');
    }
  }

  @override
  Future<void> configureVoiceChat({required bool speakerEnabled}) async {
    try {
      log('HW', 'audioSession CONFIGURE | context=voiceChat category=playAndRecord mode=voiceChat');
      final session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionMode: AVAudioSessionMode.voiceChat,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.allowBluetooth |
            AVAudioSessionCategoryOptions.allowBluetoothA2dp,
      ));
      log('HW', 'speakerphone SET | enabled=$speakerEnabled context=configureVoiceChat');
      await Hardware.instance.setSpeakerphoneOn(speakerEnabled);
    } catch (e) {
      log('HW', 'configureVoiceChat ERROR | $e');
    }
  }

  // ── Ringback ─────────────────────────────────────────────────────────────────

  @override
  void startRingback() {
    // iOS: 600ms delay before ringback so audio session settles.
    Future.delayed(const Duration(milliseconds: 600), () async {
      try {
        if (_ringbackPreloaded) {
          log('SOUND', 'ringbackPlayer RESUME (pre-loaded) | ringing.wav instant start');
          log('HW', 'ringbackPlayer PLAY | mode=loop pre-loaded=true device=earpiece');
          await _ringbackPlayer.setReleaseMode(ReleaseMode.loop);
          await _ringbackPlayer.seek(Duration.zero);
          await _ringbackPlayer.resume();
        } else {
          log('SOUND', 'ringbackPlayer PLAY (fallback, not pre-loaded) | ringing.wav');
          log('HW', 'ringbackPlayer PLAY | mode=loop pre-loaded=false device=earpiece');
          await _ringbackPlayer.setReleaseMode(ReleaseMode.loop);
          await _ringbackPlayer.play(ap.AssetSource('sounds/ringing.wav'));
        }
      } catch (e) {
        log('SOUND', 'startRingback ERROR | $e');
      }
    });
  }

  @override
  void stopRingback() {
    log('HW', 'ringbackPlayer STOP');
    _ringbackPlayer.stop();
  }

  // ── Ringer / vibration ───────────────────────────────────────────────────────

  @override
  void playNotification() {
    log('SOUND', 'playNotification triggered');
    FlutterRingtonePlayer().playNotification();
  }

  @override
  void startRinger() {
    log('SOUND', 'startRingtoneAndVibration CALLED (iOS)');
    FlutterRingtonePlayer().playRingtone(looping: true);
    _ringtoneLoopTimer?.cancel();
    _ringtoneLoopTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      FlutterRingtonePlayer().playRingtone();
    });
  }

  @override
  void stopRinger() {
    log('HW', 'ringtonePlayer STOP');
    _ringtoneLoopTimer?.cancel();
    _ringtoneLoopTimer = null;
    FlutterRingtonePlayer().stop();
    log('HW', 'haptic CANCEL');
    Vibration.cancel();
  }

  // ── End-of-call sounds ───────────────────────────────────────────────────────

  @override
  void playEndedSound({required bool wasConnected, EndReason? endReason}) {
    if (endReason == EndReason.busy || endReason == EndReason.rejected) {
      log('HW', 'audioPlayer PLAY | source=busy.wav endReason=$endReason');
      log('SOUND', 'busy.wav PLAY | endReason=$endReason');
      _audioPlayer.setReleaseMode(ReleaseMode.release);
      _audioPlayer.play(AssetSource('sounds/busy.wav'));
    } else if (wasConnected) {
      log('HW', 'audioPlayer PLAY | source=ended.wav wasConnected=true');
      log('SOUND', 'ended.wav PLAY | wasConnected=true');
      _audioPlayer.setReleaseMode(ReleaseMode.release);
      _audioPlayer.play(AssetSource('sounds/ended.wav'));
    } else {
      log('HW', 'audioPlayer STOP | ended-without-connection');
      log('SOUND', 'audioPlayer.stop | ended without connection');
      _audioPlayer.stop();
    }
  }

  @override
  void playWeakSound() {
    log('HW', 'audioPlayer PLAY | source=weak.wav poorConnection=true');
    log('SOUND', 'weak.wav PLAY | poorConnection detected');
    _audioPlayer.setReleaseMode(ReleaseMode.release);
    _audioPlayer.play(AssetSource('sounds/weak.wav'));
  }

  @override
  void stopAllSounds() {
    log('HW', 'ringbackPlayer STOP | context=stopAllSounds');
    _ringbackPlayer.stop();
    log('HW', 'audioPlayer STOP | context=stopAllSounds');
    _audioPlayer.stop();
  }

  // ── Speakerphone ─────────────────────────────────────────────────────────────

  @override
  Future<void> setSpeaker(bool enabled) async {
    try {
      log('HW', 'speakerphone SET | enabled=$enabled');
      await Hardware.instance.setSpeakerphoneOn(enabled);
    } catch (e) {
      log('HW', 'speakerphone SET ERROR | enabled=$enabled $e');
    }
  }

  // ── iOS CallKit audio lifecycle ──────────────────────────────────────────────

  @override
  void onAudioSessionActivated() {
    _audioSessionActivated = true;
    log('LK', 'audioSessionActivated received | completerReady=${_callkitAudioReady != null}');
    if (_callkitAudioReady != null && !_callkitAudioReady!.isCompleted) {
      _callkitAudioReady!.complete();
    }
  }

  @override
  Future<void> waitForCallkitAudio() async {
    if (_audioSessionActivated) {
      log('HW', 'didActivateAudioSession flag=true → no wait | waitMs=0');
      return;
    }
    _callkitAudioReady ??= Completer<void>();
    final waitStart = DateTime.now();
    log('HW', 'didActivateAudioSession WAITING | callkitAudioReady created maxWait=4s');
    await _callkitAudioReady!.future.timeout(
      const Duration(seconds: 4),
      onTimeout: () {
        final ms = DateTime.now().difference(waitStart).inMilliseconds;
        log('HW', 'didActivateAudioSession TIMEOUT | waitMs=$ms → proceeding');
      },
    );
    final ms = DateTime.now().difference(waitStart).inMilliseconds;
    log('HW', 'didActivateAudioSession RECEIVED | waitMs=$ms');
    _callkitAudioReady = null;
  }

  // ── Android no-ops ───────────────────────────────────────────────────────────

  @override
  Future<void> onCallConnected(String uuid) async {
    // iOS: CallKit manages call state natively — no explicit "connected" notification needed.
  }
}
