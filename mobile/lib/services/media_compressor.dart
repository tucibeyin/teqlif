import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:video_compress/video_compress.dart';

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
  const MediaCompressException(this.message);

  @override
  String toString() => 'MediaCompressException: $message';
}

class MediaCompressor {
  static bool _cancelled = false;
  static Subscription? _progressSub;

  static Future<CompressedMedia> compress(
    String inputPath,
    MediaCompressType type, {
    void Function(double progress)? onProgress,
    int? targetDurationMs,
  }) async {
    _cancelled = false;
    final file = File(inputPath);
    final originalBytes = await file.length();

    switch (type) {
      case MediaCompressType.voice:
        // Recorded in AAC format — read bytes directly
        final bytes = await file.readAsBytes();
        return CompressedMedia(
          bytes: bytes,
          mimeType: 'audio/mp4',
          extension: 'm4a',
          originalBytes: originalBytes,
          compressedBytes: bytes.length,
        );

      case MediaCompressType.dmPhoto:
      case MediaCompressType.listingPhoto:
        return _compressPhoto(inputPath, originalBytes, maxDim: 1200, quality: 80);

      case MediaCompressType.storyPhoto:
        return _compressPhoto(inputPath, originalBytes, maxDim: 1920, quality: 85);

      case MediaCompressType.dmVideo:
      case MediaCompressType.storyVideo:
        return _compressVideo(
          inputPath, originalBytes,
          quality: VideoQuality.MediumQuality,
          onProgress: onProgress,
        );

      case MediaCompressType.listingVideo:
        return _compressVideo(
          inputPath, originalBytes,
          quality: VideoQuality.HighestQuality,
          onProgress: onProgress,
        );
    }
  }

  static Future<CompressedMedia> _compressPhoto(
    String inputPath,
    int originalBytes, {
    required int maxDim,
    required int quality,
  }) async {
    final result = await FlutterImageCompress.compressWithFile(
      inputPath,
      minWidth: maxDim,
      minHeight: maxDim,
      quality: quality,
      keepExif: false,
    );
    if (result == null) throw const MediaCompressException('Image compression failed');
    return CompressedMedia(
      bytes: result,
      mimeType: 'image/jpeg',
      extension: 'jpg',
      originalBytes: originalBytes,
      compressedBytes: result.length,
    );
  }

  static Future<CompressedMedia> _compressVideo(
    String inputPath,
    int originalBytes, {
    required VideoQuality quality,
    void Function(double)? onProgress,
  }) async {
    _progressSub?.unsubscribe();
    if (onProgress != null) {
      _progressSub = VideoCompress.compressProgress$.subscribe((p) {
        onProgress((p / 100.0).clamp(0.0, 1.0));
      });
    }

    try {
      final result = await VideoCompress.compressVideo(
        inputPath,
        quality: quality,
        deleteOrigin: false,
        includeAudio: true,
      );

      if (_cancelled) throw const MediaCompressCancelledException();

      final outFile = result?.file;
      if (outFile == null) throw const MediaCompressException('Video compression failed');

      final bytes = await outFile.readAsBytes();
      return CompressedMedia(
        bytes: bytes,
        mimeType: 'video/mp4',
        extension: 'mp4',
        originalBytes: originalBytes,
        compressedBytes: bytes.length,
        durationMs: result?.duration?.toInt(),
      );
    } finally {
      _progressSub?.unsubscribe();
      _progressSub = null;
    }
  }

  static Future<void> cancel() async {
    _cancelled = true;
    VideoCompress.cancelCompression();
  }
}
