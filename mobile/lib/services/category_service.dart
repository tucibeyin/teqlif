import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api.dart';

class CategoryService {
  static List<(String, String)>? _cache;

  static Future<List<(String, String)>> getCategories() async {
    if (_cache != null) return _cache!;
    try {
      final response = await http.get(Uri.parse('$kBaseUrl/categories'));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        _cache = data
            .map<(String, String)>((c) => (c['key'] as String, c['label'] as String))
            .toList();
        return _cache!;
      }
    } catch (_) {}
    // Fallback: hardcoded liste (offline veya sunucu hatası)
    _cache = const [
      ('elektronik', '📱 Elektronik'),
      ('giyim', '👗 Giyim'),
      ('ev', '🛋 Ev & Bahçe'),
      ('vasita', '🚗 Vasıta'),
      ('spor', '⚽ Spor'),
      ('kitap', '📚 Kitap & Müzik'),
      ('diger', '📦 Diğer'),
    ];
    return _cache!;
  }

  static void clearCache() => _cache = null;
}
