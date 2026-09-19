import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/api_client.dart';
import '../core/app_exception.dart';
import '../models/story.dart';
import 'storage_service.dart';

class StoryService {
  final ApiClient _api;
  StoryService(this._api);

  Future<Map<String, String>> _headers() async {
    final token = await StorageService.getToken();
    return _api.buildApiHeaders(token, json: true);
  }

  // ── Hybrid: video hikayeleri + canlı yayın harmanlama ─────────────────────

  Future<List<UserStoryGroup>> getFollowingStories() async {
    final headers = await _headers();
    final list = await _api.callList(
      () => http.get(Uri.parse('${_api.config.baseUrl}/stories/following'), headers: headers),
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

  Future<List<StoryItem>> getMyStories() async {
    final headers = await _headers();
    final data = await _api.call(
      () => http.get(Uri.parse('${_api.config.baseUrl}/stories/mine'), headers: headers),
    );
    final itemsList = data['items'] as List? ?? [];
    return itemsList
        .map((e) => StoryItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Hikaye beğeni toggle ──────────────────────────────────────────────────

  Future<Map<String, dynamic>> toggleLike(int storyId) async {
    final headers = await _headers();
    return _api.call(
      () => http.post(Uri.parse('${_api.config.baseUrl}/stories/$storyId/like'), headers: headers),
    );
  }

  // ── Hikaye görüntüleme kaydı ──────────────────────────────────────────────

  Future<void> recordStoryView(int storyId) async {
    final headers = await _headers();
    try {
      await _api.call(
        () => http.post(Uri.parse('${_api.config.baseUrl}/stories/$storyId/view'), headers: headers),
      );
    } on AppException catch (e) {
      debugPrint('[StoryService] recordStoryView hata: ${e.message}');
    }
  }

  // ── Hikaye görüntüleyenler ────────────────────────────────────────────────

  Future<List<StoryViewer>> getStoryViewers(int storyId) async {
    final headers = await _headers();
    final data = await _api.call(
      () => http.get(Uri.parse('${_api.config.baseUrl}/stories/$storyId/viewers'), headers: headers),
    );
    final viewers = data['viewers'] as List? ?? [];
    return viewers
        .map((e) => StoryViewer.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Hikaye silme ──────────────────────────────────────────────────────────

  Future<void> deleteStory(int storyId) async {
    final headers = await _headers();
    await _api.call(
      () => http.delete(Uri.parse('${_api.config.baseUrl}/stories/$storyId'), headers: headers),
    );
  }

  // ── Hikaye yükleme (video dosyası → backend) ───────────────────────────────
  // MultipartRequest StreamedResponse döndürdüğü için _api.call kullanılamaz.

  Future<void> uploadStoryBytes(
    List<int> bytes, {
    required String fileName,
    required String mimeType,
  }) async {
    final token = await StorageService.getToken();
    final req = http.MultipartRequest('POST', Uri.parse('${_api.config.baseUrl}/stories/upload'));
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    final parts = mimeType.split('/');
    final mediaType = MediaType(parts[0], parts.length > 1 ? parts[1] : 'octet-stream');
    req.files.add(http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: fileName,
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

  Future<void> uploadStory(File mediaFile) async {
    final token = await StorageService.getToken();
    final req = http.MultipartRequest('POST', Uri.parse('${_api.config.baseUrl}/stories/upload'));
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

final storyServiceProvider = Provider<StoryService>((ref) =>
    StoryService(ref.watch(apiClientProvider)));
