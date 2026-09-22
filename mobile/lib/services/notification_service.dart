import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/api_client.dart';
import '../core/logger_service.dart';
import 'storage_service.dart';

class NotificationService {
  final ApiClient _api;
  NotificationService(this._api);

  Future<Map<String, String>> _headers() async {
    final token = await StorageService.getToken();
    return _api.buildApiHeaders(token, json: true);
  }

  /// Okunmamış bildirim sayısı — ağ hatası durumunda 0 döner (graceful degrade).
  Future<int> getUnreadNotifCount() async {
    try {
      final body = await _api.call(
        () async => http.get(Uri.parse('${_api.config.baseUrl}/notifications/unread-count'), headers: await _headers()),
      );
      return body['count'] as int? ?? 0;
    } catch (e) {
      LoggerService.instance.warning('NotificationService', 'Bildirim sayısı alınamadı: $e');
      return 0;
    }
  }

  /// Okunmamış mesaj sayısı — ağ hatası durumunda 0 döner (graceful degrade).
  Future<int> getUnreadMessageCount() async {
    try {
      final body = await _api.call(
        () async => http.get(Uri.parse('${_api.config.baseUrl}/messages/unread-count'), headers: await _headers()),
      );
      return body['count'] as int? ?? 0;
    } catch (e) {
      LoggerService.instance.warning('NotificationService', 'Mesaj sayısı alınamadı: $e');
      return 0;
    }
  }

  /// Bildirim listesi — ağ hatası durumunda boş liste döner (graceful degrade).
  Future<List<dynamic>> getNotifications() async {
    return _api.callList(
      () async => http.get(Uri.parse('${_api.config.baseUrl}/notifications/'), headers: await _headers()),
    );
  }

  /// Tümünü okundu işaretle — sessizce başarısız olabilir (background işlem).
  Future<void> markAllRead() async {
    try {
      await _api.call(
        () async => http.post(Uri.parse('${_api.config.baseUrl}/notifications/mark-all-read'), headers: await _headers()),
      );
    } catch (e) {
      LoggerService.instance.warning('NotificationService', 'Okundu işareti başarısız: $e');
    }
  }

  /// Konuşma listesi — hata durumunda exception fırlatır (SWR caller yakalar).
  Future<List<dynamic>> getConversations() async {
    return _api.callList(
      () async => http.get(Uri.parse('${_api.config.baseUrl}/messages/conversations'), headers: await _headers()),
    );
  }

  Future<List<dynamic>> getMessageRequests() async {
    return _api.callList(
      () async => http.get(Uri.parse('${_api.config.baseUrl}/messages/requests'), headers: await _headers()),
    );
  }

  Future<Map<String, dynamic>> getThreadStatus(int otherUserId) async {
    return _api.call(
      () async => http.get(Uri.parse('${_api.config.baseUrl}/messages/thread/$otherUserId/status'), headers: await _headers()),
    );
  }

  Future<void> acceptMessageRequest(int requesterId) async {
    await _api.call(
      () async => http.post(Uri.parse('${_api.config.baseUrl}/messages/requests/$requesterId/accept'), headers: await _headers()),
    );
  }

  Future<void> declineMessageRequest(int requesterId) async {
    await _api.call(
      () async => http.post(Uri.parse('${_api.config.baseUrl}/messages/requests/$requesterId/decline'), headers: await _headers()),
    );
  }

  Future<void> dismissMessageRequest(int requesterId) async {
    await _api.call(
      () async => http.delete(Uri.parse('${_api.config.baseUrl}/messages/requests/$requesterId'), headers: await _headers()),
    );
  }

  Future<void> updateCallPermission(int otherUserId, bool allowed) async {
    await _api.call(() async => http.patch(
      Uri.parse('${_api.config.baseUrl}/messages/thread/$otherUserId/call-permission'),
      headers: await _headers(),
      body: jsonEncode({'call_allowed': allowed}),
    ));
  }

  /// Mesaj geçmişi — hata durumunda exception fırlatır; çağıran hata durumunu göstermelidir.
  Future<List<dynamic>> getMessages(int otherUserId) {
    return _api.callList(
      () async => http.get(Uri.parse('${_api.config.baseUrl}/messages/$otherUserId'), headers: await _headers()),
    );
  }

  /// Kullanıcı bilgisi — ağ hatası durumunda null döner (graceful degrade).
  Future<Map<String, dynamic>?> getUserByUsername(String username) async {
    try {
      final body = await _api.call(
        () async => http.get(Uri.parse('${_api.config.baseUrl}/users/$username'), headers: await _headers()),
      );
      return body;
    } catch (e) {
      LoggerService.instance.warning('NotificationService', 'Kullanıcı bilgisi alınamadı ($username): $e');
      return null;
    }
  }

  /// Tek mesajı sil — hata durumunda false döner.
  Future<bool> deleteMessage(int messageId, {String scope = 'everyone'}) async {
    try {
      await _api.call(
        () async => http.delete(
          Uri.parse('${_api.config.baseUrl}/messages/$messageId?scope=$scope'),
          headers: await _headers(),
        ),
      );
      return true;
    } catch (e) {
      LoggerService.instance.warning('NotificationService', 'Mesaj silinemedi: $e');
      return false;
    }
  }

  /// Mesajı raporla — hata durumunda false döner.
  Future<bool> flagMessage(int messageId, String reason) async {
    try {
      await _api.call(
        () async => http.post(
          Uri.parse('${_api.config.baseUrl}/messages/$messageId/flag?reason=$reason'),
          headers: await _headers(),
        ),
      );
      return true;
    } catch (e) {
      LoggerService.instance.warning('NotificationService', 'Mesaj raporlanamadı: $e');
      return false;
    }
  }

  /// Konuşmayı sil — hata durumunda false döner.
  Future<bool> deleteConversation(int otherUserId) async {
    try {
      await _api.call(
        () async => http.delete(Uri.parse('${_api.config.baseUrl}/messages/conversation/$otherUserId'), headers: await _headers()),
      );
      return true;
    } catch (e) {
      LoggerService.instance.warning('NotificationService', 'Konuşma silinemedi: $e');
      return false;
    }
  }

  /// Mesaj gönder — hata durumunda false döner ve loglama yapılır.
  Future<bool> sendMessage(int receiverId, String content, {int? listingId}) async {
    try {
      final body = <String, dynamic>{'receiver_id': receiverId, 'content': content};
      if (listingId != null) body['listing_id'] = listingId;
      await _api.call(
        () async => http.post(
          Uri.parse('${_api.config.baseUrl}/messages/send'),
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

final notificationServiceProvider = Provider<NotificationService>((ref) =>
    NotificationService(ref.watch(apiClientProvider)));
