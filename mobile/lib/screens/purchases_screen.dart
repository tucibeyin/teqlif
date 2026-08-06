import 'viewmodels/purchases_view_model.dart';

import 'package:cached_network_image/cached_network_image.dart';
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter/material.dart";
import "../services/localization_service.dart";
import '../../services/category_service.dart';
import '../../utils/number_formatter.dart';
import '../../config/app_colors.dart';
import '../../config/theme.dart';
import '../../config/api.dart';
import 'purchase_detail_screen.dart';

import "../../ui_library/components/cards/teq_card.dart";
import '../../ui_library/components/filters/teq_filter_bar.dart';

class _TypeBadge extends StatelessWidget {
  final String itemType;
  final bool isBuyItNow;
  final TranslationPack loc;

  const _TypeBadge({
    required this.itemType,
    required this.isBuyItNow,
    required this.loc,
  });

  @override
  Widget build(BuildContext context) {
    final (label, color) = itemType == 'direct'
        ? (loc.t('saleTypeDirect'), const Color(0xFF6366F1))
        : isBuyItNow
            ? (loc.t('saleTypeBuyNow'), const Color(0xFF16A34A))
            : (loc.t('saleTypeBid'), const Color(0xFFF97316));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11),
      ),
    );
  }
}

class PurchasesScreen extends ConsumerStatefulWidget {
  const PurchasesScreen({super.key});

  @override
  ConsumerState<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends ConsumerState<PurchasesScreen> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final currentState = ref.read(purchasesProvider).valueOrNull;
    if (currentState != null && currentState.categories == null) {
      CategoryService.getCategories(locale: Localizations.localeOf(context).languageCode).then((cats) {
        if (mounted) {
          ref.read(purchasesProvider.notifier).setCategories(cats);
        }
      });
    }
  }

  List<Map<String, dynamic>> _getFiltered(PurchasesState state) {
    var result = state.purchases;
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
    final stateAsync = ref.watch(purchasesProvider);
    
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        title: Text(loc.t("settingsMyPurchases")),
        backgroundColor: AppColors.surface(context),
        foregroundColor: AppColors.textPrimary(context),
        elevation: 0,
        centerTitle: true,
      ),
      body: stateAsync.when(
        data: (state) {
          final filtered = _getFiltered(state);
          final bool hasFilter = !state.filter.isEmpty;
          
          if (state.purchases.isEmpty) {
            return Center(
              child: Text(
                loc.t("purchaseEmptyState"),
                style: TextStyle(color: AppColors.textSecondary(context), fontSize: 16),
              ),
            );
          }
          
          return Column(
            children: [
              TeqFilterBar(
                filter: state.filter,
                onChanged: (f) => ref.read(purchasesProvider.notifier).updateFilter(f),
                showSubcategory: false,
                showCity: false,
                showCondition: false,
                showSort: false,
                showPriceRange: false,
              ),
              const SizedBox(height: 10),
              if (hasFilter && filtered.isEmpty)
                Expanded(
                  child: Center(
                    child: Text(loc.t("searchNoResults"),
                        style: const TextStyle(color: Color(0xFF6B7280), fontSize: 15)),
                  ),
                )
              else
                Expanded(
                  child: RefreshIndicator(
                    color: kPrimary,
                    onRefresh: () => ref.read(purchasesProvider.notifier).reload(),
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final item = filtered[index];
                        final itemName = item['item_name'] as String? ?? loc.t("purchaseUnknownItem");
                        final price = (item['final_price'] as num?)?.toDouble() ?? 0.0;
                        final seller = item['seller_username'] as String? ?? loc.t("purchaseUnknownSeller");
                        final category = item['category'] as String?;
                        final thumbnailUrl = item['image_url'] as String?;
                        final itemType = item['type'] as String? ?? 'auction';
                        final isBuyItNow = (item['is_bought_it_now'] as bool?) ?? false;
                        final endedAt = item['ended_at'] as String?;

                        return TeqCard(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: EdgeInsets.zero,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PurchaseDetailScreen(purchase: item),
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: thumbnailUrl != null && thumbnailUrl.isNotEmpty
                                        ? CachedNetworkImage(
                                            imageUrl: imgUrl(thumbnailUrl),
                                            width: 72,
                                            height: 72,
                                            fit: BoxFit.cover,
                                            errorWidget: (_, _, _) => _placeholderBox(),
                                            placeholder: (_, _) => _placeholderBox(),
                                          )
                                        : _placeholderBox(),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
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
                                          '@$seller',
                                          style: TextStyle(
                                            color: AppColors.textSecondary(context),
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            if (category != null) ...[
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: kPrimary.withValues(alpha: 0.12),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  CategoryService.localizedLabelFor(loc, category),
                                                  style: const TextStyle(color: kPrimary, fontSize: 11),
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                            ],
                                            _TypeBadge(
                                              itemType: itemType,
                                              isBuyItNow: isBuyItNow,
                                              loc: loc,
                                            ),
                                          ],
                                        ),
                                        if (endedAt != null) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            _formatDate(endedAt),
                                            style: TextStyle(
                                              color: AppColors.textTertiary(context),
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
                                      Icon(Icons.chevron_right, color: AppColors.iconSecondary(context)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
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
                Text(loc.t("purchaseLoadError"), style: const TextStyle(color: Color(0xFFEF4444))),
                TextButton(onPressed: () => ref.read(purchasesProvider.notifier).reload(), child: Text(loc.t("btnRetry"))),
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
      child: Icon(Icons.shopping_bag_outlined, color: AppColors.iconSecondary(context), size: 32),
    );
  }
}
