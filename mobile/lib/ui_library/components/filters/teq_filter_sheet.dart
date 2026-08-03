import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/app_colors.dart';
import '../../../models/catalog.dart';
import '../../../models/listing_filter_state.dart';
import '../../../services/catalog_service.dart';
import '../../../services/city_service.dart';
import '../../../services/field_config_service.dart';
import '../../../services/localization_service.dart';
import '../../../utils/listing_fields.dart';
import '../../foundation/teq_colors.dart';
import '../buttons/teq_button.dart';

class TeqFilterSheet extends ConsumerStatefulWidget {
  const TeqFilterSheet._({
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
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => TeqFilterSheet._(
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
  ConsumerState<TeqFilterSheet> createState() => _TeqFilterSheetState();
}

class _TeqFilterSheetState extends ConsumerState<TeqFilterSheet> {
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
    if (value == null || value == '' || (value is List && value.isEmpty)) {
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
        dropdownColor: AppColors.surface(context),
        items: [
          DropdownMenuItem<String>(
            value: null,
            child: Text(loc.tOr('filterCategoryAll', 'Tüm Kategoriler'), style: TextStyle(color: AppColors.textPrimary(context))),
          ),
          ...categories.map((c) => DropdownMenuItem(
                value: c.key,
                child: Text(loc.t(c.labelKey), style: TextStyle(color: AppColors.textPrimary(context))),
              )),
        ],
        onChanged: _setCategory,
      ),
    );
  }

  Widget _buildSubcategoryDropdown(TranslationPack loc) {
    if (_pending.category == null) return const SizedBox.shrink();
    final subcats = CatalogService.subcategoriesFor(_pending.category!);
    if (subcats.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: DropdownButtonFormField<String>(
        // ignore: deprecated_member_use
        value: _pending.subcategory,
        decoration: _fieldDecor(loc.tOr('filterSubcategoryAll', 'Tümü')),
        dropdownColor: AppColors.surface(context),
        items: [
          DropdownMenuItem<String>(
            value: null,
            child: Text(loc.tOr('filterSubcategoryAll', 'Tümü'), style: TextStyle(color: AppColors.textPrimary(context))),
          ),
          ...subcats.map((s) {
            final (key, labelKey) = s;
            return DropdownMenuItem(
              value: key,
              child: Text(loc.t(labelKey), style: TextStyle(color: AppColors.textPrimary(context))),
            );
          }),
        ],
        onChanged: _setSubcategory,
      ),
    );
  }

  Widget _buildFilterExtraField(ExtraFieldDef f, TranslationPack loc) {
    final val = _pending.extraFields[f.key];

    if (f.type == ExtraFieldType.dropdown) {
      final opts = f.options;
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          // ignore: deprecated_member_use
          value: val as String?,
          decoration: _fieldDecor(loc.t(f.labelKey)),
          dropdownColor: AppColors.surface(context),
          items: [
            DropdownMenuItem<String>(
              value: null,
              child: Text(loc.tOr('filterSubcategoryAll', 'Tümü'), style: TextStyle(color: AppColors.textPrimary(context))),
            ),
            ...opts.map((o) => DropdownMenuItem(
                  value: o.value,
                  child: Text(loc.tOr('opt_${o.value}', o.label), style: TextStyle(color: AppColors.textPrimary(context))),
                )),
          ],
          onChanged: (v) => _setExtraField(f.key, v),
        ),
      );
    }

    if (f.type == ExtraFieldType.multiselect) {
      final opts = f.options;
      final selected = (val as List?)?.cast<String>() ?? [];
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              loc.t(f.labelKey),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary(context),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: opts.map((o) {
                final isSel = selected.contains(o.value);
                return FilterChip(
                  label: Text(loc.tOr('opt_${o.value}', o.label)),
                  selected: isSel,
                  onSelected: (sel) {
                    final next = List<String>.from(selected);
                    if (sel) {
                      next.add(o.value);
                    } else {
                      next.remove(o.value);
                    }
                    _setExtraField(f.key, next.isEmpty ? null : next);
                  },
                  selectedColor: TeqColors.primary.withValues(alpha: 0.15),
                  checkmarkColor: TeqColors.primary,
                  labelStyle: TextStyle(
                    color: isSel ? TeqColors.primary : AppColors.textPrimary(context),
                    fontWeight: isSel ? FontWeight.w600 : FontWeight.normal,
                    fontSize: 13,
                  ),
                  backgroundColor: AppColors.inputFill(context),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                      color: isSel ? TeqColors.primary : AppColors.border(context),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      );
    }

    if (f.type == ExtraFieldType.number || f.type == ExtraFieldType.text) {
      final ctrl = _extraCtrls[f.key] ??= TextEditingController(text: val?.toString() ?? '');
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: ctrl,
          keyboardType: f.type == ExtraFieldType.number ? TextInputType.number : TextInputType.text,
          decoration: _fieldDecor(loc.t(f.labelKey)),
          onChanged: (v) => _setExtraField(f.key, f.type == ExtraFieldType.number ? num.tryParse(v) : v),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildCityDropdown(TranslationPack loc) {
    if (!_citiesLoaded) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: TeqColors.primary)),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: DropdownButtonFormField<String>(
        // ignore: deprecated_member_use
        value: _pending.city,
        decoration: _fieldDecor(loc.tOr('filterCityAll', 'Tüm Şehirler')),
        dropdownColor: AppColors.surface(context),
        items: [
          DropdownMenuItem<String>(
            value: null,
            child: Text(loc.tOr('filterCityAll', 'Tüm Şehirler'), style: TextStyle(color: AppColors.textPrimary(context))),
          ),
          ..._cities.map((c) => DropdownMenuItem(
                value: c,
                child: Text(c, style: TextStyle(color: AppColors.textPrimary(context))),
              )),
        ],
        onChanged: (v) => setState(() => _pending = _pending.copyWith(city: v)),
      ),
    );
  }

  InputDecoration _fieldDecor(String label) => InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AppColors.textSecondary(context), fontSize: 14),
        filled: true,
        fillColor: AppColors.inputFill(context),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.border(context)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.border(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: TeqColors.primary, width: 1.5),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(localizationProvider);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.70,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      builder: (_, controller) => Column(
        children: [
          const _DragHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                loc.tOr('filterTitle', 'Filtreler'),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary(context),
                ),
              ),
            ),
          ),
          Divider(height: 1, color: AppColors.border(context)),
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.only(bottom: 16, top: 8),
              children: [
                if (widget.showCategory) ...[
                  _SectionHeader(loc.tOr('filterCategory', 'Kategori')),
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
                              _SectionHeader(loc.tOr('filterSubcategory', 'Alt Kategori')),
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
                                child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: TeqColors.primary)),
                              )
                            : _fields.isEmpty
                                ? const SizedBox.shrink()
                                : Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _SectionHeader(loc.tOr('filterExtraFields', 'Özellikler')),
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
                  _SectionHeader(loc.tOr('filterCitySection', 'Şehir')),
                  _buildCityDropdown(loc),
                ],
                if (widget.showCondition && _pending.category != 'real_estate') ...[
                  _SectionHeader(loc.tOr('filterConditionSection', 'Durum')),
                  _ChipRow(
                    items: (_pending.category == 'vehicles')
                        ? [
                            ('new', loc.t('conditionNew')),
                            ('used', loc.t('conditionUsed')),
                          ]
                        : [
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
                  _SectionHeader(loc.tOr('filterPriceRange', 'Fiyat Aralığı')),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _minController,
                            keyboardType: TextInputType.number,
                            decoration: _fieldDecor(loc.tOr('filterPriceMin', 'En Az')),
                            onChanged: (v) {
                              final val = double.tryParse(v);
                              setState(() => _pending = _pending.copyWith(minPrice: val));
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _maxController,
                            keyboardType: TextInputType.number,
                            decoration: _fieldDecor(loc.tOr('filterPriceMax', 'En Çok')),
                            onChanged: (v) {
                              final val = double.tryParse(v);
                              setState(() => _pending = _pending.copyWith(maxPrice: val));
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (widget.showSort) ...[
                  _SectionHeader(loc.tOr('filterSortSection', 'Sıralama')),
                  _ChipRow(
                    items: [
                      ('newest', loc.tOr('sortNewest', 'En Yeni')),
                      ('oldest', loc.tOr('sortOldest', 'En Eski')),
                      ('price_asc', loc.tOr('sortPriceAsc', 'Fiyat (Artan)')),
                      ('price_desc', loc.tOr('sortPriceDesc', 'Fiyat (Azalan)')),
                    ],
                    selected: _pending.sortBy,
                    onSelect: (v) => setState(() {
                      _pending = _pending.copyWith(
                        sortBy: v == _pending.sortBy ? null : v,
                      );
                    }),
                  ),
                ],
              ],
            ),
          ),
          _Footer(
            loc: loc,
            pending: _pending,
            onClear: () {
              _minController.clear();
              _maxController.clear();
              for (final ctrl in _extraCtrls.values) {
                ctrl.clear();
              }
              setState(() => _pending = const ListingFilterState());
            },
            onApply: () => Navigator.of(context).pop(_pending),
          ),
        ],
      ),
    );
  }
}

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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary(context),
            letterSpacing: 0.3,
          ),
        ),
      );
}

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
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        child: Row(
          children: items.map((item) {
            final isSel = item.$1 == selected;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => onSelect(item.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSel ? TeqColors.primary : AppColors.inputFill(context),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSel ? TeqColors.primary : AppColors.border(context),
                    ),
                  ),
                  child: Text(
                    item.$2,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSel ? FontWeight.w600 : FontWeight.w500,
                      color: isSel ? Colors.white : AppColors.textPrimary(context),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      );
}

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
        ? '${loc.tOr('filterApply', 'Uygula')} ($count)'
        : loc.tOr('filterApply', 'Uygula');

    return Container(
      padding: EdgeInsets.fromLTRB(
        16, 12, 16, 12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
        border: Border(top: BorderSide(color: AppColors.border(context))),
      ),
      child: Row(children: [
        Expanded(
          child: TeqButton.outline(
            text: loc.tOr('filterClear', 'Temizle'),
            onPressed: pending.isEmpty ? null : onClear,
            size: TeqButtonSize.large,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: TeqButton(
            text: applyLabel,
            onPressed: onApply,
            size: TeqButtonSize.large,
          ),
        ),
      ]),
    );
  }
}
