class CatalogOption {
  const CatalogOption({
    required this.value,
    required this.label,
    required this.labelKey,
    this.parentOptionValue,
    this.exclusionGroup,
    this.isExclusive = false,
  });

  final String value;
  final String label;    // human-readable display name from DB (e.g. "Benzin")
  final String labelKey; // i18n key (e.g. "opt_gasoline")
  final String? parentOptionValue;
  final String? exclusionGroup;
  final bool isExclusive;

  factory CatalogOption.fromJson(Map<String, dynamic> j) {
    final rawParent = j['parent_option_value'] as String?;
    // Support both old API format (parent_option_value overloaded) and
    // new clean format (exclusion_group + is_exclusive columns).
    // Old: parent_option_value='grp:damage_level'  → exclusionGroup='damage_level'
    // Old: parent_option_value='__excl__'          → isExclusive=true
    // New: exclusion_group='damage_level', is_exclusive=true (parent_option_value=null)
    final String? exclusionGroup = j['exclusion_group'] as String? ??
        (rawParent != null && rawParent.startsWith('grp:')
            ? rawParent.substring(4)
            : null);
    final bool isExclusive = j['is_exclusive'] as bool? ??
        (rawParent == '__excl__');
    final String? parentOptionValue = (rawParent != null &&
            !rawParent.startsWith('grp:') &&
            rawParent != '__excl__')
        ? rawParent
        : null;
    return CatalogOption(
      value: j['value'] as String,
      label: j['label'] as String? ?? j['value'] as String,
      labelKey: j['label_key'] as String? ?? 'opt_${j['value']}',
      parentOptionValue: parentOptionValue,
      exclusionGroup: exclusionGroup,
      isExclusive: isExclusive,
    );
  }
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
    this.isListable = true,
  });

  final String key;
  final List<CatalogSubcategory> subcategories;
  /// Eğer false ise bu kategori ilan oluşturma ve filtre ekranlarında gösterilmez.
  /// Örn: chat kategorisi yalnızca canlı yayın kontekstinde kullanılır.
  final bool isListable;

  String get labelKey => 'cat_$key';

  factory CatalogCategory.fromJson(Map<String, dynamic> j) => CatalogCategory(
        key: j['key'] as String,
        isListable: j['is_listable'] as bool? ?? true,
        subcategories: (j['subcategories'] as List<dynamic>? ?? [])
            .map((s) => CatalogSubcategory.fromJson(s as Map<String, dynamic>))
            .toList(),
      );
}
