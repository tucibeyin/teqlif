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
    return apiCallList(
      () async => http.get(Uri.parse('$kBaseUrl/notifications/'), headers: await _headers()),
    );
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
    return apiCallList(
      () async => http.get(Uri.parse('$kBaseUrl/messages/conversations'), headers: await _headers()),
    );
  }

  /// Mesaj geçmişi — hata durumunda exception fırlatır; çağıran hata durumunu göstermelidir.
  static Future<List<dynamic>> getMessages(int otherUserId) {
    return apiCallList(
      () async => http.get(Uri.parse('$kBaseUrl/messages/$otherUserId'), headers: await _headers()),
    );
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

  /// Tek mesajı sil — hata durumunda false döner.
  static Future<bool> deleteMessage(int messageId) async {
    try {
      await apiCall(
        () async => http.delete(Uri.parse('$kBaseUrl/messages/$messageId'), headers: await _headers()),
      );
      return true;
    } catch (e) {
      LoggerService.instance.warning('NotificationService', 'Mesaj silinemedi: $e');
      return false;
    }
  }

  /// Konuşmayı sil — hata durumunda false döner.
  static Future<bool> deleteConversation(int otherUserId) async {
    try {
      await apiCall(
        () async => http.delete(Uri.parse('$kBaseUrl/messages/conversation/$otherUserId'), headers: await _headers()),
      );
      return true;
    } catch (e) {
      LoggerService.instance.warning('NotificationService', 'Konuşma silinemedi: $e');
      return false;
    }
  }

  /// Mesaj gönder — hata durumunda false döner ve loglama yapılır.
  static Future<bool> sendMessage(int receiverId, String content, {int? listingId}) async {
    try {
      final body = <String, dynamic>{'receiver_id': receiverId, 'content': content};
      if (listingId != null) body['listing_id'] = listingId;
      await apiCall(
        () async => http.post(
          Uri.parse('$kBaseUrl/messages/send'),
          headers: await _headers(),
          body: jsonEncode(body),
        ),
      );
      return true;
    } catch (e) {
      LoggerService.instance.warning('NotificationService', 'Mesaj gönderilemedi: $e');
      return false;
    }
  }
}
