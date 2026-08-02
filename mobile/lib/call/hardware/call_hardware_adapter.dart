import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import '../state/end_reason.dart';

// ── Abstract interface ─────────────────────────────────────────────────────────
//
// Platform-specific audio hardware responsibility:
//   • AVAudioSession (iOS) / AudioFocus (Android)
//   • Ringback, ringtone, vibration, one-shot sounds
//   • Speakerphone routing
//   • Mic/camera permission requests
//
// CallService calls these methods; all Platform.isIOS / Platform.isAndroid
// branches live in the concrete implementations.

abstract class CallHardwareAdapter {
  // ── Hardware state notifier (D-7) ─────────────────────────────────────────
  // Owned by adapter; CallService exposes via getter. UI listens directly.
  final ValueNotifier<bool> isSpeaker = ValueNotifier<bool>(false);

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  /// Preload ringback player, configure audio context, prewarm AudioSession.
  Future<void> init();

  /// Stop all audio players; cancel subscriptions.
  void dispose();

  /// Clear per-call state (iOS audioSessionActivated flag, Completer).
  /// Call from reset() before starting a new call.
  void resetAfterCall();

  // ── Permissions ─────────────────────────────────────────────────────────────

  /// Requests OS microphone permission dialog if needed.
  Future<PermissionStatus> requestMicPermission();

  // ── Audio session ───────────────────────────────────────────────────────────

  /// Configure audio session for an outgoing call (dialing state).
  /// iOS: AVAudioSession playAndRecord/voiceChat + allowBluetooth.
  /// Android: AudioFocus gainTransientMayDuck + voiceCommunication.
  Future<void> setupAudioSession();

  /// Deactivate audio session (idle state cleanup).
  /// iOS: session.setActive(false). Android: AudioFocus abandon.
  Future<void> teardownAudioSession();

  /// Called after room.connect() to restore audio session.
  /// iOS: room.connect() overrides AVAudioSession to soloAmbient → ringback stops.
  ///      Re-configures playAndRecord/voiceChat and resumes ringback if interrupted.
  /// Android: no-op (room.connect() has no audio-session side effect).
  Future<void> resumeAfterRoomConnect();

  /// Configure playAndRecord/voiceChat session and set speakerphone.
  /// Called during callee audio activation and on TrackSubscribed.
  Future<void> configureVoiceChat({required bool speakerEnabled});

  // ── Ringback (caller) ────────────────────────────────────────────────────────

  void startRingback();
  void stopRingback();

  // ── Ringer / vibration (callee) ─────────────────────────────────────────────

  /// One-shot notification sound when IncomingCallBar appears.
  void playNotification();

  /// Looping ringtone + vibration for incoming call.
  void startRinger();

  /// Stop ringtone and vibration.
  void stopRinger();

  // ── End-of-call sounds ───────────────────────────────────────────────────────

  /// busy.wav (rejected/busy) or ended.wav (was connected) or silence.
  void playEndedSound({required bool wasConnected, EndReason? endReason});

  /// weak.wav for reconnecting state.
  void playWeakSound();

  /// Stop all audio players immediately.
  void stopAllSounds();

  // ── Speakerphone ─────────────────────────────────────────────────────────────

  /// Always call AFTER configureVoiceChat() / setupAudioSession() to avoid
  /// AVAudioSession override resetting the routing.
  Future<void> setSpeaker(bool enabled);

  // ── iOS CallKit audio lifecycle ──────────────────────────────────────────────

  /// iOS: called by CallKit channel when didActivateAudioSession fires.
  /// Android: no-op.
  void onAudioSessionActivated();

  /// iOS: await CallKit's didActivateAudioSession signal (max 4s timeout).
  /// Android: returns immediately.
  Future<void> waitForCallkitAudio();

  // ── Android CallKit UI ────────────────────────────────────────────────────────

  /// Android: notifies flutter_callkit_incoming to update notification UI to "connected".
  /// iOS: no-op.
  Future<void> onCallConnected(String uuid);

  // ── Proximity sensor ─────────────────────────────────────────────────────────

  /// Start listening to proximity sensor events. Calls [onNear] when the sensor
  /// detects the device is near the user's ear (value == 0).
  /// Android: also enables proximity screen-off.
  void startProximitySensor({required void Function() onNear});

  /// Stop listening to proximity sensor events.
  /// Android: also disables proximity screen-off.
  void stopProximitySensor();

  // ── Logging ──────────────────────────────────────────────────────────────────

  void log(String phase, String msg) =>
      debugPrint('[CALL_HW][${DateTime.now().toIso8601String()}][$phase] $msg');
}
