import 'dart:io';
import 'dart:math';
import 'package:ffmpeg_kit_flutter_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_min/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_min/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_min/return_code.dart';
import 'package:path_provider/path_provider.dart';

enum MediaCompressType {
  voice,
  dmVideo,
  dmPhoto,
  listingPhoto,
  listingVideo,
  storyPhoto,
  storyVideo,
}

class CompressedMedia {
  final List<int> bytes;
  final String mimeType;
  final String extension;
  final int originalBytes;
  final int compressedBytes;
  final int? durationMs;

  const CompressedMedia({
    required this.bytes,
    required this.mimeType,
    required this.extension,
    required this.originalBytes,
    required this.compressedBytes,
    this.durationMs,
  });
}

class MediaCompressCancelledException implements Exception {
  const MediaCompressCancelledException();
}

class MediaCompressException implements Exception {
  final String message;
  final int? returnCode;
  const MediaCompressException(this.message, {this.returnCode});

  @override
  String toString() => 'MediaCompressException: $message (code: $returnCode)';
}

class MediaCompressor {
  static FFmpegSession? _currentSession;
  static final _rng = Random();

  // ffmpeg argümanları (tip bazında)
  static List<String> _args(
    String input,
    String output,
    MediaCompressType type,
  ) {
    switch (type) {
      case MediaCompressType.voice:
        // m4a/any → opus 16kbps VBR, mono, 16kHz
        return [
          '-i', input,
          '-c:a', 'libopus',
          '-b:a', '16k',
          '-vbr', 'on',
          '-application', 'voip',
          '-ac', '1',
          '-ar', '16000',
          output,
        ];

      case MediaCompressType.dmVideo:
        // any → mp4, H.264 CRF28, 720p, max 90s
        return [
          '-i', input,
          '-c:v', 'libx264',
          '-crf', '28',
          '-preset', 'fast',
          '-vf', 'scale=-2:720',
          '-c:a', 'aac',
          '-b:a', '64k',
          '-t', '90',
          output,
        ];

      case MediaCompressType.listingVideo:
        // any → mp4, H.264 CRF23, 1080p, max 60s, EXIF temiz
        return [
          '-i', input,
          '-c:v', 'libx264',
          '-crf', '23',
          '-preset', 'fast',
          '-vf', 'scale=-2:1080',
          '-c:a', 'aac',
          '-b:a', '128k',
          '-t', '60',
          '-map_metadata', '-1',
          output,
        ];

      case MediaCompressType.storyVideo:
        // any → mp4, H.264 CRF28, 720p, max 15s
        return [
          '-i', input,
          '-c:v', 'libx264',
          '-crf', '28',
          '-preset', 'fast',
          '-vf', 'scale=-2:720',
          '-c:a', 'aac',
          '-b:a', '64k',
          '-t', '15',
          output,
        ];

      case MediaCompressType.dmPhoto:
      case MediaCompressType.listingPhoto:
        // any → jpeg, max 1200px, EXIF temiz
        return [
          '-i', input,
          '-vf', r"scale='min(1200,iw)':-2",
          '-q:v', '4',
          '-map_metadata', '-1',
          output,
        ];

      case MediaCompressType.storyPhoto:
        // any → jpeg, max 1920px, EXIF temiz
        return [
          '-i', input,
          '-vf', r"scale='min(1920,iw)':-2",
          '-q:v', '3',
          '-map_metadata', '-1',
          output,
        ];
    }
  }

  static String _outputExtension(MediaCompressType type) {
    switch (type) {
      case MediaCompressType.voice:
        return 'ogg';
      case MediaCompressType.dmVideo:
      case MediaCompressType.listingVideo:
      case MediaCompressType.storyVideo:
        return 'mp4';
      case MediaCompressType.dmPhoto:
      case MediaCompressType.listingPhoto:
      case MediaCompressType.storyPhoto:
        return 'jpg';
    }
  }

  static String _mimeType(MediaCompressType type) {
    switch (type) {
      case MediaCompressType.voice:
        return 'audio/ogg';
      case MediaCompressType.dmVideo:
      case MediaCompressType.listingVideo:
      case MediaCompressType.storyVideo:
        return 'video/mp4';
      case MediaCompressType.dmPhoto:
      case MediaCompressType.listingPhoto:
      case MediaCompressType.storyPhoto:
        return 'image/jpeg';
    }
  }

  /// Medyayı sıkıştır. [onProgress] 0.0–1.0 arasında ilerlemeyi bildirir.
  /// Video tiplerinde [targetDurationMs] progress hesabı için kullanılır.
  /// İptal için [cancel()] çağır — [MediaCompressCancelledException] fırlatır.
  static Future<CompressedMedia> compress(
    String inputPath,
    MediaCompressType type, {
    void Function(double progress)? onProgress,
    int? targetDurationMs,
  }) async {
    final tmpDir = await getTemporaryDirectory();
    final ext = _outputExtension(type);
    final tag = '${DateTime.now().millisecondsSinceEpoch}_${_rng.nextInt(999999)}';
    final outputPath = '${tmpDir.path}/teq_$tag.$ext';
    final inputFile = File(inputPath);
    final originalBytes = await inputFile.length();

    // progress callback kurulumu
    if (onProgress != null && targetDurationMs != null && targetDurationMs > 0) {
      FFmpegKitConfig.enableStatisticsCallback((stats) {
        final progress = (stats.getTime() / targetDurationMs).clamp(0.0, 1.0);
        onProgress(progress);
      });
    }

    final args = ['-y', ..._args(inputPath, outputPath, type)];
    _currentSession = await FFmpegKit.executeWithArgumentsAsync(args);
    final session = _currentSession!;
    final returnCode = await session.getReturnCode();

    // istatistik callback'i temizle
    if (onProgress != null) {
      FFmpegKitConfig.enableStatisticsCallback(null);
    }

    if (ReturnCode.isCancel(returnCode)) {
      final outFile = File(outputPath);
      if (await outFile.exists()) await outFile.delete();
      throw const MediaCompressCancelledException();
    }

    if (!ReturnCode.isSuccess(returnCode)) {
      final outFile = File(outputPath);
      if (await outFile.exists()) await outFile.delete();
      throw MediaCompressException(
        'ffmpeg failed',
        returnCode: returnCode?.getValue(),
      );
    }

    final outFile = File(outputPath);
    if (!await outFile.exists()) {
      throw const MediaCompressException('output file not found');
    }

    try {
      final bytes = await outFile.readAsBytes();
      return CompressedMedia(
        bytes: bytes,
        mimeType: _mimeType(type),
        extension: ext,
        originalBytes: originalBytes,
        compressedBytes: bytes.length,
      );
    } finally {
      // output temp dosyasını temizle — caller bytes alır, path almaz
      if (await outFile.exists()) await outFile.delete();
    }
  }

  /// Devam eden sıkıştırmayı iptal et.
  static Future<void> cancel() async {
    final session = _currentSession;
    if (session != null) {
      await FFmpegKit.cancel(await session.getSessionId());
    }
  }
}
