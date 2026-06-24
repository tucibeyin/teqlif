import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import '../services/storage_service.dart';

class WalletService {
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
