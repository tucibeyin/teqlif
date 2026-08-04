import 'dart:async';
import 'package:proximity_sensor/proximity_sensor.dart';
import 'package:audio_session/audio_session.dart';
import 'package:audioplayers/audioplayers.dart' hide AVAudioSessionCategory;
import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:livekit_client/livekit_client.dart' show Hardware;
import 'package:permission_handler/permission_handler.dart';
import 'package:vibration/vibration.dart';
import '../state/end_reason.dart';
import 'call_hardware_adapter.dart';

class AndroidCallHardwareAdapter extends CallHardwareAdapter {
  // ── Audio players ───────────────────────────────────────────────────────────

  final _ringbackPlayer = AudioPlayer();
  bool _ringbackPreloaded = false;

  // One-shot sounds: busy.wav, ended.wav, weak.wav.
  // Android: voiceCommunication context prevents speaker drift after AudioFocus release.
  final _audioPlayer = AudioPlayer();

  StreamSubscription<int>? _proximitySub;

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  @override
  Future<void> init() async {
    await _preloadRingback();
    // Android has no audio session to pre-warm.
  }

  Future<void> _preloadRingback() async {
    try {
      // Android: voiceCommunication context keeps audio on earpiece when AudioFocus
      // is released — prevents sounds from jumping to speaker unexpectedly.
      await _audioPlayer.setAudioContext(ap.AudioContext(
        android: const ap.AudioContextAndroid(
          usageType: ap.AndroidUsageType.voiceCommunication,
          contentType: ap.AndroidContentType.sonification,
          audioFocus: ap.AndroidAudioFocus.gainTransientMayDuck,
        ),
      ));
      await _ringbackPlayer.setReleaseMode(ReleaseMode.loop);
      await _ringbackPlayer.setAudioContext(ap.AudioContext(
        android: const ap.AudioContextAndroid(
          usageType: ap.AndroidUsageType.voiceCommunication,
          contentType: ap.AndroidContentType.sonification,
          audioFocus: ap.AndroidAudioFocus.gainTransientMayDuck,
        ),
      ));
      await _ringbackPlayer.setSource(ap.AssetSource('sounds/ringing.wav'));
      _ringbackPreloaded = true;
      log('SOUND', 'ringing.wav PRE-LOADED | ready for instant resume()');

      // Android MediaPlayer cold-start (~780ms): force-decode by playing 50ms then pausing.
      // After this, resume() starts in ~15ms instead of ~780ms.
      try {
        await _ringbackPlayer.resume();
        await Future.delayed(const Duration(milliseconds: 50));
        await _ringbackPlayer.pause();
        await _ringbackPlayer.seek(Duration.zero);
        log('SOUND', 'ringing.wav FORCE-BUFFERED (Android) | cold-start latency eliminated');
      } catch (e) {
        log('SOUND', 'Android buffer-force FAILED | $e');
      }
    } catch (e) {
      log('SOUND', 'ringing.wav pre-load FAILED | $e → fallback to play(AssetSource)');
    }
  }

  @override
  void dispose() {
    _proximitySub?.cancel();
    _ringbackPlayer.dispose();
    _audioPlayer.dispose();
    FlutterRingtonePlayer().stop();
    Vibration.cancel();
  }

  @override
  void resetAfterCall() {
    // Android: no per-call flag state to reset.
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
      log('HW', 'audioSession CONFIGURE | context=dialing androidUsage=voiceCommunication androidFocus=gainTransientMayDuck');
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
    // Android: no AVAudioSession equivalent — AudioFocus is released automatically
    // when the AudioPlayer/MediaPlayer is released. No explicit deactivation needed.
  }

  @override
  Future<void> resumeAfterRoomConnect() async {
    // Android: room.connect() has no audio-session side effect (no AVAudioSession).
    // Ringback continues uninterrupted — nothing to restore.
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
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.sonification,
          flags: AndroidAudioFlags.none,
          usage: AndroidAudioUsage.voiceCommunication,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransientMayDuck,
        androidWillPauseWhenDucked: false,
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
    // Android: no delay needed — AudioFocus settles synchronously.
    Future(() async {
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
    log('SOUND', 'startRingtoneAndVibration CALLED (Android) -> NO-OP (Handled natively by flutter_callkit_incoming)');
  }

  @override
  void stopRinger() {
    log('HW', 'ringtonePlayer STOP');
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
      isSpeaker.value = enabled;
    } catch (e) {
      log('HW', 'speakerphone SET ERROR | enabled=$enabled $e');
    }
  }

  // ── iOS no-ops ───────────────────────────────────────────────────────────────

  @override
  void onAudioSessionActivated() {
    // Android: no CallKit audio session lifecycle — no-op.
  }

  @override
  Future<void> waitForCallkitAudio() async {
    // Android: no CallKit audio session to wait for — returns immediately.
  }

  // ── Proximity sensor ─────────────────────────────────────────────────────────

  @override
  void startProximitySensor({required void Function() onNear}) {
    _proximitySub?.cancel();
    log('HW', 'proximitySensor START');
    _proximitySub = ProximitySensor.events.listen((int value) {
      if (value == 0) onNear();
    }, onError: (e) {
      log('HW', 'proximitySensor ERROR | $e');
    });
    ProximitySensor.setProximityScreenOff(true).catchError((e) {
      log('HW', 'proximitySensor setScreenOff ERROR | $e');
    });
  }

  @override
  void stopProximitySensor() {
    if (_proximitySub == null) return;
    _proximitySub!.cancel().catchError((_) {});
    _proximitySub = null;
    ProximitySensor.setProximityScreenOff(false).catchError((_) {});
    log('HW', 'proximitySensor STOP');
  }

  // ── Android CallKit UI ────────────────────────────────────────────────────────

  @override
  Future<void> onCallConnected(String uuid) async {
    log('HW', 'setCallConnected | uuid=$uuid');
    FlutterCallkitIncoming.setCallConnected(uuid).catchError((e) {
      log('HW', 'setCallConnected ERROR | $e');
    });
    // Short delay: CallKit notification UI update must settle before audio config.
    await Future.delayed(const Duration(milliseconds: 200));
  }
}
