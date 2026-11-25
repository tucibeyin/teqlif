import 'package:livekit_client/livekit_client.dart';

/// Backend'den gelen `video_quality_profile` string'ini LiveKit seçeneklerine
/// dönüştüren adapter.
///
/// TEK KAYNAK: Kalite → LiveKit eşlemesi buradan okunur.
/// Hiçbir ekran/widget literal profil değeri ("sd"/"hd"/"fhd") içermemelidir.
/// Backend karşılığı: backend/app/services/subscription/tier.py _QUALITY_* sabitleri.
abstract class StreamQualityProfile {
  static const sd  = 'sd';
  static const hd  = 'hd';
  static const fhd = 'fhd';

  static RoomOptions roomOptions(String profile) {
    final isFhd = profile == fhd;
    final isHd  = profile == hd;
    return RoomOptions(
      adaptiveStream: true,
      dynacast: true,
      defaultVideoPublishOptions: VideoPublishOptions(
        simulcast: true,
        backupVideoCodec: const BackupVideoCodec(codec: 'vp9'),
        videoSimulcastLayers: isFhd
            ? const [VideoParametersPresets.h540_169, VideoParametersPresets.h720_169]
            : isHd
                ? const [VideoParametersPresets.h360_169, VideoParametersPresets.h540_169]
                : const [VideoParametersPresets.h240_43, VideoParametersPresets.h360_169],
        videoEncoding: VideoEncoding(
          maxBitrate: isFhd ? 4000000 : isHd ? 1700000 : 800000,
          maxFramerate: 30,
        ),
        // flutter_webrtc Android toUpperCase() Türkçe locale bug: i→İ. balanced güvenli.
        degradationPreference: DegradationPreference.balanced,
      ),
      defaultAudioPublishOptions: const AudioPublishOptions(audioBitrate: 64000),
    );
  }

  static CameraCaptureOptions cameraOptions(String profile) {
    return CameraCaptureOptions(
      params: profile == fhd
          ? VideoParametersPresets.h1080_169
          : profile == hd
              ? VideoParametersPresets.h720_169
              : VideoParametersPresets.h540_169,
    );
  }
}
