import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import '../services/auth_service.dart';
import 'storage_service.dart';

class ModerationService {
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

  static Future<void> mute(int streamId, String username) async {
    final res = await http.post(
      Uri.parse('$kBaseUrl/moderation/$streamId/mute'),
      headers: await _headers(),
      body: jsonEncode({'username': username}),
    );
    _checkError(res);
  }

  static Future<void> unmute(int streamId, String username) async {
    final res = await http.post(
      Uri.parse('$kBaseUrl/moderation/$streamId/unmute'),
      headers: await _headers(),
      body: jsonEncode({'username': username}),
    );
    _checkError(res);
  }

  static Future<void> kick(int streamId, String username) async {
    final res = await http.post(
      Uri.parse('$kBaseUrl/moderation/$streamId/kick'),
      headers: await _headers(),
      body: jsonEncode({'username': username}),
    );
    _checkError(res);
  }
}
