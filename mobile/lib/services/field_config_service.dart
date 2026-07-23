import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import '../core/logger_service.dart';
import '../utils/listing_fields.dart';

class FieldConfigService {
  static final Map<String, List<ExtraFieldDef>> _cache = {};

  static Future<List<ExtraFieldDef>> getFields(String subcategory) async {
    if (_cache.containsKey(subcategory)) return _cache[subcategory]!;

    try {
      final resp = await http
          .get(Uri.parse('$kBaseUrl/field-config/$subcategory'))
          .timeout(const Duration(seconds: 8));

      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        final rawFields = body['fields'] as List<dynamic>? ?? [];
        final fields = rawFields
            .map((f) => ExtraFieldDef.fromJson(f as Map<String, dynamic>))
            .toList();
        _cache[subcategory] = fields;
        return fields;
      }

      if (resp.statusCode == 404) return [];
    } catch (e) {
      LoggerService.instance.warning('FieldConfigService', 'Alan şeması alınamadı [$subcategory]: $e');
    }

    return _fallback(subcategory);
  }

  // Returns local dart constant as fallback when server is unreachable.
  static List<ExtraFieldDef> _fallback(String subcategory) =>
      kSubcategoryFields[subcategory] ?? [];

  static void clearCache() => _cache.clear();
}
