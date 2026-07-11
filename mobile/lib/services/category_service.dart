import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import '../core/logger_service.dart';

// Categories valid only for live streams, excluded from listing creation
const _listingExcluded = {'sohbet'};

// Locale-aware fallback labels (matching cat_* ARB keys + emojis from backend)
const _fallbackLabels = <String, Map<String, String>>{
  'tr': {
    'elektronik': '📱 Elektronik',
    'giyim':      '👗 Giyim & Moda',
    'ev':         '🛋 Ev & Yaşam',
    'vasita':     '🚗 Vasıta',
    'spor':       '⚽ Spor & Hobi',
    'kitap':      '📚 Kitap & Kültür',
    'emlak':      '🏠 Emlak',
    'diger':      '📦 Diğer',
  },
  'en': {
    'elektronik': '📱 Electronics',
    'giyim':      '👗 Clothing & Fashion',
    'ev':         '🛋 Home & Living',
    'vasita':     '🚗 Vehicles',
    'spor':       '⚽ Sports & Hobbies',
    'kitap':      '📚 Books & Culture',
    'emlak':      '🏠 Real Estate',
    'diger':      '📦 Other',
  },
  'ar': {
    'elektronik': '📱 إلكترونيات',
    'giyim':      '👗 ملابس وموضة',
    'ev':         '🛋 المنزل والمعيشة',
    'vasita':     '🚗 مركبات',
    'spor':       '⚽ رياضة وهوايات',
    'kitap':      '📚 كتب وثقافة',
    'emlak':      '🏠 عقارات',
    'diger':      '📦 أخرى',
  },
  'ru': {
    'elektronik': '📱 Электроника',
    'giyim':      '👗 Одежда и мода',
    'ev':         '🛋 Дом и быт',
    'vasita':     '🚗 Транспорт',
    'spor':       '⚽ Спорт и хобби',
    'kitap':      '📚 Книги и культура',
    'emlak':      '🏠 Недвижимость',
    'diger':      '📦 Другое',
  },
};

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
    // Fallback: locale-aware translations matching cat_* ARB keys
    final labels = _fallbackLabels[locale] ?? _fallbackLabels['tr']!;
    _cache[locale] = labels.entries
        .where((e) => !_listingExcluded.contains(e.key))
        .map<(String, String)>((e) => (e.key, e.value))
        .toList();
    return _cache[locale]!;
  }

  /// Kategori key'ini lokalize edilmiş label'a çevirir (senkron).
  /// Cache doluysa cache'den, değilse statik fallback'ten döner.
  static String labelFor(String key, {String locale = 'tr'}) {
    if (key.isEmpty) return key;
    final cached = _cache[locale];
    if (cached != null) {
      for (final p in cached) {
        if (p.$1 == key) return p.$2;
      }
    }
    final labels = _fallbackLabels[locale] ?? _fallbackLabels['tr']!;
    return labels[key] ?? key;
  }

  static void clearCache() => _cache.clear();
}
