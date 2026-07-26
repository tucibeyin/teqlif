import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_colors.dart';
import '../config/theme.dart';
import '../models/catalog.dart';
import '../models/listing_filter_state.dart';
import '../services/catalog_service.dart';
import '../services/city_service.dart';
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
    bool showExtraFields = false,
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
  }

  @override
  void dispose() {
    _minController.dispose();
    _maxController.dispose();
    super.dispose();
  }

  void _setCategory(String? key) => setState(() {
        _pending = _pending.copyWith(
          category: key,
          subcategory: null,
          extraFields: {},
        );
      });

  void _setSubcategory(String? key) => setState(() {
        _pending = _pending.copyWith(subcategory: key, extraFields: {});
      });

  void _setExtraField(String fieldKey, dynamic value) {
    final fields = Map<String, dynamic>.from(_pending.extraFields);
    if (value == null) {
      fields.remove(fieldKey);
    } else {
      fields[fieldKey] = value;
    }
    setState(() => _pending = _pending.copyWith(extraFields: fields));
  }

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
                  _CategoryStrip(
                    loc: loc,
                    selected: _pending.category,
                    onSelect: _setCategory,
                  ),
                ],
                if (widget.showSubcategory && _pending.category != null)
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    child: _SubcategoryStrip(
                      loc: loc,
                      categoryKey: _pending.category!,
                      selected: _pending.subcategory,
                      onSelect: _setSubcategory,
                    ),
                  ),
                if (widget.showExtraFields && _pending.subcategory != null)
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    child: _ExtraFieldsSection(
                      loc: loc,
                      subcategoryKey: _pending.subcategory!,
                      extraFields: _pending.extraFields,
                      onSet: _setExtraField,
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

// ── Category strip ────────────────────────────────────────────────────────────

class _CategoryStrip extends StatelessWidget {
  const _CategoryStrip({
    required this.loc,
    required this.selected,
    required this.onSelect,
  });

  final TranslationPack loc;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final categories = CatalogService.isReady
        ? CatalogService.categories
        : kSubcategories.keys
            .map((k) => CatalogCategory(key: k, subcategories: const []))
            .toList();

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final cat = categories[i];
          final isSelected = selected == cat.key;
          return _FilterChip(
            label: loc.t(cat.labelKey),
            selected: isSelected,
            onTap: () => onSelect(isSelected ? null : cat.key),
          );
        },
      ),
    );
  }
}

// ── Subcategory strip ─────────────────────────────────────────────────────────

class _SubcategoryStrip extends StatelessWidget {
  const _SubcategoryStrip({
    required this.loc,
    required this.categoryKey,
    required this.selected,
    required this.onSelect,
  });

  final TranslationPack loc;
  final String categoryKey;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final subcats = CatalogService.subcategoriesFor(categoryKey);
    if (subcats.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(loc.t('filterSubcategory')),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: subcats.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final (key, labelKey) = subcats[i];
              final isSelected = selected == key;
              return _FilterChip(
                label: loc.t(labelKey),
                selected: isSelected,
                onTap: () => onSelect(isSelected ? null : key),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Extra fields (dropdown only, no dependsOn) ────────────────────────────────

class _ExtraFieldsSection extends StatelessWidget {
  const _ExtraFieldsSection({
    required this.loc,
    required this.subcategoryKey,
    required this.extraFields,
    required this.onSet,
  });

  final TranslationPack loc;
  final String subcategoryKey;
  final Map<String, dynamic> extraFields;
  final void Function(String key, dynamic value) onSet;

  @override
  Widget build(BuildContext context) {
    final fields = CatalogService.fieldsFor(subcategoryKey);
    if (fields == null || fields.isEmpty) return const SizedBox.shrink();

    final filterable = fields
        .where((f) =>
            f.type == 'dropdown' &&
            f.dependsOn == null &&
            f.topLevelOptions.isNotEmpty)
        .toList();
    if (filterable.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(loc.t('filterExtraFields')),
        for (final field in filterable) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text(
              loc.t(field.labelKey),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary(context),
              ),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: field.topLevelOptions.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final (value, labelKey) = field.topLevelOptions[i];
                final isSelected = extraFields[field.key] == value;
                return _FilterChip(
                  label: loc.t(labelKey),
                  selected: isSelected,
                  onTap: () => onSet(field.key, isSelected ? null : value),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
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
