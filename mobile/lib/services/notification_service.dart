import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import '../core/logger_service.dart';
import 'storage_service.dart';

class NotificationService {
  static Future<Map<String, String>> _headers() async {
    final token = await StorageService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Okunmamış bildirim sayısı — ağ hatası durumunda 0 döner (graceful degrade).
  static Future<int> getUnreadNotifCount() async {
    try {
      final body = await apiCall(
        () async => http.get(Uri.parse('$kBaseUrl/notifications/unread-count'), headers: await _headers()),
      );
      return body['count'] as int? ?? 0;
    } catch (e) {
      LoggerService.instance.warning('NotificationService', 'Bildirim sayısı alınamadı: $e');
      return 0;
    }
  }

  /// Okunmamış mesaj sayısı — ağ hatası durumunda 0 döner (graceful degrade).
  static Future<int> getUnreadMessageCount() async {
    try {
      final body = await apiCall(
        () async => http.get(Uri.parse('$kBaseUrl/messages/unread-count'), headers: await _headers()),
      );
      return body['count'] as int? ?? 0;
    } catch (e) {
      LoggerService.instance.warning('NotificationService', 'Mesaj sayısı alınamadı: $e');
      return 0;
    }
  }

  /// Bildirim listesi — ağ hatası durumunda boş liste döner (graceful degrade).
  static Future<List<dynamic>> getNotifications() async {
    final resp = await http.get(Uri.parse('$kBaseUrl/notifications/'), headers: await _headers());
    if (resp.statusCode == 200) return jsonDecode(resp.body) as List;
    throw Exception('getNotifications HTTP ${resp.statusCode}');
  }

  /// Tümünü okundu işaretle — sessizce başarısız olabilir (background işlem).
  static Future<void> markAllRead() async {
    try {
      await apiCall(
        () async => http.post(Uri.parse('$kBaseUrl/notifications/mark-all-read'), headers: await _headers()),
      );
    } catch (e) {
      LoggerService.instance.warning('NotificationService', 'Okundu işareti başarısız: $e');
    }
  }

  /// Konuşma listesi — hata durumunda exception fırlatır (SWR caller yakalar).
  static Future<List<dynamic>> getConversations() async {
    final resp = await http.get(Uri.parse('$kBaseUrl/messages/conversations'), headers: await _headers());
    if (resp.statusCode == 200) return jsonDecode(resp.body) as List;
    throw Exception('getConversations HTTP ${resp.statusCode}');
  }

  /// Mesaj geçmişi — ağ hatası durumunda boş liste döner (graceful degrade).
  static Future<List<dynamic>> getMessages(int otherUserId) async {
    try {
      final resp = await http.get(Uri.parse('$kBaseUrl/messages/$otherUserId'), headers: await _headers());
      if (resp.statusCode == 200) return jsonDecode(resp.body) as List;
    } catch (e) {
      LoggerService.instance.warning('NotificationService', 'Mesajlar alınamadı: $e');
    }
    return [];
  }

  /// Kullanıcı bilgisi — ağ hatası durumunda null döner (graceful degrade).
  static Future<Map<String, dynamic>?> getUserByUsername(String username) async {
    try {
      final body = await apiCall(
        () async => http.get(Uri.parse('$kBaseUrl/users/$username'), headers: await _headers()),
      );
      return body;
    } catch (e) {
      LoggerService.instance.warning('NotificationService', 'Kullanıcı bilgisi alınamadı ($username): $e');
      return null;
    }
  }

  /// Mesaj gönder — hata durumunda false döner ve loglama yapılır.
  static Future<bool> sendMessage(int receiverId, String content) async {
    try {
      await apiCall(
        () async => http.post(
          Uri.parse('$kBaseUrl/messages/send'),
          headers: await _headers(),
          body: jsonEncode({'receiver_id': receiverId, 'content': content}),
        ),
      );
      return true;
    } catch (e) {
      LoggerService.instance.warning('NotificationService', 'Mesaj gönderilemedi: $e');
      return false;
    }
  }
}
