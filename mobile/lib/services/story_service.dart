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

  // ── Hikaye beğeni toggle ──────────────────────────────────────────────────

  /// [storyId] hikayesi için beğeni toggle eder (beğen / beğeniyi kaldır).
  /// Güncel [likes_count] ve [is_liked] döner.
  static Future<Map<String, dynamic>> toggleLike(int storyId) async {
    final headers = await _headers();
    final resp = await http.post(
      Uri.parse('$kBaseUrl/stories/$storyId/like'),
      headers: headers,
    );
    debugPrint('[StoryService] toggleLike($storyId) → HTTP ${resp.statusCode}');
    if (resp.statusCode == 200) {
      return _tryDecode(resp.body);
    }
    final body = _tryDecode(resp.body);
    final errMap = body['error'];
    throw AppException(
      errMap is Map
          ? (errMap['message'] ?? 'Beğeni gönderilemedi')
          : (body['detail'] ?? 'Beğeni gönderilemedi'),
      code: errMap is Map
          ? (errMap['code'] ?? 'ERR_${resp.statusCode}')
          : 'HTTP_${resp.statusCode}',
      statusCode: resp.statusCode,
    );
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

  // ── Hikaye silme ──────────────────────────────────────────────────────────

  static Future<void> deleteStory(int storyId) async {
    final headers = await _headers();
    final resp = await http.delete(
      Uri.parse('$kBaseUrl/stories/$storyId'),
      headers: headers,
    );
    debugPrint('[StoryService] deleteStory($storyId) → HTTP ${resp.statusCode}');
    if (resp.statusCode >= 400) {
      final body = _tryDecode(resp.body);
      final errMap = body['error'];
      throw AppException(
        errMap is Map
            ? (errMap['message'] ?? 'Hikaye silinemedi')
            : (body['detail'] ?? 'Hikaye silinemedi'),
        code: errMap is Map
            ? (errMap['code'] ?? 'ERR_${resp.statusCode}')
            : 'HTTP_${resp.statusCode}',
        statusCode: resp.statusCode,
      );
    }
  }

  // ── Hikaye yükleme (video dosyası → backend) ───────────────────────────────

  static Future<void> uploadStory(File mediaFile) async {
    final token = await StorageService.getToken();
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$kBaseUrl/stories/upload'),
    );
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    // contentType dosya uzantısına göre belirlenir — bazı iOS/Android cihazlar
    // varsayılan olarak application/octet-stream gönderir ve backend'de 400 alınır.
    final ext = mediaFile.path.split('.').last.toLowerCase();
    final isImage = ['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'].contains(ext);
    final mediaType = isImage ? MediaType('image', ext == 'jpg' ? 'jpeg' : ext) : MediaType('video', 'mp4');
    req.files.add(await http.MultipartFile.fromPath(
      'file',
      mediaFile.path,
      contentType: mediaType,
    ));

    debugPrint('[StoryService] uploadStory → gönderiliyor: ${mediaFile.path}');
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
