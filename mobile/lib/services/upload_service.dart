import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import 'storage_service.dart';

/// Upload sonucu: orijinal URL ve thumbnail URL.
typedef UploadResult = ({String url, String? thumbUrl});

/// Video upload sonucu.
typedef VideoUploadResult = ({String videoUrl, String? thumbUrl});

class UploadService {
  /// Bir dosyayı backend'e yükler.
  /// Başarı durumunda [UploadResult] döner; hata durumunda [Exception] fırlatır.
  static Future<VideoUploadResult> uploadVideo(File file) async {
    final token = await StorageService.getToken();
    if (token == null) throw Exception('Oturum açık değil');

    final fileSize = await file.length();
    debugPrint('[Upload] Video yükleniyor: ${file.path} (${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB)');

    final req = http.MultipartRequest('POST', Uri.parse('$kBaseUrl/upload/listing-video'));
    req.headers['Authorization'] = 'Bearer $token';
    req.files.add(await http.MultipartFile.fromPath('file', file.path));

    final sw = Stopwatch()..start();
    final streamed = await req.send();
    final body = await streamed.stream.bytesToString();
    sw.stop();

    debugPrint('[Upload] Yanıt: HTTP ${streamed.statusCode} (${sw.elapsedMilliseconds}ms) | body: ${body.length > 300 ? body.substring(0, 300) : body}');

    if (streamed.statusCode != 200) {
      String detail = body;
      try {
        detail = (jsonDecode(body) as Map)['detail']?.toString() ?? body;
      } catch (_) {}
      debugPrint('[Upload] HATA: status=${streamed.statusCode} detail=$detail');
      throw Exception('HTTP ${streamed.statusCode}: $detail');
    }

    final json = jsonDecode(body) as Map<String, dynamic>;
    return (
      videoUrl: json['video_url'] as String,
      thumbUrl: json['thumb_url'] as String?,
    );
  }

  static Future<UploadResult> uploadFile(File file) async {
    final token = await StorageService.getToken();
    if (token == null) throw Exception('Oturum açık değil');

    final req = http.MultipartRequest('POST', Uri.parse('$kBaseUrl/upload'));
    req.headers['Authorization'] = 'Bearer $token';
    req.files.add(await http.MultipartFile.fromPath('file', file.path));

    final streamed = await req.send();
    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode != 200) {
      String detail = body;
      try {
        detail = (jsonDecode(body) as Map)['detail']?.toString() ?? body;
      } catch (_) {}
      throw Exception('Yükleme başarısız: $detail');
    }

    final json = jsonDecode(body) as Map<String, dynamic>;
    return (
      url: json['url'] as String,
      thumbUrl: json['thumb_url'] as String?,
    );
  }

  static Future<UploadResult> uploadBytes(Uint8List bytes, String filename) async {
    final token = await StorageService.getToken();
    if (token == null) throw Exception('Oturum açık değil');

    final req = http.MultipartRequest('POST', Uri.parse('$kBaseUrl/upload'));
    req.headers['Authorization'] = 'Bearer $token';
    req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));

    final streamed = await req.send();
    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode != 200) {
      String detail = body;
      try {
        detail = (jsonDecode(body) as Map)['detail']?.toString() ?? body;
      } catch (_) {}
      throw Exception('Yükleme başarısız: $detail');
    }

    final json = jsonDecode(body) as Map<String, dynamic>;
    return (
      url: json['url'] as String,
      thumbUrl: json['thumb_url'] as String?,
    );
  }
}
