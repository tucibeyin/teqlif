import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
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

  // ── Hybrid: video hikayeleri + canlı yayın harmanlama ─────────────────────

  static Future<List<UserStoryGroup>> getFollowingStories() async {
    final headers = await _headers();
    final resp = await http.get(
      Uri.parse('$kBaseUrl/stories/following'),
      headers: headers,
    );
    debugPrint('[StoryService] getFollowingStories → HTTP ${resp.statusCode}');
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
        debugPrint(
          '[StoryService] UserStoryGroup.fromJson hatası: $err | veri: $e',
        );
      }
    }
    debugPrint('[StoryService] getFollowingStories → ${result.length} grup');
    return result;
  }

  // ── Kendi hikayelerim ─────────────────────────────────────────────────────

  static Future<List<StoryItem>> getMyStories() async {
    final headers = await _headers();
    final resp = await http.get(
      Uri.parse('$kBaseUrl/stories/mine'),
      headers: headers,
    );
    debugPrint('[StoryService] getMyStories → HTTP ${resp.statusCode}');
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
    final data = _tryDecode(resp.body);
    final itemsList = data['items'] as List? ?? [];
    return itemsList
        .map((e) => StoryItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Hikaye görüntüleme kaydı ──────────────────────────────────────────────

  static Future<void> recordStoryView(int storyId) async {
    final headers = await _headers();
    final resp = await http.post(
      Uri.parse('$kBaseUrl/stories/$storyId/view'),
      headers: headers,
    );
    debugPrint('[StoryService] recordStoryView($storyId) → HTTP ${resp.statusCode}');
    // 204 başarı; hata değilse sessizce geç
    if (resp.statusCode >= 400) {
      debugPrint('[StoryService] recordStoryView → hata: ${resp.body}');
    }
  }

  // ── Hikaye görüntüleyenler ────────────────────────────────────────────────

  static Future<List<StoryViewer>> getStoryViewers(int storyId) async {
    final headers = await _headers();
    final resp = await http.get(
      Uri.parse('$kBaseUrl/stories/$storyId/viewers'),
      headers: headers,
    );
    debugPrint('[StoryService] getStoryViewers($storyId) → HTTP ${resp.statusCode}');
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
    final data = _tryDecode(resp.body);
    final viewers = data['viewers'] as List? ?? [];
    return viewers
        .map((e) => StoryViewer.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Hikaye yükleme (video dosyası → backend) ───────────────────────────────

  static Future<void> uploadStory(File videoFile) async {
    final token = await StorageService.getToken();
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$kBaseUrl/stories/upload'),
    );
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    // contentType açıkça video/mp4 olarak ayarlanır — bazı iOS/Android cihazlar
    // varsayılan olarak application/octet-stream gönderir ve backend'de 400 alınır.
    req.files.add(await http.MultipartFile.fromPath(
      'file',
      videoFile.path,
      contentType: MediaType('video', 'mp4'),
    ));

    debugPrint('[StoryService] uploadStory → gönderiliyor: ${videoFile.path}');
    final streamed = await req.send();
    final bodyStr = await streamed.stream.bytesToString();

    if (streamed.statusCode >= 400) {
      final decoded = _tryDecode(bodyStr);
      // FastAPI: {"detail": "..."} | özel hata: {"error": {"message": ..., "code": ...}}
      final errMap = decoded['error'];
      final message = errMap is Map
          ? (errMap['message'] as String? ?? 'Hikaye yüklenemedi')
          : (decoded['detail'] as String? ?? 'Hikaye yüklenemedi');
      final code = errMap is Map
          ? (errMap['code'] as String? ?? 'UPLOAD_ERROR')
          : 'HTTP_${streamed.statusCode}';
      debugPrint('[StoryService] uploadStory → hata ${streamed.statusCode}: $message');
      throw AppException(message, code: code, statusCode: streamed.statusCode);
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
