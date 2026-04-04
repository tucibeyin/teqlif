import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import '../core/app_exception.dart';
import '../models/stream.dart';
import 'storage_service.dart';

class StreamService {
  static Future<Map<String, String>> _headers() async {
    final token = await StorageService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<List<StreamOut>> getActiveStreams() async {
    final headers = await _headers();
    final resp = await http.get(Uri.parse('$kBaseUrl/streams/active'), headers: headers);
    debugPrint('[StreamService] getActiveStreams → HTTP ${resp.statusCode}, body: ${resp.body.length > 200 ? resp.body.substring(0, 200) : resp.body}');
    if (resp.statusCode >= 400) {
      final body = _tryDecode(resp.body);
      final errMap = body['error'];
      throw AppException(
        errMap is Map ? (errMap['message'] ?? 'Bir hata oluştu') : (body['detail'] ?? 'Bir hata oluştu'),
        code: errMap is Map ? (errMap['code'] ?? 'ERR_${resp.statusCode}') : 'HTTP_${resp.statusCode}',
        statusCode: resp.statusCode,
      );
    }
    final list = _tryDecodeList(resp.body);
    debugPrint('[StreamService] getActiveStreams → parse edilen öğe sayısı: ${list.length}');
    final result = <StreamOut>[];
    for (final e in list) {
      try {
        result.add(StreamOut.fromJson(e as Map<String, dynamic>));
      } catch (err) {
        debugPrint('[StreamService] StreamOut.fromJson hatası: $err | veri: $e');
      }
    }
    return result;
  }

  static Future<List<StreamOut>> getFollowedLiveStreams() async {
    final headers = await _headers();
    final resp = await http.get(
      Uri.parse('$kBaseUrl/streams/following/live'),
      headers: headers,
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
    return list
        .map((e) => StreamOut.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<StreamTokenOut> startStream(
    String title,
    String category, {
    String? captchaToken,
  }) async {
    final headers = await _headers();
    if (captchaToken != null && captchaToken.isNotEmpty) {
      headers['X-Captcha-Token'] = captchaToken;
    }
    final body = await apiCall(
      () async => http.post(
        Uri.parse('$kBaseUrl/streams/start'),
        headers: headers,
        body: jsonEncode({'title': title, 'category': category}),
      ),
    );
    return StreamTokenOut.fromJson(body);
  }

  static Future<void> endStream(int streamId) async {
    await apiCall(
      () async => http.post(Uri.parse('$kBaseUrl/streams/$streamId/end'), headers: await _headers()),
    );
  }

  static Future<JoinTokenOut> joinStream(int streamId) async {
    final body = await apiCall(
      () async => http.post(Uri.parse('$kBaseUrl/streams/$streamId/join'), headers: await _headers()),
    );
    return JoinTokenOut.fromJson(body);
  }

  /// Canlı yayına kalp gönder (add-only, backend throttle olmadan — istemci throttle'ı kullanır).
  static Future<void> likeStream(int streamId) async {
    await http.post(
      Uri.parse('$kBaseUrl/streams/$streamId/like'),
      headers: await _headers(),
    );
  }

  static Future<void> leaveStream(int streamId) async {
    await http.delete(
      Uri.parse('$kBaseUrl/streams/$streamId/leave'),
      headers: await _headers(),
    );
  }

  static Future<List<String>> getViewers(int streamId) async {
    final headers = await _headers();
    final resp = await http.get(Uri.parse('$kBaseUrl/streams/$streamId/viewers'), headers: headers);
    if (resp.statusCode >= 400) {
      throw AppException('İzleyiciler alınamadı', statusCode: resp.statusCode);
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    return List<String>.from(body['viewers'] as List);
  }

  static Future<String> uploadThumbnail(int streamId, Uint8List bytes, String filename) async {
    final token = await StorageService.getToken();
    final req = http.MultipartRequest(
      'PATCH',
      Uri.parse('$kBaseUrl/streams/$streamId/thumbnail'),
    );
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamed = await req.send();
    final bodyStr = await streamed.stream.bytesToString();
    if (streamed.statusCode >= 400) {
      final decoded = _tryDecode(bodyStr);
      final errMap = decoded['error'];
      throw AppException(
        errMap is Map ? (errMap['message'] ?? 'Thumbnail yüklenemedi') : (decoded['detail'] ?? 'Thumbnail yüklenemedi'),
        statusCode: streamed.statusCode,
      );
    }
    return (_tryDecode(bodyStr)['thumbnail_url'] as String);
  }

  /// Bir izleyiciyi sahneye davet et (host → POST /cohost/invite).
  static Future<void> inviteCoHost(int streamId, String username) async {
    await apiCall(
      () async => http.post(
        Uri.parse('$kBaseUrl/streams/$streamId/cohost/invite'),
        headers: await _headers(),
        body: jsonEncode({'target_username': username}),
      ),
    );
  }

  /// Sahne davetini kabul et — yeni can_publish=true token döner (viewer → POST /cohost/accept).
  static Future<StreamTokenOut> acceptCoHostInvite(int streamId) async {
    final body = await apiCall(
      () async => http.post(
        Uri.parse('$kBaseUrl/streams/$streamId/cohost/accept'),
        headers: await _headers(),
      ),
    );
    return StreamTokenOut.fromJson(body);
  }

  /// Sahnedeki konuğu kaldır (host → POST /cohost/remove).
  static Future<void> removeCoHost(int streamId, String username) async {
    await apiCall(
      () async => http.post(
        Uri.parse('$kBaseUrl/streams/$streamId/cohost/remove'),
        headers: await _headers(),
        body: jsonEncode({'target_username': username}),
      ),
    );
  }

  /// Gönüllü sahneden ayrıl — cohost_removed WS sinyali yayınlanır (viewer → POST /cohost/leave).
  static Future<void> leaveCoHost(int streamId) async {
    await apiCall(
      () async => http.post(
        Uri.parse('$kBaseUrl/streams/$streamId/cohost/leave'),
        headers: await _headers(),
      ),
    );
  }

  static Map<String, dynamic> _tryDecode(String body) {
    try { return jsonDecode(body) as Map<String, dynamic>; } catch (_) { return {}; }
  }

  static List _tryDecodeList(String body) {
    try { return jsonDecode(body) as List; } catch (_) { return []; }
  }
}
