import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import 'stream_connection_manager.dart';

/// Arka plan ses bildirimi ve Foreground Service yönetimini üstlenen sınıf
class StreamBackgroundAudioHandler extends BaseAudioHandler {
  
  StreamBackgroundAudioHandler() {
    _updatePlaybackState(playing: false);
  }

  void _updatePlaybackState({required bool playing}) {
    playbackState.add(playbackState.value.copyWith(
      controls: [
        playing ? MediaControl.pause : MediaControl.play,
        MediaControl.stop,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1],
      processingState: AudioProcessingState.ready,
      playing: playing,
    ));
  }

  /// Canlı yayın arka plan servisini başlatır
  Future<void> startService(int streamId, String title, String author) async {
    mediaItem.add(MediaItem(
      id: streamId.toString(),
      album: 'Teqlif Canlı Yayın',
      title: title,
      artist: author,
    ));
    _updatePlaybackState(playing: true);
    debugPrint('[EVENT: BG_AUDIO] Background Service Started for stream: $streamId');
  }

  /// Ön plana (foreground) dönüldüğünde veya canlı yayından çıkıldığında servisi durdurur
  Future<void> stopService() async {
    _updatePlaybackState(playing: false);
    await super.stop();
    debugPrint('[EVENT: BG_AUDIO] Background Service Stopped');
  }

  @override
  Future<void> play() async {
    _updatePlaybackState(playing: true);
    // İhtiyaca göre StreamConnectionManager.instance.getSession(id).room.localParticipant.unpublishTrack() gibi işlemler yapılabilir
  }

  @override
  Future<void> pause() async {
    _updatePlaybackState(playing: false);
    // Sesi duraklat
  }

  @override
  Future<void> stop() async {
    // Kilit ekranından veya bildirimden X'e basıldığında tamamen kapat
    await stopService();
    // Varsa tüm WebRTC bağlantılarını kopar
    StreamConnectionManager.instance.clearViewport();
  }
}

late StreamBackgroundAudioHandler bgAudioHandler;

Future<void> initBackgroundAudio() async {
  bgAudioHandler = await AudioService.init(
    builder: () => StreamBackgroundAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.teqlif.mobile.channel.audio',
      androidNotificationChannelName: 'Canlı Yayın Arka Plan Sesi',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );
}
