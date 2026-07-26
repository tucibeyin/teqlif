class CatalogOption {
  const CatalogOption({
    required this.value,
    required this.label,
    required this.labelKey,
    this.parentOptionValue,
  });

  final String value;
  final String label;    // human-readable display name from DB (e.g. "Benzin")
  final String labelKey; // i18n key (e.g. "opt_gasoline")
  final String? parentOptionValue;

  factory CatalogOption.fromJson(Map<String, dynamic> j) => CatalogOption(
        value: j['value'] as String,
        label: j['label'] as String? ?? j['value'] as String,
        labelKey: j['label_key'] as String? ?? 'opt_${j['value']}',
        parentOptionValue: j['parent_option_value'] as String?,
      );
}

class CatalogField {
  const CatalogField({
    required this.key,
    required this.labelKey,
    required this.type,
    required this.required,
    this.unit,
    this.dependsOn,
    required this.options,
  });

  final String key;
  final String labelKey;
  final String type;
  final bool required;
  final String? unit;
  final String? dependsOn;
  final List<CatalogOption> options;

  factory CatalogField.fromJson(Map<String, dynamic> j) => CatalogField(
        key: j['key'] as String,
        labelKey: j['label_key'] as String,
        type: j['type'] as String,
        required: j['required'] as bool? ?? true,
        unit: j['unit'] as String?,
        dependsOn: j['depends_on'] as String?,
        options: (j['options'] as List<dynamic>? ?? [])
            .map((o) => CatalogOption.fromJson(o as Map<String, dynamic>))
            .toList(),
      );

  /// Top-level options (no parent dependency).
  List<(String, String)> get topLevelOptions => options
      .where((o) => o.parentOptionValue == null)
      .map((o) => (o.value, o.labelKey))
      .toList();

  /// Conditional options grouped by parent option value.
  Map<String, List<(String, String)>> get conditionalOptions {
    final map = <String, List<(String, String)>>{};
    for (final o in options) {
      final p = o.parentOptionValue;
      if (p != null) {
        map.putIfAbsent(p, () => []).add((o.value, o.labelKey));
      }
    }
    return map;
  }
}

class CatalogSubcategory {
  const CatalogSubcategory({required this.key, required this.fields});

  final String key;
  final List<CatalogField> fields;

  String get labelKey => 'subcat_$key';

  factory CatalogSubcategory.fromJson(Map<String, dynamic> j) =>
      CatalogSubcategory(
        key: j['key'] as String,
        fields: (j['fields'] as List<dynamic>? ?? [])
            .map((f) => CatalogField.fromJson(f as Map<String, dynamic>))
            .toList(),
      );
}

class CatalogCategory {
  const CatalogCategory({
    required this.key,
    required this.subcategories,
  });

  final String key;
  final List<CatalogSubcategory> subcategories;

  String get labelKey => 'cat_$key';

  factory CatalogCategory.fromJson(Map<String, dynamic> j) => CatalogCategory(
        key: j['key'] as String,
        subcategories: (j['subcategories'] as List<dynamic>? ?? [])
            .map((s) => CatalogSubcategory.fromJson(s as Map<String, dynamic>))
            .toList(),
      );
}
