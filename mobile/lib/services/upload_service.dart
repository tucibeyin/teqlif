import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import '../core/app_exception.dart';
import '../core/media_constants.dart';
import 'storage_service.dart';

/// Upload sonucu: orijinal URL ve thumbnail URL.
typedef UploadResult = ({String url, String? thumbUrl});

/// Video upload sonucu.
typedef VideoUploadResult = ({String videoUrl, String? thumbUrl});

class UploadService {
  /// Dosya stream'ini progress callback ile sarar.
  static Stream<List<int>> _progressStream(
    Stream<List<int>> source,
    int total,
    void Function(double) onProgress,
  ) async* {
    var sent = 0;
    await for (final chunk in source) {
      sent += chunk.length;
      onProgress(total > 0 ? (sent / total).clamp(0.0, 1.0) : 0.0);
      yield chunk;
    }
  }

  /// Backend hata yanıtını [AppException]'a çevirir.
  static AppException _parseError(int statusCode, String body) {
    try {
      final map = jsonDecode(body) as Map<String, dynamic>;
      final err = map['error'] as Map<String, dynamic>?;
      final code = err?['code']?.toString() ?? 'ERR_UNKNOWN';
      final message = err?['message']?.toString() ?? body;
      return AppException(message, code: code, statusCode: statusCode);
    } catch (_) {
      return AppException(body, code: 'ERR_UNKNOWN', statusCode: statusCode);
    }
  }

  /// İlan videosunu backend'e yükler.
  /// [onProgress]: 0.0–1.0 arası ilerleme callback'i.
  static Future<VideoUploadResult> uploadVideo(
    File file, {
    void Function(double)? onProgress,
  }) async {
    final token = await StorageService.getToken();
    if (token == null) throw const AppException('Oturum açık değil', code: 'UNAUTHORIZED');

    final fileSize = await file.length();
    debugPrint('[Upload] Video: ${file.path} (${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB)');

    if (fileSize > MediaConstants.listingVideoMaxBytes) {
      throw const AppException('', code: 'VIDEO_TOO_LARGE', statusCode: 400);
    }

    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$kBaseUrl/upload/listing-video'),
    );
    req.headers['Authorization'] = 'Bearer $token';

    if (onProgress != null) {
      req.files.add(http.MultipartFile(
        'file',
        _progressStream(file.openRead(), fileSize, onProgress),
        fileSize,
        filename: file.path.split('/').last,
      ));
    } else {
      req.files.add(await http.MultipartFile.fromPath('file', file.path));
    }

    final sw = Stopwatch()..start();
    final streamed = await req.send();
    final body = await streamed.stream.bytesToString();
    sw.stop();

    debugPrint('[Upload] Video yanıt: HTTP ${streamed.statusCode} (${sw.elapsedMilliseconds}ms)');

    if (streamed.statusCode != 200) {
      throw _parseError(streamed.statusCode, body);
    }

    final json = jsonDecode(body) as Map<String, dynamic>;
    return (
      videoUrl: json['video_url'] as String,
      thumbUrl: json['thumb_url'] as String?,
    );
  }

  /// İlan videosunu bytes olarak backend'e yükler.
  static Future<VideoUploadResult> uploadVideoBytes(
    List<int> bytes, {
    void Function(double)? onProgress,
  }) async {
    final token = await StorageService.getToken();
    if (token == null) throw const AppException('Oturum açık değil', code: 'UNAUTHORIZED');

    debugPrint('[Upload] VideoBytes: ${(bytes.length / 1024 / 1024).toStringAsFixed(2)} MB');

    if (bytes.length > MediaConstants.listingVideoMaxBytes) {
      throw const AppException('', code: 'VIDEO_TOO_LARGE', statusCode: 400);
    }

    final req = http.MultipartRequest('POST', Uri.parse('$kBaseUrl/upload/listing-video'));
    req.headers['Authorization'] = 'Bearer $token';

    if (onProgress != null) {
      final rawStream = Stream.fromIterable(<List<int>>[bytes]);
      req.files.add(http.MultipartFile(
        'file',
        _progressStream(rawStream, bytes.length, onProgress),
        bytes.length,
        filename: 'video.mp4',
      ));
    } else {
      req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: 'video.mp4'));
    }

    final sw = Stopwatch()..start();
    final streamed = await req.send();
    final body = await streamed.stream.bytesToString();
    sw.stop();
    debugPrint('[Upload] VideoBytes yanıt: HTTP ${streamed.statusCode} (${sw.elapsedMilliseconds}ms)');

    if (streamed.statusCode != 200) {
      throw _parseError(streamed.statusCode, body);
    }

    final json = jsonDecode(body) as Map<String, dynamic>;
    return (
      videoUrl: json['video_url'] as String,
      thumbUrl: json['thumb_url'] as String?,
    );
  }

  /// İlan fotoğrafını backend'e yükler.
  /// [onProgress]: 0.0–1.0 arası ilerleme callback'i.
  static Future<UploadResult> uploadFile(
    File file, {
    void Function(double)? onProgress,
  }) async {
    final token = await StorageService.getToken();
    if (token == null) throw const AppException('Oturum açık değil', code: 'UNAUTHORIZED');

    final fileSize = await file.length();

    if (fileSize > MediaConstants.imageMaxBytes) {
      throw const AppException('', code: 'FILE_TOO_LARGE', statusCode: 400);
    }

    final req = http.MultipartRequest('POST', Uri.parse('$kBaseUrl/upload'));
    req.headers['Authorization'] = 'Bearer $token';

    if (onProgress != null) {
      req.files.add(http.MultipartFile(
        'file',
        _progressStream(file.openRead(), fileSize, onProgress),
        fileSize,
        filename: file.path.split('/').last,
      ));
    } else {
      req.files.add(await http.MultipartFile.fromPath('file', file.path));
    }

    final streamed = await req.send();
    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode != 200) {
      throw _parseError(streamed.statusCode, body);
    }

    final json = jsonDecode(body) as Map<String, dynamic>;
    return (
      url: json['url'] as String,
      thumbUrl: json['thumb_url'] as String?,
    );
  }

  /// Bytes olarak upload (profil fotoğrafı gibi kameradan alınan ham veri).
  static Future<UploadResult> uploadBytes(Uint8List bytes, String filename) async {
    final token = await StorageService.getToken();
    if (token == null) throw const AppException('Oturum açık değil', code: 'UNAUTHORIZED');

    if (bytes.length > MediaConstants.imageMaxBytes) {
      throw const AppException('', code: 'FILE_TOO_LARGE', statusCode: 400);
    }

    final req = http.MultipartRequest('POST', Uri.parse('$kBaseUrl/upload'));
    req.headers['Authorization'] = 'Bearer $token';
    req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));

    final streamed = await req.send();
    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode != 200) {
      throw _parseError(streamed.statusCode, body);
    }

    final json = jsonDecode(body) as Map<String, dynamic>;
    return (
      url: json['url'] as String,
      thumbUrl: json['thumb_url'] as String?,
    );
  }
}
