import 'viewmodels/sales_view_model.dart';
import '../../services/category_service.dart';

import 'package:cached_network_image/cached_network_image.dart';
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter/material.dart";
import "../services/localization_service.dart";
import '../ui_library/components/filters/teq_filter_bar.dart';
import '../../utils/number_formatter.dart';
import '../../config/app_colors.dart';
import '../../config/theme.dart';
import '../../config/api.dart';
import '../../ui_library/components/cards/teq_card.dart';
import 'sale_detail_screen.dart';

class SalesScreen extends ConsumerStatefulWidget {
  const SalesScreen({super.key});

  @override
  ConsumerState<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends ConsumerState<SalesScreen> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final currentState = ref.read(salesProvider).valueOrNull;
    if (currentState != null && currentState.categories == null) {
      CategoryService.getCategories(locale: Localizations.localeOf(context).languageCode).then((cats) {
        if (mounted) {
          ref.read(salesProvider.notifier).setCategories(cats);
        }
      });
    }
  }

  List<Map<String, dynamic>> _getFiltered(SalesState state) {
    var result = state.sales;
    final filter = state.filter;
    if (filter.searchQuery != null && filter.searchQuery!.isNotEmpty) {
      final q = filter.searchQuery!.toLowerCase();
      result = result.where((item) =>
        (item['item_name'] as String? ?? '').toLowerCase().contains(q)
      ).toList();
    }
    if (filter.category != null && filter.category!.isNotEmpty) {
      result = result.where((item) => 
        (item['category'] as String?) == filter.category &&
        (filter.subcategory == null || item['subcategory'] == filter.subcategory)
      ).toList();
    }
    if (filter.dateFrom != null && filter.dateTo != null) {
      final start = filter.dateFrom!;
      final end = filter.dateTo!.add(const Duration(days: 1));
      result = result.where((item) {
        final raw = item['ended_at'] as String?;
        if (raw == null) return false;
        final dt = DateTime.tryParse(raw)?.toLocal();
        return dt != null && !dt.isBefore(start) && dt.isBefore(end);
      }).toList();
    }
    return result;
  }
  String _formatDate(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(localizationProvider);
    final stateAsync = ref.watch(salesProvider);
    
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        title: Text(loc.t("settingsMySales")),
        backgroundColor: AppColors.surface(context),
        foregroundColor: AppColors.textPrimary(context),
        elevation: 0,
        centerTitle: true,
      ),
      body: stateAsync.when(
        data: (state) {
          final filtered = _getFiltered(state);
          final bool hasFilter = !state.filter.isEmpty;
          
          if (state.sales.isEmpty) {
            return Center(
              child: Text(
                loc.t("saleEmptyState"),
                style: TextStyle(
                  color: AppColors.textSecondary(context),
                  fontSize: 16,
                ),
              ),
            );
          }
          
          return Column(
            children: [
              TeqFilterBar(
                filter: state.filter,
                onChanged: (f) => ref.read(salesProvider.notifier).updateFilter(f),
                showSubcategory: false,
                showCity: false,
                showCondition: false,
                showSort: false,
                showPriceRange: false,
              ),
              if (hasFilter && filtered.isEmpty)
                Expanded(
                  child: Center(
                    child: Text(
                      loc.t("searchNoResults"),
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 15,
                      ),
                    ),
                  ),
                )
              else
                Expanded(
                  child: RefreshIndicator(
                    color: kPrimary,
                    onRefresh: () => ref.read(salesProvider.notifier).reload(),
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final item = filtered[index];
                        final itemName =
                            item['item_name'] as String? ??
                            loc.t("purchaseUnknownItem");
                        final price =
                            (item['final_price'] as num?)?.toDouble() ?? 0.0;
                        final buyer =
                            item['buyer_username'] as String? ??
                            loc.t("saleUnknownBuyer");
                        final category = item['category'] as String?;
                        final thumbnailUrl =
                            item['thumbnail_url'] as String? ??
                            item['image_url'] as String?;
                        final isBuyItNow =
                            (item['is_bought_it_now'] as bool?) ?? false;
                        final endedAt = item['ended_at'] as String?;

                        return TeqCard(
                          color: AppColors.card(context),
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => SaleDetailScreen(sale: item),
                              ),
                            );
                          },
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child:
                                    thumbnailUrl != null &&
                                        thumbnailUrl.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: imgUrl(thumbnailUrl),
                                        width: 72,
                                        height: 72,
                                        fit: BoxFit.cover,
                                        errorWidget: (_, _, _) =>
                                            _placeholderBox(),
                                        placeholder: (_, _) =>
                                            _placeholderBox(),
                                      )
                                    : _placeholderBox(),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      itemName,
                                      style: TextStyle(
                                        color: AppColors.textPrimary(context),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '@$buyer',
                                      style: TextStyle(
                                        color: AppColors.textSecondary(
                                          context,
                                        ),
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        if (category != null) ...[
                                          Container(
                                            padding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 2,
                                                ),
                                            decoration: BoxDecoration(
                                              color: kPrimary.withValues(
                                                alpha: 0.12,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              state.categories?.firstWhere(
                                                (p) => p.$1 == category,
                                                orElse: () => (category, category),
                                              ).$2 ?? category,
                                              style: const TextStyle(
                                                color: kPrimary,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                        ],
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isBuyItNow
                                                ? const Color(
                                                    0xFF16A34A,
                                                  ).withValues(alpha: 0.12)
                                                : const Color(
                                                    0xFFF97316,
                                                  ).withValues(alpha: 0.12),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            isBuyItNow
                                                ? loc.t("saleTypeBuyNow")
                                                : loc.t("saleTypeBid"),
                                            style: TextStyle(
                                              color: isBuyItNow
                                                  ? const Color(0xFF16A34A)
                                                  : const Color(0xFFF97316),
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (endedAt != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        _formatDate(endedAt),
                                        style: TextStyle(
                                          color: AppColors.textTertiary(
                                            context,
                                          ),
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    TeqNumberFormatter.format(price, fieldKey: 'price', unit: '₺'),
                                    style: const TextStyle(
                                      color: Color(0xFF4ADE80),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Icon(
                                    Icons.chevron_right,
                                    color: AppColors.iconSecondary(context),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: kPrimary)),
        error: (e, st) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(loc.t("saleLoadError"), style: const TextStyle(color: Color(0xFFEF4444))),
                TextButton(onPressed: () => ref.read(salesProvider.notifier).reload(), child: Text(loc.t("btnRetry"))),
              ],
            )
          );
        },
      ),
    );
  }
  Widget _placeholderBox() {
    return Container(
      width: 72,
      height: 72,
      color: AppColors.card(context).withValues(alpha: 0.5),
      child: Icon(
        Icons.storefront_outlined,
        color: AppColors.iconSecondary(context),
        size: 32,
      ),
    );
  }
}
