import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_colors.dart';
import '../config/theme.dart';
import '../models/catalog.dart';
import '../models/listing_filter_state.dart';
import '../services/catalog_service.dart';
import '../services/city_service.dart';
import '../services/field_config_service.dart';
import '../services/localization_service.dart';
import '../utils/listing_fields.dart';

class ListingFilterSheet extends ConsumerStatefulWidget {
  const ListingFilterSheet._({
    required this.initial,
    required this.showCategory,
    required this.showSubcategory,
    required this.showExtraFields,
    required this.showCity,
    required this.showCondition,
    required this.showSort,
    required this.showPriceRange,
  });

  final ListingFilterState initial;
  final bool showCategory;
  final bool showSubcategory;
  final bool showExtraFields;
  final bool showCity;
  final bool showCondition;
  final bool showSort;
  final bool showPriceRange;

  static Future<ListingFilterState?> show(
    BuildContext context, {
    required ListingFilterState initial,
    bool showCategory = true,
    bool showSubcategory = true,
    bool showExtraFields = true,
    bool showCity = true,
    bool showCondition = true,
    bool showSort = true,
    bool showPriceRange = true,
  }) =>
      showModalBottomSheet<ListingFilterState>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.surface(context),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (_) => ListingFilterSheet._(
          initial: initial,
          showCategory: showCategory,
          showSubcategory: showSubcategory,
          showExtraFields: showExtraFields,
          showCity: showCity,
          showCondition: showCondition,
          showSort: showSort,
          showPriceRange: showPriceRange,
        ),
      );

  @override
  ConsumerState<ListingFilterSheet> createState() =>
      _ListingFilterSheetState();
}

class _ListingFilterSheetState extends ConsumerState<ListingFilterSheet> {
  late ListingFilterState _pending;
  final _minController = TextEditingController();
  final _maxController = TextEditingController();
  List<String> _cities = [];
  bool _citiesLoaded = false;

  List<ExtraFieldDef> _fields = [];
  bool _fieldsLoading = false;
  final Map<String, TextEditingController> _extraCtrls = {};

  @override
  void initState() {
    super.initState();
    _pending = widget.initial;
    if (_pending.minPrice != null) {
      _minController.text = _pending.minPrice!.toStringAsFixed(0);
    }
    if (_pending.maxPrice != null) {
      _maxController.text = _pending.maxPrice!.toStringAsFixed(0);
    }
    if (widget.showCity) {
      CityService.getCities().then((c) {
        if (mounted) setState(() { _cities = c; _citiesLoaded = true; });
      });
    }
    if (widget.showExtraFields && _pending.subcategory != null) {
      _loadFields(_pending.subcategory!);
    }
  }

  @override
  void dispose() {
    _minController.dispose();
    _maxController.dispose();
    for (final ctrl in _extraCtrls.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  Future<void> _loadFields(String subcategoryKey) async {
    setState(() { _fieldsLoading = true; _fields = []; });
    final fields = await FieldConfigService.getFields(subcategoryKey);
    if (!mounted) return;
    for (final f in fields) {
      if (f.type == ExtraFieldType.number || f.type == ExtraFieldType.text) {
        _extraCtrls[f.key] ??= TextEditingController(
          text: _pending.extraFields[f.key]?.toString() ?? '',
        );
      }
    }
    setState(() { _fields = fields; _fieldsLoading = false; });
  }

  void _setCategory(String? key) {
    for (final ctrl in _extraCtrls.values) {
      ctrl.dispose();
    }
    _extraCtrls.clear();
    setState(() {
      _fields = [];
      _pending = _pending.copyWith(
        category: key,
        subcategory: null,
        extraFields: {},
      );
    });
  }

  void _setSubcategory(String? key) {
    for (final ctrl in _extraCtrls.values) {
      ctrl.dispose();
    }
    _extraCtrls.clear();
    setState(() => _pending = _pending.copyWith(subcategory: key, extraFields: {}));
    if (key != null && widget.showExtraFields) _loadFields(key);
  }

  void _setExtraField(String fieldKey, dynamic value) {
    final fields = Map<String, dynamic>.from(_pending.extraFields);
    if (value == null) {
      fields.remove(fieldKey);
    } else {
      fields[fieldKey] = value;
    }
    setState(() => _pending = _pending.copyWith(extraFields: fields));
  }

  Widget _buildCategoryDropdown(TranslationPack loc) {
    final categories = CatalogService.isReady
        ? CatalogService.categories
        : kSubcategories.keys
            .map((k) => CatalogCategory(key: k, subcategories: const []))
            .toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: DropdownButtonFormField<String>(
        // ignore: deprecated_member_use
        value: _pending.category,
        decoration: _fieldDecor(loc.tOr('filterCategoryAll', 'Tüm Kategoriler')),
        hint: Text(loc.tOr('filterCategoryAll', 'Tüm Kategoriler')),
        items: [
          DropdownMenuItem<String>(
            value: null,
            child: Text(loc.tOr('filterCategoryAll', 'Tüm Kategoriler')),
          ),
          ...categories.map((c) => DropdownMenuItem<String>(
                value: c.key,
                child: Text(loc.t(c.labelKey)),
              )),
        ],
        onChanged: (v) => _setCategory(v),
      ),
    );
  }

  Widget _buildSubcategoryDropdown(TranslationPack loc) {
    final subcats = CatalogService.subcategoriesFor(_pending.category!);
    if (subcats.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: DropdownButtonFormField<String>(
        // ignore: deprecated_member_use
        value: _pending.subcategory,
        decoration: _fieldDecor(loc.tOr('filterSubcategoryAll', 'Tüm Alt Kategoriler')),
        hint: Text(loc.tOr('filterSubcategoryAll', 'Tüm Alt Kategoriler')),
        items: [
          DropdownMenuItem<String>(
            value: null,
            child: Text(loc.tOr('filterSubcategoryAll', 'Tüm Alt Kategoriler')),
          ),
          ...subcats.map((s) {
            final (key, labelKey) = s;
            return DropdownMenuItem<String>(
              value: key,
              child: Text(loc.t(labelKey)),
            );
          }),
        ],
        onChanged: (v) => _setSubcategory(v),
      ),
    );
  }

  Widget _buildFilterExtraField(ExtraFieldDef f, TranslationPack loc) {
    final label = loc.t(f.labelKey);

    if (f.dependsOn != null) {
      final parentVal = _pending.extraFields[f.dependsOn!] as String?;
      final options = parentVal != null
          ? (f.conditionalOptions?[parentVal] ?? <FieldOption>[])
          : <FieldOption>[];
      return AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        child: options.isEmpty
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: DropdownButtonFormField<String>(
                  // ignore: deprecated_member_use
                  value: _pending.extraFields[f.key] as String?,
                  decoration: _fieldDecor(label),
                  hint: Text(label),
                  items: [
                    DropdownMenuItem<String>(
                      value: null,
                      child: Text(loc.tOr('filterFieldAll', 'Tümü')),
                    ),
                    ...options.map((o) => DropdownMenuItem<String>(
                          value: o.value,
                          child: Text(loc.tOr('opt_${o.value}', o.label)),
                        )),
                  ],
                  onChanged: (v) => _setExtraField(f.key, v),
                ),
              ),
      );
    }

    switch (f.type) {
      case ExtraFieldType.dropdown:
        final items = f.key == 'year'
            ? [
                DropdownMenuItem<String>(
                  value: null,
                  child: Text(loc.tOr('filterFieldAll', 'Tümü')),
                ),
                ...List.generate(
                  DateTime.now().year - 1899,
                  (i) {
                    final y = (DateTime.now().year - i).toString();
                    return DropdownMenuItem<String>(value: y, child: Text(y));
                  },
                ),
              ]
            : [
                DropdownMenuItem<String>(
                  value: null,
                  child: Text(loc.tOr('filterFieldAll', 'Tümü')),
                ),
                ...f.options.map((o) => DropdownMenuItem<String>(
                      value: o.value,
                      child: Text(loc.tOr('opt_${o.value}', o.label)),
                    )),
              ];
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: DropdownButtonFormField<String>(
            // ignore: deprecated_member_use
            value: _pending.extraFields[f.key] as String?,
            decoration: _fieldDecor(label, unit: f.unit),
            hint: Text(label),
            items: items,
            onChanged: (v) {
              _setExtraField(f.key, v);
              for (final dep in _fields) {
                if (dep.dependsOn == f.key) _setExtraField(dep.key, null);
              }
            },
          ),
        );

      case ExtraFieldType.number:
        final ctrl = _extraCtrls[f.key] ??= TextEditingController(
          text: _pending.extraFields[f.key]?.toString() ?? '',
        );
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            style: TextStyle(fontSize: 14, color: AppColors.textPrimary(context)),
            decoration: _fieldDecor(label, unit: f.unit),
            onChanged: (v) => _setExtraField(f.key, v.isEmpty ? null : v),
          ),
        );

      case ExtraFieldType.text:
        final ctrl = _extraCtrls[f.key] ??= TextEditingController(
          text: _pending.extraFields[f.key]?.toString() ?? '',
        );
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: TextField(
            controller: ctrl,
            style: TextStyle(fontSize: 14, color: AppColors.textPrimary(context)),
            decoration: _fieldDecor(label),
            onChanged: (v) => _setExtraField(f.key, v.isEmpty ? null : v),
          ),
        );

      case ExtraFieldType.multiselect:
        final selected = (_pending.extraFields[f.key] as List<dynamic>?)
                ?.cast<String>()
                .toSet() ??
            {};
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary(context),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: f.options.map((o) {
                  final isSelected = selected.contains(o.value);
                  return _FilterChip(
                    label: loc.tOr('opt_${o.value}', o.label),
                    selected: isSelected,
                    onTap: () {
                      final newSet = Set<String>.from(selected);
                      if (isSelected) {
                        newSet.remove(o.value);
                      } else {
                        if (o.isExclusive) newSet.clear();
                        newSet.add(o.value);
                      }
                      _setExtraField(f.key, newSet.isEmpty ? null : newSet.toList());
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        );
    }
  }

  InputDecoration _fieldDecor(String label, {String? unit}) => InputDecoration(
        labelText: label,
        suffixText: unit,
        filled: true,
        fillColor: AppColors.inputFill(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(localizationProvider);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      maxChildSize: 0.92,
      builder: (_, controller) => Column(
        children: [
          const _DragHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                loc.t('filterTitle'),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary(context),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.only(bottom: 8),
              children: [
                if (widget.showCategory) ...[
                  _SectionHeader(loc.t('filterCategory')),
                  _buildCategoryDropdown(loc),
                ],
                if (widget.showSubcategory)
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    child: _pending.category == null
                        ? const SizedBox.shrink()
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _SectionHeader(loc.t('filterSubcategory')),
                              _buildSubcategoryDropdown(loc),
                            ],
                          ),
                  ),
                if (widget.showExtraFields)
                  AnimatedSize(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOut,
                    child: _pending.subcategory == null
                        ? const SizedBox.shrink()
                        : _fieldsLoading
                            ? const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: kPrimary)),
                              )
                            : _fields.isEmpty
                                ? const SizedBox.shrink()
                                : Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _SectionHeader(loc.t('filterExtraFields')),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 16),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: _fields.map((f) => _buildFilterExtraField(f, loc)).toList(),
                                        ),
                                      ),
                                    ],
                                  ),
                  ),
                if (widget.showCity) ...[
                  _SectionHeader(loc.t('filterCitySection')),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: _CityTile(
                      loc: loc,
                      cities: _cities,
                      loaded: _citiesLoaded,
                      selected: _pending.city,
                      onSelect: (c) => setState(() {
                        _pending = _pending.copyWith(city: c);
                      }),
                    ),
                  ),
                ],
                if (widget.showCondition) ...[
                  _SectionHeader(loc.t('filterConditionSection')),
                  _ChipRow(
                    items: [
                      ('new', loc.t('conditionNew')),
                      ('like_new', loc.t('conditionLikeNew')),
                      ('used', loc.t('conditionUsed')),
                      ('refurbished', loc.t('conditionRefurbished')),
                      ('damaged', loc.t('conditionDamaged')),
                    ],
                    selected: _pending.condition,
                    onSelect: (v) => setState(() {
                      _pending = _pending.copyWith(
                        condition: v == _pending.condition ? null : v,
                      );
                    }),
                  ),
                ],
                if (widget.showPriceRange) ...[
                  _SectionHeader(loc.t('filterPriceRange')),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: Row(children: [
                      Expanded(
                        child: _PriceField(
                          controller: _minController,
                          hint: loc.t('filterPriceMin'),
                          onChanged: (v) => setState(() {
                            _pending = _pending.copyWith(
                              minPrice: double.tryParse(v),
                            );
                          }),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _PriceField(
                          controller: _maxController,
                          hint: loc.t('filterPriceMax'),
                          onChanged: (v) => setState(() {
                            _pending = _pending.copyWith(
                              maxPrice: double.tryParse(v),
                            );
                          }),
                        ),
                      ),
                    ]),
                  ),
                ],
                if (widget.showSort) ...[
                  _SectionHeader(loc.t('filterSortSection')),
                  _ChipRow(
                    items: [
                      ('newest', loc.t('sortNewest')),
                      ('oldest', loc.t('sortOldest')),
                      ('price_asc', loc.t('sortPriceAsc')),
                      ('price_desc', loc.t('sortPriceDesc')),
                    ],
                    selected: _pending.sortBy,
                    onSelect: (v) => setState(() {
                      _pending = _pending.copyWith(
                        sortBy: v == _pending.sortBy ? null : v,
                      );
                    }),
                  ),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
          _Footer(
            loc: loc,
            pending: _pending,
            onClear: () => setState(() => _pending = const ListingFilterState()),
            onApply: () => Navigator.of(context).pop(_pending),
          ),
        ],
      ),
    );
  }
}

// ── Shared chip widget ────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? kPrimary : AppColors.inputFill(context),
            borderRadius: BorderRadius.circular(20),
            border: selected
                ? null
                : Border.all(color: AppColors.border(context)),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: selected ? Colors.white : AppColors.textPrimary(context),
            ),
          ),
        ),
      );
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary(context),
            letterSpacing: 0.2,
          ),
        ),
      );
}

// ── Horizontal chip row ───────────────────────────────────────────────────────

class _ChipRow extends StatelessWidget {
  const _ChipRow({
    required this.items,
    required this.selected,
    required this.onSelect,
  });

  final List<(String, String)> items;
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 40,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final (value, label) = items[i];
            return _FilterChip(
              label: label,
              selected: selected == value,
              onTap: () => onSelect(value),
            );
          },
        ),
      );
}

// ── City tile + picker ────────────────────────────────────────────────────────

class _CityTile extends StatelessWidget {
  const _CityTile({
    required this.loc,
    required this.cities,
    required this.loaded,
    required this.selected,
    required this.onSelect,
  });

  final TranslationPack loc;
  final List<String> cities;
  final bool loaded;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: loaded ? () => _pick(context) : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.inputFill(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected != null ? kPrimary : AppColors.border(context),
              width: selected != null ? 1.5 : 1,
            ),
          ),
          child: Row(children: [
            Icon(
              Icons.location_on_outlined,
              size: 18,
              color: selected != null
                  ? kPrimary
                  : AppColors.iconSecondary(context),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                selected ?? loc.t('cityAll'),
                style: TextStyle(
                  fontSize: 14,
                  color: selected != null
                      ? AppColors.textPrimary(context)
                      : AppColors.textSecondary(context),
                ),
              ),
            ),
            if (selected != null)
              GestureDetector(
                onTap: () => onSelect(null),
                child: Icon(
                  Icons.close,
                  size: 16,
                  color: AppColors.textSecondary(context),
                ),
              )
            else
              Icon(
                Icons.chevron_right,
                size: 18,
                color: AppColors.iconSecondary(context),
              ),
          ]),
        ),
      );

  void _pick(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _CityPickerSheet(
        loc: loc,
        cities: cities,
        selected: selected,
        onSelect: (c) {
          Navigator.of(context).pop();
          onSelect(c);
        },
      ),
    );
  }
}

class _CityPickerSheet extends StatefulWidget {
  const _CityPickerSheet({
    required this.loc,
    required this.cities,
    required this.selected,
    required this.onSelect,
  });

  final TranslationPack loc;
  final List<String> cities;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  State<_CityPickerSheet> createState() => _CityPickerSheetState();
}

class _CityPickerSheetState extends State<_CityPickerSheet> {
  late List<String> _filtered;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filtered = widget.cities;
    _search.addListener(_onSearch);
  }

  void _onSearch() {
    final q = _search.text.toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? widget.cities
          : widget.cities.where((c) => c.toLowerCase().contains(q)).toList();
    });
  }

  @override
  void dispose() {
    _search.removeListener(_onSearch);
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(children: [
          const _DragHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.loc.t('citySelectTitle'),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary(context),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: widget.loc.t('citySearchHint'),
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true,
                fillColor: AppColors.inputFill(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _filtered.length + 1,
              itemBuilder: (_, i) {
                if (i == 0) {
                  final isAll = widget.selected == null;
                  return ListTile(
                    title: Text(
                      widget.loc.t('cityAll'),
                      style: TextStyle(
                        color: isAll ? kPrimary : AppColors.textPrimary(context),
                        fontWeight:
                            isAll ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    trailing:
                        isAll ? Icon(Icons.check, color: kPrimary, size: 18) : null,
                    onTap: () => widget.onSelect(null),
                  );
                }
                final city = _filtered[i - 1];
                final isSelected = widget.selected == city;
                return ListTile(
                  title: Text(
                    city,
                    style: TextStyle(
                      color: isSelected
                          ? kPrimary
                          : AppColors.textPrimary(context),
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  trailing: isSelected
                      ? Icon(Icons.check, color: kPrimary, size: 18)
                      : null,
                  onTap: () => widget.onSelect(city),
                );
              },
            ),
          ),
        ]),
      );
}

// ── Price field ───────────────────────────────────────────────────────────────

class _PriceField extends StatelessWidget {
  const _PriceField({
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        onChanged: onChanged,
        style: TextStyle(
          fontSize: 14,
          color: AppColors.textPrimary(context),
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 13,
          ),
          filled: true,
          fillColor: AppColors.inputFill(context),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      );
}

// ── Drag handle ───────────────────────────────────────────────────────────────

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.border(context),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}

// ── Footer ────────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  const _Footer({
    required this.loc,
    required this.pending,
    required this.onClear,
    required this.onApply,
  });

  final TranslationPack loc;
  final ListingFilterState pending;
  final VoidCallback onClear;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final count = pending.activeCount;
    final applyLabel = count > 0
        ? '${loc.t('filterApply')} ($count)'
        : loc.t('filterApply');

    return Container(
      padding: EdgeInsets.fromLTRB(
        16, 12, 16, 12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        border: Border(top: BorderSide(color: AppColors.border(context))),
      ),
      child: Row(children: [
        Expanded(
          child: OutlinedButton(
            onPressed: pending.isEmpty ? null : onClear,
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color: pending.isEmpty ? AppColors.border(context) : kPrimary,
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(
              loc.t('filterClear'),
              style: TextStyle(
                color: pending.isEmpty
                    ? AppColors.textSecondary(context)
                    : kPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: ElevatedButton(
            onPressed: onApply,
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: Text(
              applyLabel,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
