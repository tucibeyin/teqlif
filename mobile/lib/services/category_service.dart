import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import '../core/logger_service.dart';
import 'localization_service.dart';

class CategoryService {
  static final Map<String, List<(String, String)>> _cache = {};

  static Future<List<(String, String)>> getCategories({
    String locale = 'tr',
    bool forStream = false,
  }) async {
    final cacheKey = forStream ? '${locale}_stream' : locale;
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey]!;
    try {
      final uri = Uri.parse(
        forStream ? '$kBaseUrl/categories?context=stream' : '$kBaseUrl/categories',
      );
      final response = await http.get(uri, headers: {'Accept-Language': locale});
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        _cache[cacheKey] = data
            .map<(String, String)>((c) => (c['key'] as String, c['label'] as String))
            .toList();
        return _cache[cacheKey]!;
      }
    } catch (e) {
      LoggerService.instance.warning('CategoryService', 'Kategoriler alınamadı: $e');
    }
    return [];
  }

  /// Kategori key'ini lokalize edilmiş label'a çevirir (senkron).
  /// Cache doluysa cache'den, değilse key'i olduğu gibi döner.
  static String labelFor(String key, {String locale = 'tr'}) {
    if (key.isEmpty) return key;
    final cached = _cache[locale];
    if (cached != null) {
      for (final p in cached) {
        if (p.$1 == key) return p.$2;
      }
    }
    return key;
  }

  static void clearCache() => _cache.clear();

  /// ARB cat_* key'lerini kullanarak lokalize kategori adı döner.
  static String localizedLabelFor(TranslationPack loc, String key) {
    return switch (key) {
      'electronics' => loc.t('cat_electronics'),
      'fashion'     => loc.t('cat_fashion'),
      'home'        => loc.t('cat_home'),
      'vehicles'    => loc.t('cat_vehicles'),
      'sports'      => loc.t('cat_sports'),
      'books'       => loc.t('cat_books'),
      'real_estate' => loc.t('cat_real_estate'),
      'other'       => loc.t('cat_other'),
      'chat'        => loc.t('cat_chat'),
      _             => key,
    };
  }
}
