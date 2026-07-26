import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_colors.dart';
import '../config/theme.dart';
import '../models/listing_filter_state.dart';
import '../services/localization_service.dart';
import 'listing_filter_sheet.dart';

class ListingFilterBar extends ConsumerWidget {
  const ListingFilterBar({
    super.key,
    required this.filter,
    required this.onChanged,
    this.showSearchBar = false,
    this.showCategory = true,
    this.showSubcategory = true,
    this.showExtraFields = false,
    this.showCity = true,
    this.showCondition = true,
    this.showSort = true,
    this.showPriceRange = true,
    this.searchQuery = '',
    this.searchHint,
    this.onSearchChanged,
  });

  final ListingFilterState filter;
  final ValueChanged<ListingFilterState> onChanged;

  // Search bar (optional)
  final bool showSearchBar;
  final String searchQuery;
  final String? searchHint;
  final ValueChanged<String>? onSearchChanged;

  // Feature flags forwarded to the sheet
  final bool showCategory;
  final bool showSubcategory;
  final bool showExtraFields;
  final bool showCity;
  final bool showCondition;
  final bool showSort;
  final bool showPriceRange;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(localizationProvider);
    final count = filter.activeCount;
    final hasFilter = !filter.isEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(children: [
        if (showSearchBar) ...[
          Expanded(
            child: TextField(
              onChanged: onSearchChanged,
              decoration: InputDecoration(
                hintText: searchHint ?? loc.t('searchHint'),
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
          const SizedBox(width: 8),
        ],
        GestureDetector(
          onTap: () async {
            final result = await ListingFilterSheet.show(
              context,
              initial: filter,
              showCategory: showCategory,
              showSubcategory: showSubcategory,
              showExtraFields: showExtraFields,
              showCity: showCity,
              showCondition: showCondition,
              showSort: showSort,
              showPriceRange: showPriceRange,
            );
            if (result != null) onChanged(result);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: hasFilter ? kPrimary : AppColors.inputFill(context),
              borderRadius: BorderRadius.circular(10),
              border: hasFilter
                  ? null
                  : Border.all(color: AppColors.border(context)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                Icons.tune_rounded,
                size: 18,
                color: hasFilter
                    ? Colors.white
                    : AppColors.iconColor(context),
              ),
              const SizedBox(width: 6),
              Text(
                count > 0
                    ? '${loc.t('filterButton')} ($count)'
                    : loc.t('filterButton'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: hasFilter
                      ? Colors.white
                      : AppColors.textPrimary(context),
                ),
              ),
            ]),
          ),
        ),
        if (hasFilter) ...[
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => onChanged(const ListingFilterState()),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.inputFill(context),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border(context)),
              ),
              child: Icon(
                Icons.close_rounded,
                size: 18,
                color: AppColors.iconColor(context),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}
