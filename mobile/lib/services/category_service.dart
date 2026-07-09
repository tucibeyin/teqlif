import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import '../core/logger_service.dart';

// Categories valid only for live streams, excluded from listing creation
const _listingExcluded = {'sohbet'};

class CategoryService {
  static final Map<String, List<(String, String)>> _cache = {};

  static Future<List<(String, String)>> getCategories({String locale = 'tr'}) async {
    if (_cache.containsKey(locale)) return _cache[locale]!;
    try {
      final response = await http.get(
        Uri.parse('$kBaseUrl/categories'),
        headers: {'Accept-Language': locale},
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        _cache[locale] = data
            .map<(String, String)>((c) => (c['key'] as String, c['label'] as String))
            .where((pair) => !_listingExcluded.contains(pair.$1))
            .toList();
        return _cache[locale]!;
      }
    } catch (e) {
      LoggerService.instance.warning('CategoryService', 'Kategoriler sunucudan alınamadı, fallback kullanılıyor: $e');
    }
    // Fallback: sunucu cevap vermezse ya da parse edilemezse hardcoded liste
    _cache[locale] ??= const [
      ('elektronik', '📱 Elektronik'),
      ('vasita', '🚗 Vasıta'),
      ('emlak', '🏠 Emlak'),
      ('giyim', '👗 Giyim'),
      ('spor', '⚽ Spor'),
      ('kitap', '📚 Kitap & Müzik'),
      ('ev', '🛋 Ev & Bahçe'),
      ('diger', '📦 Diğer'),
    ];
    return _cache[locale]!;
  }

  static void clearCache() => _cache.clear();
}
