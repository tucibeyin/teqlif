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
    final list = await apiCallList(
      () => http.get(Uri.parse('$kBaseUrl/stories/following'), headers: headers),
    );
    final result = <UserStoryGroup>[];
    for (final e in list) {
      try {
        result.add(UserStoryGroup.fromJson(e as Map<String, dynamic>));
      } catch (err) {
        debugPrint('[StoryService] UserStoryGroup.fromJson hatası: $err | veri: $e');
      }
    }
    return result;
  }

  // ── Kendi hikayelerim ─────────────────────────────────────────────────────

  static Future<List<StoryItem>> getMyStories() async {
    final headers = await _headers();
    final data = await apiCall(
      () => http.get(Uri.parse('$kBaseUrl/stories/mine'), headers: headers),
    );
    final itemsList = data['items'] as List? ?? [];
    return itemsList
        .map((e) => StoryItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Hikaye beğeni toggle ──────────────────────────────────────────────────

  static Future<Map<String, dynamic>> toggleLike(int storyId) async {
    final headers = await _headers();
    return apiCall(
      () => http.post(Uri.parse('$kBaseUrl/stories/$storyId/like'), headers: headers),
    );
  }

  // ── Hikaye görüntüleme kaydı ──────────────────────────────────────────────

  static Future<void> recordStoryView(int storyId) async {
    final headers = await _headers();
    try {
      await apiCall(
        () => http.post(Uri.parse('$kBaseUrl/stories/$storyId/view'), headers: headers),
      );
    } on AppException catch (e) {
      debugPrint('[StoryService] recordStoryView hata: ${e.message}');
    }
  }

  // ── Hikaye görüntüleyenler ────────────────────────────────────────────────

  static Future<List<StoryViewer>> getStoryViewers(int storyId) async {
    final headers = await _headers();
    final data = await apiCall(
      () => http.get(Uri.parse('$kBaseUrl/stories/$storyId/viewers'), headers: headers),
    );
    final viewers = data['viewers'] as List? ?? [];
    return viewers
        .map((e) => StoryViewer.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Hikaye silme ──────────────────────────────────────────────────────────

  static Future<void> deleteStory(int storyId) async {
    final headers = await _headers();
    await apiCall(
      () => http.delete(Uri.parse('$kBaseUrl/stories/$storyId'), headers: headers),
    );
  }

  // ── Hikaye yükleme (video dosyası → backend) ───────────────────────────────
  // MultipartRequest StreamedResponse döndürdüğü için apiCall kullanılamaz.

  static Future<void> uploadStory(File mediaFile) async {
    final token = await StorageService.getToken();
    final req = http.MultipartRequest('POST', Uri.parse('$kBaseUrl/stories/upload'));
    if (token != null) req.headers['Authorization'] = 'Bearer $token';

    final ext = mediaFile.path.split('.').last.toLowerCase();
    final isImage = ['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'].contains(ext);
    final mediaType = isImage
        ? MediaType('image', ext == 'jpg' ? 'jpeg' : ext)
        : MediaType('video', 'mp4');
    req.files.add(await http.MultipartFile.fromPath(
      'file',
      mediaFile.path,
      contentType: mediaType,
    ));

    final streamed = await req.send();
    final bodyStr = await streamed.stream.bytesToString();

    if (streamed.statusCode >= 400) {
      Map<String, dynamic> decoded;
      try {
        decoded = jsonDecode(bodyStr) as Map<String, dynamic>;
      } catch (_) {
        decoded = {};
      }
      final errMap = decoded['error'];
      final message = errMap is Map
          ? (errMap['message'] as String? ?? 'Hikaye yüklenemedi.')
          : (decoded['detail'] as String? ?? 'Hikaye yüklenemedi.');
      final code = errMap is Map
          ? (errMap['code'] as String? ?? 'UPLOAD_ERROR')
          : 'HTTP_${streamed.statusCode}';
      throw AppException(message, code: code, statusCode: streamed.statusCode);
    }
  }
}
