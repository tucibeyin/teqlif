import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import 'storage_service.dart';

class NotificationService {
  static Future<Map<String, String>> _headers() async {
    final token = await StorageService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<int> getUnreadNotifCount() async {
    try {
      final resp = await http.get(
        Uri.parse('$kBaseUrl/notifications/unread-count'),
        headers: await _headers(),
      );
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body)['count'] as int;
      }
    } catch (_) {}
    return 0;
  }

  static Future<int> getUnreadMessageCount() async {
    try {
      final resp = await http.get(
        Uri.parse('$kBaseUrl/messages/unread-count'),
        headers: await _headers(),
      );
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body)['count'] as int;
      }
    } catch (_) {}
    return 0;
  }

  static Future<List<dynamic>> getNotifications() async {
    try {
      final resp = await http.get(
        Uri.parse('$kBaseUrl/notifications/'),
        headers: await _headers(),
      );
      if (resp.statusCode == 200) return jsonDecode(resp.body) as List;
    } catch (_) {}
    return [];
  }

  static Future<void> markAllRead() async {
    try {
      await http.post(
        Uri.parse('$kBaseUrl/notifications/mark-all-read'),
        headers: await _headers(),
      );
    } catch (_) {}
  }

  static Future<List<dynamic>> getConversations() async {
    try {
      final resp = await http.get(
        Uri.parse('$kBaseUrl/messages/conversations'),
        headers: await _headers(),
      );
      if (resp.statusCode == 200) return jsonDecode(resp.body) as List;
    } catch (_) {}
    return [];
  }

  static Future<List<dynamic>> getMessages(int otherUserId) async {
    try {
      final resp = await http.get(
        Uri.parse('$kBaseUrl/messages/$otherUserId'),
        headers: await _headers(),
      );
      if (resp.statusCode == 200) return jsonDecode(resp.body) as List;
    } catch (_) {}
    return [];
  }

  static Future<Map<String, dynamic>?> getUserByUsername(String username) async {
    try {
      final resp = await http.get(
        Uri.parse('$kBaseUrl/users/$username'),
        headers: await _headers(),
      );
      if (resp.statusCode == 200) return jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  static Future<bool> sendMessage(int receiverId, String content) async {
    try {
      final resp = await http.post(
        Uri.parse('$kBaseUrl/messages/send'),
        headers: await _headers(),
        body: jsonEncode({'receiver_id': receiverId, 'content': content}),
      );
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
