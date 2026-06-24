import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import '../services/storage_service.dart';

class WalletService {
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
        Uri.parse('$kBaseUrl/wallet/send-gift'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
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
      return {'ok': false, 'error': body?['detail'] ?? 'Bir hata oluştu.'};
    } catch (_) {
      return {'ok': false, 'error': 'Bağlantı hatası.'};
    }
  }

  static Future<Map<String, dynamic>?> getBalance({int limit = 5}) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      final resp = await http.get(
        Uri.parse('$kBaseUrl/wallet/balance?limit=$limit'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }
}
