import 'viewmodels/sales_view_model.dart';
import '../../services/category_service.dart';
import '../services/direct_sale_service.dart';
import '../models/direct_sale.dart';
import '../utils/error_helper.dart';

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
                        final itemType = item['type'] as String? ?? 'auction';
                        if (itemType == 'direct') {
                          return _DirectSaleCard(item: item, loc: loc);
                        }
                        // Auction card
                        final itemName = item['item_name'] as String? ?? loc.t("purchaseUnknownItem");
                        final price = (item['total_revenue'] as num?)?.toDouble() ?? 0.0;
                        final buyer = item['buyer_username'] as String? ?? loc.t("saleUnknownBuyer");
                        final category = item['category'] as String?;
                        final thumbnailUrl = item['image_url'] as String?;
                        final isBuyItNow = (item['is_bought_it_now'] as bool?) ?? false;
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
                                      '@$buyer',
                                      style: TextStyle(color: AppColors.textSecondary(context), fontSize: 13),
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
                                              color: isBuyItNow ? const Color(0xFF16A34A) : const Color(0xFFF97316),
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
                                        style: TextStyle(color: AppColors.textTertiary(context), fontSize: 11),
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

// ── Direkt Satış Kartı ────────────────────────────────────────────────────────

class _DirectSaleCard extends ConsumerWidget {
  final Map<String, dynamic> item;
  final TranslationPack loc;

  const _DirectSaleCard({required this.item, required this.loc});

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
  Widget build(BuildContext context, WidgetRef ref) {
    final saleId = (item['id'] as num).toInt();
    final itemName = item['item_name'] as String? ?? '';
    final revenue = (item['total_revenue'] as num?)?.toDouble() ?? 0.0;
    final totalQty = (item['total_quantity_sold'] as num?)?.toInt() ?? 0;
    final orderCount = (item['order_count'] as num?)?.toInt() ?? 0;
    final imageUrl = item['image_url'] as String?;
    final endedAt = item['ended_at'] as String?;

    return TeqCard(
      color: AppColors.card(context),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: imageUrl != null && imageUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: imgUrl(imageUrl),
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => _placeholder(context),
                        placeholder: (_, _) => _placeholder(context),
                      )
                    : _placeholder(context),
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
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            loc.t('saleTypeDirect'),
                            style: const TextStyle(color: Color(0xFF6366F1), fontSize: 11),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _formatDate(endedAt),
                          style: TextStyle(color: AppColors.textTertiary(context), fontSize: 11),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${loc.t('directSaleOrderQuantity', {'count': totalQty.toString()})} · ${loc.t('directSaleBuyerCount', {'count': orderCount.toString()})}',
                      style: TextStyle(color: AppColors.textSecondary(context), fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                TeqNumberFormatter.format(revenue, fieldKey: 'price', unit: '₺'),
                style: const TextStyle(
                  color: Color(0xFF4ADE80),
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Divider(height: 1, color: AppColors.textTertiary(context).withValues(alpha: 0.2)),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => showModalBottomSheet(
              context: context,
              backgroundColor: AppColors.surface(context),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              builder: (_) => _BuyersSheet(saleId: saleId, itemName: itemName),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  loc.t('directSaleOrdersTitle'),
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                Icon(Icons.chevron_right, color: AppColors.iconSecondary(context), size: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      color: AppColors.card(context).withValues(alpha: 0.5),
      child: Icon(Icons.sell_outlined, color: AppColors.iconSecondary(context), size: 32),
    );
  }
}

// ── Alıcılar Bottom Sheet ─────────────────────────────────────────────────────

class _BuyersSheet extends ConsumerStatefulWidget {
  final int saleId;
  final String itemName;

  const _BuyersSheet({required this.saleId, required this.itemName});

  @override
  ConsumerState<_BuyersSheet> createState() => _BuyersSheetState();
}

class _BuyersSheetState extends ConsumerState<_BuyersSheet> {
  List<DirectSaleOrder>? _orders;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final orders = await DirectSaleService.getOrders(widget.saleId);
      if (mounted) setState(() { _orders = orders; _loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() { _orders = []; _loading = false; });
        handleError(e, ref.read(localizationProvider));
      }
    }
  }

  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year.toString().substring(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(localizationProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${loc.t('directSaleOrdersTitle')} — ${widget.itemName}',
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: CircularProgressIndicator(color: kPrimary))
          else if (_orders == null || _orders!.isEmpty)
            Center(
              child: Text(
                loc.t('purchaseEmptyState'),
                style: TextStyle(color: AppColors.textSecondary(context)),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _orders!.length,
                separatorBuilder: (_, _) => Divider(
                  height: 1,
                  color: AppColors.textTertiary(context).withValues(alpha: 0.15),
                ),
                itemBuilder: (_, i) {
                  final o = _orders![i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '@${o.buyerUsername}',
                                style: TextStyle(
                                  color: AppColors.textPrimary(context),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _formatDate(o.createdAt.toLocal()),
                                style: TextStyle(color: AppColors.textTertiary(context), fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          loc.t('directSaleOrderQuantity', {'count': o.quantity.toString()}),
                          style: TextStyle(color: AppColors.textSecondary(context), fontSize: 13),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          TeqNumberFormatter.format(o.totalPrice, fieldKey: 'price', unit: '₺'),
                          style: const TextStyle(
                            color: Color(0xFF4ADE80),
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
