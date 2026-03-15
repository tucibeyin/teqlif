import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import '../models/stream.dart';
import '../services/auth_service.dart';
import 'storage_service.dart';

class StreamService {
  static Future<Map<String, String>> _headers() async {
    final token = await StorageService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static void _checkError(http.Response res) {
    if (res.statusCode >= 400) {
      final body = jsonDecode(res.body);
      throw ApiException(body['detail'] ?? 'Bir hata oluştu');
    }
  }

  static Future<List<StreamOut>> getActiveStreams() async {
    final res = await http.get(
      Uri.parse('$kBaseUrl/streams/active'),
      headers: await _headers(),
    );
    _checkError(res);
    final list = jsonDecode(res.body) as List;
    return list.map((e) => StreamOut.fromJson(e)).toList();
  }

  static Future<StreamTokenOut> startStream(String title, String category) async {
    final res = await http.post(
      Uri.parse('$kBaseUrl/streams/start'),
      headers: await _headers(),
      body: jsonEncode({'title': title, 'category': category}),
    );
    _checkError(res);
    return StreamTokenOut.fromJson(jsonDecode(res.body));
  }

  static Future<void> endStream(int streamId) async {
    final res = await http.post(
      Uri.parse('$kBaseUrl/streams/$streamId/end'),
      headers: await _headers(),
    );
    _checkError(res);
  }

  static Future<JoinTokenOut> joinStream(int streamId) async {
    final res = await http.post(
      Uri.parse('$kBaseUrl/streams/$streamId/join'),
      headers: await _headers(),
    );
    _checkError(res);
    return JoinTokenOut.fromJson(jsonDecode(res.body));
  }

  static Future<void> leaveStream(int streamId) async {
    await http.delete(
      Uri.parse('$kBaseUrl/streams/$streamId/leave'),
      headers: await _headers(),
    );
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
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode >= 400) {
      final decoded = jsonDecode(body);
      throw ApiException(decoded['detail'] ?? 'Thumbnail yüklenemedi');
    }
    return (jsonDecode(body)['thumbnail_url'] as String);
  }
}
