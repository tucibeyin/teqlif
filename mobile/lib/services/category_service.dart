import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import '../core/logger_service.dart';
import '../l10n/app_localizations.dart';

// Categories valid only for live streams, excluded from listing creation
const _listingExcluded = {'sohbet'};

// Locale-aware fallback labels (matching cat_* ARB keys + emojis from backend)
const _fallbackLabels = <String, Map<String, String>>{
  'tr': {
    'sohbet':     '🗣 Canlı Sohbet',
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
    'sohbet':     '🗣 Live Chat',
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
    'sohbet':     '🗣 دردشة مباشرة',
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
    'sohbet':     '🗣 Живой чат',
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
              (a.$1 == 'sohbet' ? 0 : 1).compareTo(b.$1 == 'sohbet' ? 0 : 1));
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
      'elektronik' => l.cat_elektronik,
      'giyim'      => l.cat_giyim,
      'ev'         => l.cat_ev,
      'vasita'     => l.cat_vasita,
      'spor'       => l.cat_spor,
      'kitap'      => l.cat_kitap,
      'emlak'      => l.cat_emlak,
      'diger'      => l.cat_diger,
      'sohbet'     => l.cat_sohbet,
      _            => key,
    };
  }
}
