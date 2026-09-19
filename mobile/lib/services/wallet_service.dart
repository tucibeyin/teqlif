import 'dart:convert';
import 'package:http/http.dart' as http;
import '../main.dart' show providerContainer;
import '../core/network/api_client.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

class WalletService {
  static Future<Map<String, String>> _headers(String? token, {bool json = false}) async {
    final h = <String, String>{};
    if (token != null) h['Authorization'] = 'Bearer $token';
    if (json) h['Content-Type'] = 'application/json';
    return h;
  }

  static Future<Map<String, dynamic>> sendGift({
    required int streamId,
    required String receiverUsername,
    required String giftName,
    required int cost,
  }) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return {'ok': false, 'error': 'Oturum bulunamadı.'};
      final resp = await http.post(
        Uri.parse('${providerContainer.read(apiClientProvider).config.baseUrl}/wallet/send-gift'),
        headers: await _headers(token, json: true),
        body: jsonEncode({
          'stream_id': streamId,
          'receiver_username': receiverUsername,
          'gift_name': giftName,
          'cost': cost,
        }),
      );
      if (resp.statusCode == 200) {
        return {'ok': true, ...(jsonDecode(resp.body) as Map<String, dynamic>)};
      }
      final body = jsonDecode(resp.body) as Map<String, dynamic>?;
      final errMap = body?['error'] as Map?;
      final msg = errMap?['message'] as String? ?? body?['detail'] as String? ?? 'Bir hata oluştu.';
      return {'ok': false, 'error': msg, 'status_code': resp.statusCode};
    } catch (_) {
      return {'ok': false, 'error': 'Bağlantı hatası.'};
    }
  }

  static Future<Map<String, dynamic>?> getBalance({int limit = 5}) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      final resp = await http.get(
        Uri.parse('${providerContainer.read(apiClientProvider).config.baseUrl}/wallet/balance?limit=$limit'),
        headers: await _headers(token),
      );
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  static Future<Map<String, dynamic>?> getTransactionDetail(int txnId) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      final resp = await http.get(
        Uri.parse('${providerContainer.read(apiClientProvider).config.baseUrl}/wallet/transaction/$txnId'),
        headers: await _headers(token),
      );
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  /// SWR Stream: önce Hive cache, sonra taze API verisi.
  /// Giriş yapılmamışsa stream hiç emit etmez.
  /// [bypassCache]: pull-to-refresh için cache okumayı atlar.
  static Stream<Map<String, dynamic>> getBalanceStream({
    int limit = 5,
    bool bypassCache = false,
  }) =>
      ApiService(providerContainer.read(apiClientProvider)).get<Map<String, dynamic>>(
        url: '${providerContainer.read(apiClientProvider).config.baseUrl}/wallet/balance?limit=$limit',
        cacheKey: 'user_wallet_data',
        cacheTtl: const Duration(minutes: 2),
        bypassCache: bypassCache,
        fromJson: (raw) => raw as Map<String, dynamic>,
      );
}
