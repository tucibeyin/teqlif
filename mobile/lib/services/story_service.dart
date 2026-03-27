import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import '../core/app_exception.dart';
import '../models/story.dart';
import 'storage_service.dart';

class StoryService {
  static Future<Map<String, String>> _headers() async {
    final token = await StorageService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // ── Takip edilen kullanıcıların gruplanmış hikayeleri ──────────────────────

  static Future<List<UserStoryGroup>> getGroupedStories() async {
    final headers = await _headers();
    final resp = await http.get(
      Uri.parse('$kBaseUrl/stories/following'),
      headers: headers,
    );
    debugPrint(
      '[StoryService] getGroupedStories → HTTP ${resp.statusCode}',
    );
    if (resp.statusCode >= 400) {
      final body = _tryDecode(resp.body);
      final errMap = body['error'];
      throw AppException(
        errMap is Map
            ? (errMap['message'] ?? 'Bir hata oluştu')
            : (body['detail'] ?? 'Bir hata oluştu'),
        code: errMap is Map
            ? (errMap['code'] ?? 'ERR_${resp.statusCode}')
            : 'HTTP_${resp.statusCode}',
        statusCode: resp.statusCode,
      );
    }
    final list = _tryDecodeList(resp.body);
    final result = <UserStoryGroup>[];
    for (final e in list) {
      try {
        result.add(UserStoryGroup.fromJson(e as Map<String, dynamic>));
      } catch (err) {
        debugPrint('[StoryService] UserStoryGroup.fromJson hatası: $err | veri: $e');
      }
    }
    debugPrint('[StoryService] getGroupedStories → ${result.length} grup');
    return result;
  }

  // ── Hikaye yükleme (video dosyası → backend) ───────────────────────────────

  static Future<void> uploadStory(File videoFile) async {
    final token = await StorageService.getToken();
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$kBaseUrl/stories/upload'),
    );
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    req.files.add(await http.MultipartFile.fromPath('file', videoFile.path));

    debugPrint('[StoryService] uploadStory → gönderiliyor: ${videoFile.path}');
    final streamed = await req.send();
    final bodyStr = await streamed.stream.bytesToString();

    if (streamed.statusCode >= 400) {
      final decoded = _tryDecode(bodyStr);
      final errMap = decoded['error'];
      throw AppException(
        errMap is Map
            ? (errMap['message'] ?? 'Hikaye yüklenemedi')
            : (decoded['detail'] ?? 'Hikaye yüklenemedi'),
        code: errMap is Map ? (errMap['code'] ?? 'UPLOAD_ERROR') : 'HTTP_${streamed.statusCode}',
        statusCode: streamed.statusCode,
      );
    }
    debugPrint('[StoryService] uploadStory → başarılı (${streamed.statusCode})');
  }

  // ── Yardımcılar ────────────────────────────────────────────────────────────

  static Map<String, dynamic> _tryDecode(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  static List _tryDecodeList(String body) {
    try {
      return jsonDecode(body) as List;
    } catch (_) {
      return [];
    }
  }
}
