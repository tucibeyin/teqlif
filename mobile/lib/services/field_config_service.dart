import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import '../core/logger_service.dart';
import '../models/catalog.dart';
import '../services/catalog_service.dart';
import '../utils/listing_fields.dart';

class FieldConfigService {
  static final Map<String, List<ExtraFieldDef>> _cache = {};

  static Future<List<ExtraFieldDef>> getFields(String subcategory) async {
    if (_cache.containsKey(subcategory)) return _cache[subcategory]!;

    // When CatalogService has the data in memory, use it directly (no HTTP).
    if (CatalogService.isReady) {
      final catalogFields = CatalogService.fieldsFor(subcategory);
      if (catalogFields != null) {
        final fields = catalogFields.map(_fromCatalog).toList();
        _cache[subcategory] = fields;
        return fields;
      }
    }

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

  static ExtraFieldDef _fromCatalog(CatalogField f) {
    final type = switch (f.type) {
      'number'      => ExtraFieldType.number,
      'dropdown'    => ExtraFieldType.dropdown,
      'multiselect' => ExtraFieldType.multiselect,
      _             => ExtraFieldType.text,
    };

    final allOptions = f.options.map((o) => FieldOption(
          o.value,
          o.label,
          o.parentOptionValue,
        )).toList();

    final topOptions = allOptions
        .where((o) => o.parentOptionValue == null)
        .toList();

    Map<String, List<FieldOption>>? conditionalOptions;
    final condEntries = allOptions.where((o) => o.parentOptionValue != null);
    if (condEntries.isNotEmpty) {
      conditionalOptions = <String, List<FieldOption>>{};
      for (final opt in condEntries) {
        (conditionalOptions[opt.parentOptionValue!] ??= []).add(opt);
      }
    }

    return ExtraFieldDef(
      key: f.key,
      labelKey: f.labelKey,
      type: type,
      optional: !f.required,
      options: topOptions,
      unit: f.unit,
      dependsOn: f.dependsOn,
      conditionalOptions: conditionalOptions,
    );
  }
}
