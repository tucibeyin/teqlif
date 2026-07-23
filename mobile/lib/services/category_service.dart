import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import '../core/logger_service.dart';
import '../l10n/app_localizations.dart';

// Categories valid only for live streams, excluded from listing creation
const _listingExcluded = {'chat'};

// Locale-aware fallback labels (matching cat_* ARB keys + emojis from backend)
const _fallbackLabels = <String, Map<String, String>>{
  'tr': {
    'chat':       '🗣 Canlı Sohbet',
    'electronics':'📱 Elektronik',
    'fashion':    '👗 Giyim & Moda',
    'home':       '🛋 Ev & Yaşam',
    'vehicles':   '🚗 Vasıta',
    'sports':     '⚽ Spor & Hobi',
    'books':      '📚 Kitap & Kültür',
    'real_estate':'🏠 Emlak',
    'other':      '📦 Diğer',
  },
  'en': {
    'chat':       '🗣 Live Chat',
    'electronics':'📱 Electronics',
    'fashion':    '👗 Clothing & Fashion',
    'home':       '🛋 Home & Living',
    'vehicles':   '🚗 Vehicles',
    'sports':     '⚽ Sports & Hobbies',
    'books':      '📚 Books & Culture',
    'real_estate':'🏠 Real Estate',
    'other':      '📦 Other',
  },
  'ar': {
    'chat':       '🗣 دردشة مباشرة',
    'electronics':'📱 إلكترونيات',
    'fashion':    '👗 ملابس وموضة',
    'home':       '🛋 المنزل والمعيشة',
    'vehicles':   '🚗 مركبات',
    'sports':     '⚽ رياضة وهوايات',
    'books':      '📚 كتب وثقافة',
    'real_estate':'🏠 عقارات',
    'other':      '📦 أخرى',
  },
  'ru': {
    'chat':       '🗣 Живой чат',
    'electronics':'📱 Электроника',
    'fashion':    '👗 Одежда и мода',
    'home':       '🛋 Дом и быт',
    'vehicles':   '🚗 Транспорт',
    'sports':     '⚽ Спорт и хобби',
    'books':      '📚 Книги и культура',
    'real_estate':'🏠 Недвижимость',
    'other':      '📦 Другое',
  },
};

class CategoryService {
  static final Map<String, List<(String, String)>> _cache = {};

  static Future<List<(String, String)>> getCategories({
    String locale = 'tr',
    bool forStream = false,
  }) async {
    final cacheKey = forStream ? '${locale}_stream' : locale;
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey]!;
    try {
      final response = await http.get(
        Uri.parse('$kBaseUrl/categories'),
        headers: {'Accept-Language': locale},
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final all = data
            .map<(String, String)>((c) => (c['key'] as String, c['label'] as String))
            .toList();
        // For listings exclude stream-only categories; for streams keep all
        _cache[cacheKey] = forStream
            ? all
            : all.where((p) => !_listingExcluded.contains(p.$1)).toList();
        // Sort: sohbet first for stream contexts
        if (forStream) {
          _cache[cacheKey]!.sort((a, b) =>
              (a.$1 == 'chat' ? 0 : 1).compareTo(b.$1 == 'chat' ? 0 : 1));
        }
        return _cache[cacheKey]!;
      }
    } catch (e) {
      LoggerService.instance.warning('CategoryService', 'Kategoriler sunucudan alınamadı, fallback kullanılıyor: $e');
    }
    // Fallback: locale-aware translations matching cat_* ARB keys
    final labels = _fallbackLabels[locale] ?? _fallbackLabels['tr']!;
    _cache[cacheKey] = labels.entries
        .where((e) => forStream || !_listingExcluded.contains(e.key))
        .map<(String, String)>((e) => (e.key, e.value))
        .toList();
    return _cache[cacheKey]!;
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

  /// ARB cat_* key'lerini kullanarak emoji içermeyen lokalize kategori adı döner.
  /// Cihaz dilini AppLocalizations üzerinden otomatik yansıtır.
  static String localizedLabelFor(AppLocalizations l, String key) {
    return switch (key) {
      'electronics' => l.cat_electronics,
      'fashion'     => l.cat_fashion,
      'home'        => l.cat_home,
      'vehicles'    => l.cat_vehicles,
      'sports'      => l.cat_sports,
      'books'       => l.cat_books,
      'real_estate' => l.cat_real_estate,
      'other'       => l.cat_other,
      'chat'        => l.cat_chat,
      _             => key,
    };
  }
}
