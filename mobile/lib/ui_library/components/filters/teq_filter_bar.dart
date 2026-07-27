import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../config/app_colors.dart';
import '../../../models/listing_filter_state.dart';
import '../../../services/localization_service.dart';
import '../../foundation/teq_colors.dart';
import '../buttons/teq_button.dart';
import 'teq_filter_sheet.dart';

class TeqFilterBar extends ConsumerStatefulWidget {
  const TeqFilterBar({
    super.key,
    required this.filter,
    required this.onChanged,
    this.showSearchBar = true,
    this.showDateRange = true,
    this.showCategory = true,
    this.showSubcategory = true,
    this.showExtraFields = true,
    this.showCity = true,
    this.showCondition = true,
    this.showSort = true,
    this.showPriceRange = true,
    this.searchHint,
  });

  final ListingFilterState filter;
  final ValueChanged<ListingFilterState> onChanged;

  final bool showSearchBar;
  final bool showDateRange;
  final bool showCategory;
  final bool showSubcategory;
  final bool showExtraFields;
  final bool showCity;
  final bool showCondition;
  final bool showSort;
  final bool showPriceRange;
  final String? searchHint;

  @override
  ConsumerState<TeqFilterBar> createState() => _TeqFilterBarState();
}

class _TeqFilterBarState extends ConsumerState<TeqFilterBar> {
  bool _isExpanded = false;
  late TextEditingController _searchCtrl;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController(text: widget.filter.searchQuery ?? '');
  }

  @override
  void didUpdateWidget(covariant TeqFilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.filter.searchQuery != oldWidget.filter.searchQuery &&
        widget.filter.searchQuery != _searchCtrl.text) {
      _searchCtrl.text = widget.filter.searchQuery ?? '';
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      final trimmed = text.trim();
      widget.onChanged(
        widget.filter.copyWith(searchQuery: trimmed.isEmpty ? null : trimmed),
      );
    });
  }

  Future<void> _selectDateRange(TranslationPack loc) async {
    final now = DateTime.now();
    final initialStart = widget.filter.dateFrom ?? now.subtract(const Duration(days: 30));
    final initialEnd = widget.filter.dateTo ?? now;

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now.add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: initialStart, end: initialEnd),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.light(
            primary: TeqColors.primary,
            onPrimary: Colors.white,
            surface: AppColors.surface(context),
            onSurface: AppColors.textPrimary(context),
          ),
        ),
        child: child!,
      ),
    );

    if (picked != null) {
      widget.onChanged(widget.filter.copyWith(dateFrom: picked.start, dateTo: picked.end));
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(localizationProvider);
    final count = widget.filter.activeCount;
    final hasFilter = !widget.filter.isEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. En Üst: Arama Barı (Her zaman görünür)
          if (widget.showSearchBar) ...[
            TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              style: TextStyle(color: AppColors.textPrimary(context), fontSize: 14),
              decoration: InputDecoration(
                hintText: widget.searchHint ?? loc.tOr('searchHint', 'İlan başlığı veya açıklamalarda ara...'),
                hintStyle: TextStyle(color: AppColors.textSecondary(context), fontSize: 13),
                prefixIcon: Icon(Icons.search_rounded, size: 20, color: AppColors.iconColor(context)),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear_rounded, size: 18, color: AppColors.iconColor(context)),
                        onPressed: () {
                          _searchCtrl.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppColors.inputFill(context),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.border(context)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.border(context)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: TeqColors.primary, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],

          // 2. Alt Satır: Ana Filtre Butonu ve Temizle Butonu
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _isExpanded = !_isExpanded),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: hasFilter ? TeqColors.primary : AppColors.inputFill(context),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: hasFilter
                          ? [
                              BoxShadow(
                                color: TeqColors.primary.withValues(alpha: 0.25),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              )
                            ]
                          : null,
                      border: hasFilter
                          ? null
                          : Border.all(color: AppColors.border(context)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.tune_rounded,
                              size: 20,
                              color: hasFilter ? Colors.white : AppColors.iconColor(context),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              count > 0
                                  ? '${loc.tOr('filterButton', 'Filtreler')} ($count)'
                                  : loc.tOr('filterButton', 'Filtreler'),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: hasFilter ? Colors.white : AppColors.textPrimary(context),
                              ),
                            ),
                          ],
                        ),
                        Icon(
                          _isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                          size: 22,
                          color: hasFilter ? Colors.white : AppColors.iconColor(context),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (hasFilter) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    _searchCtrl.clear();
                    widget.onChanged(const ListingFilterState());
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.inputFill(context),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border(context)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.close_rounded, size: 18, color: AppColors.iconColor(context)),
                        const SizedBox(width: 4),
                        Text(
                          loc.tOr('filterClear', 'Temizle'),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),

          // 3. Açılır / Kapanır (Expand/Collapse) Alanlar
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: _isExpanded
                ? Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Tarih Aralığı Seçimi
                        if (widget.showDateRange) ...[
                          GestureDetector(
                            onTap: () => _selectDateRange(loc),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: AppColors.inputFill(context),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.border(context)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.calendar_today_rounded, size: 18, color: TeqColors.primary),
                                      const SizedBox(width: 8),
                                      Text(
                                        widget.filter.dateFrom != null && widget.filter.dateTo != null
                                            ? '${DateFormat('yyyy-MM-dd').format(widget.filter.dateFrom!)} — ${DateFormat('yyyy-MM-dd').format(widget.filter.dateTo!)}'
                                            : loc.tOr('filterSelectDateRange', 'Tarih Aralığı Seç'),
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: widget.filter.dateFrom != null
                                              ? AppColors.textPrimary(context)
                                              : AppColors.textSecondary(context),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (widget.filter.dateFrom != null || widget.filter.dateTo != null)
                                    GestureDetector(
                                      onTap: () => widget.onChanged(
                                        widget.filter.copyWith(dateFrom: null, dateTo: null),
                                      ),
                                      child: Icon(Icons.close_rounded, size: 18, color: AppColors.iconColor(context)),
                                    )
                                  else
                                    Icon(Icons.arrow_drop_down_rounded, size: 22, color: AppColors.iconColor(context)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        // Filtre Ekle (Başta) & Tümünü Kaldır Butonları
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: TeqButton(
                                text: loc.tOr('filterAdd', '+ Filtre Ekle'),
                                onPressed: () async {
                                  final result = await TeqFilterSheet.show(
                                    context,
                                    initial: widget.filter,
                                    showCategory: widget.showCategory,
                                    showSubcategory: widget.showSubcategory,
                                    showExtraFields: widget.showExtraFields,
                                    showCity: widget.showCity,
                                    showCondition: widget.showCondition,
                                    showSort: widget.showSort,
                                    showPriceRange: widget.showPriceRange,
                                  );
                                  if (result != null) {
                                    widget.onChanged(result);
                                  }
                                },
                                size: TeqButtonSize.medium,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TeqButton.outline(
                                text: loc.tOr('filterClearAll', 'Temizle'),
                                onPressed: hasFilter
                                    ? () {
                                        _searchCtrl.clear();
                                        widget.onChanged(const ListingFilterState());
                                        setState(() => _isExpanded = false);
                                      }
                                    : null,
                                size: TeqButtonSize.medium,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
