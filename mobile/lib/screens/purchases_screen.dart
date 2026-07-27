import 'dart:developer';

import 'package:cached_network_image/cached_network_image.dart';
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter/material.dart";
import "../services/localization_service.dart";
import '../../services/auth_service.dart';
import '../../services/category_service.dart';
import '../../utils/number_formatter.dart';
import '../../config/app_colors.dart';
import '../../config/theme.dart';
import '../../config/api.dart';
import 'purchase_detail_screen.dart';

import "../../ui_library/components/cards/teq_card.dart";
import '../../models/listing_filter_state.dart';
import '../../ui_library/components/filters/teq_filter_bar.dart';
import '../../ui_library/components/overlays/teq_snackbar.dart';

class PurchasesScreen extends ConsumerStatefulWidget {
  const PurchasesScreen({super.key});

  @override
  ConsumerState<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends ConsumerState<PurchasesScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _purchases = [];
  List<(String, String)>? _categories;
  ListingFilterState _filter = const ListingFilterState();

  List<Map<String, dynamic>> get _filteredPurchases {
    var result = _purchases;
    if (_filter.searchQuery != null && _filter.searchQuery!.isNotEmpty) {
      final q = _filter.searchQuery!.toLowerCase();
      result = result.where((item) =>
        (item['item_name'] as String? ?? '').toLowerCase().contains(q)
      ).toList();
    }
    if (_filter.category != null && _filter.category!.isNotEmpty) {
      result = result.where((item) => (item['category'] as String?) == _filter.category).toList();
    }
    if (_filter.dateFrom != null && _filter.dateTo != null) {
      final start = _filter.dateFrom!;
      final end = _filter.dateTo!.add(const Duration(days: 1));
      result = result.where((item) {
        final raw = item['ended_at'] as String?;
        if (raw == null) return false;
        final dt = DateTime.tryParse(raw)?.toLocal();
        return dt != null && !dt.isBefore(start) && dt.isBefore(end);
      }).toList();
    }
    return result;
  }

  @override
  void initState() {
    super.initState();
    _loadPurchases();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_categories == null) {
      CategoryService.getCategories(locale: Localizations.localeOf(context).languageCode)
          .then((cats) {
        if (mounted) setState(() => _categories = cats);
      });
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadPurchases() async {
    try {
      final purchases = await AuthService.getMyPurchases();
      if (mounted) {
        setState(() {
          _purchases = purchases;
          _loading = false;
        });
      }
    } catch (e, st) {
      log('Error loading purchases: $e', error: e, stackTrace: st);
      if (mounted) {
        setState(() {
          _loading = false;
        });
        final loc = ref.read(localizationProvider);
        TeqSnackBar.show(message: loc.t("purchaseLoadError"), type: TeqSnackBarType.error);
      }
    }
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
    final filtered = _filteredPurchases;
    final bool hasFilter = !_filter.isEmpty;
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        title: Text(loc.t("settingsMyPurchases")),
        backgroundColor: AppColors.surface(context),
        foregroundColor: AppColors.textPrimary(context),
        elevation: 0,
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : _purchases.isEmpty
              ? Center(
                  child: Text(
                    loc.t("purchaseEmptyState"),
                    style: TextStyle(color: AppColors.textSecondary(context), fontSize: 16),
                  ),
                )
              : Column(
                  children: [
                    TeqFilterBar(
                      filter: _filter,
                      onChanged: (f) => setState(() => _filter = f),
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
                          onRefresh: _loadPurchases,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final item = filtered[index];
                              final itemName = item['item_name'] as String? ?? loc.t("purchaseUnknownItem");
                              final price = (item['final_price'] as num?)?.toDouble() ?? 0.0;
                              final seller = item['seller_username'] as String? ?? loc.t("purchaseUnknownSeller");
                              final category = item['category'] as String?;
                              final thumbnailUrl = item['thumbnail_url'] as String? ?? item['image_url'] as String?;
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
                                                        _categories?.firstWhere(
                                                          (p) => p.$1 == category,
                                                          orElse: () => (category, category),
                                                        ).$2 ?? category,
                                                        style: const TextStyle(color: kPrimary, fontSize: 11),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 6),
                                                  ],
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: isBuyItNow
                                                          ? const Color(0xFF16A34A).withValues(alpha: 0.12)
                                                          : const Color(0xFFF97316).withValues(alpha: 0.12),
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                      isBuyItNow ? loc.t("saleTypeBuyNow") : loc.t("saleTypeBid"),
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
