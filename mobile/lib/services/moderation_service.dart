import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import 'storage_service.dart';

class ModerationService {
  static Future<Map<String, String>> _headers() async {
    final token = await StorageService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<void> mute(int streamId, String username) async {
    await apiCall(
      () async => http.post(
        Uri.parse('$kBaseUrl/moderation/$streamId/mute'),
        headers: await _headers(),
        body: jsonEncode({'username': username}),
      ),
    );
  }

  static Future<void> unmute(int streamId, String username) async {
    await apiCall(
      () async => http.post(
        Uri.parse('$kBaseUrl/moderation/$streamId/unmute'),
        headers: await _headers(),
        body: jsonEncode({'username': username}),
      ),
    );
  }

  static Future<void> kick(int streamId, String username) async {
    await apiCall(
      () async => http.post(
        Uri.parse('$kBaseUrl/moderation/$streamId/kick'),
        headers: await _headers(),
        body: jsonEncode({'username': username}),
      ),
    );
  }

  /// Belirtilen kullanıcıyı yayının Co-Host (moderatör) olarak atar.
  ///
  /// Sadece yayının asıl host'u çağırabilir.
  /// Başarı durumunda backend, odanın WebSocket kanalına
  /// `{"type": "mod_promoted", "username": "...", "promoted_by": "..."}` eventi fırlatır.
  static Future<void> promoteUser(int streamId, String username) async {
    await apiCall(
      () async => http.post(
        Uri.parse('$kBaseUrl/moderation/$streamId/promote'),
        headers: await _headers(),
        body: jsonEncode({'username': username}),
      ),
    );
  }

  /// Belirtilen kullanıcının moderatörlüğünü geri alır.
  ///
  /// Sadece yayının asıl host'u çağırabilir.
  /// Başarı durumunda backend, odanın WebSocket kanalına
  /// `{"type": "mod_demoted", "username": "...", "demoted_by": "..."}` eventi fırlatır.
  static Future<void> demoteUser(int streamId, String username) async {
    await apiCall(
      () async => http.post(
        Uri.parse('$kBaseUrl/moderation/$streamId/demote'),
        headers: await _headers(),
        body: jsonEncode({'username': username}),
      ),
    );
  }
}
