import 'dart:convert';
import 'dart:typed_data';
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
    return list.map((e) => StreamOut.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<StreamTokenOut> startStream(String title, String category) async {
    final body = await apiCall(
      () async => http.post(
        Uri.parse('$kBaseUrl/streams/start'),
        headers: await _headers(),
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

  static Map<String, dynamic> _tryDecode(String body) {
    try { return jsonDecode(body) as Map<String, dynamic>; } catch (_) { return {}; }
  }

  static List _tryDecodeList(String body) {
    try { return jsonDecode(body) as List; } catch (_) { return []; }
  }
}
