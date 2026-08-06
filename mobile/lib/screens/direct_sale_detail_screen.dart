import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/api.dart';
import '../config/app_colors.dart';
import '../config/theme.dart';
import '../models/direct_sale.dart';
import '../providers/direct_sale_provider.dart';
import '../services/direct_sale_service.dart';
import '../services/localization_service.dart';
import '../utils/number_formatter.dart';

class DirectSaleDetailScreen extends ConsumerWidget {
  final int saleId;

  const DirectSaleDetailScreen({super.key, required this.saleId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(localizationProvider);
    final asyncSummary = ref.watch(directSaleDetailProvider(saleId));

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        title: Text(loc.t('saleTypeDirect')),
        backgroundColor: AppColors.surface(context),
        foregroundColor: AppColors.textPrimary(context),
        elevation: 0,
        centerTitle: true,
      ),
      body: asyncSummary.when(
        data: (summary) => _Body(summary: summary, loc: loc),
        loading: () => const Center(child: CircularProgressIndicator(color: kPrimary)),
        error: (_, _) => Center(
          child: Text(
            loc.t('purchaseLoadError'),
            style: const TextStyle(color: Color(0xFFEF4444)),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final DirectSaleSummary summary;
  final TranslationPack loc;

  const _Body({required this.summary, required this.loc});

  String _formatDate(DateTime? dt) {
    if (dt == null) return '';
    final local = dt.toLocal();
    return '${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')}.${local.year}';
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'ended':
        return loc.t('directSaleOrderCompleted');
      case 'cancelled':
        return loc.t('directSaleOrderCancelled');
      case 'sold_out':
        return loc.t('directSaleOrderCompleted');
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = summary.displayImageUrl;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image
          if (imageUrl != null && imageUrl.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: imgUrl(imageUrl),
                width: double.infinity,
                height: 220,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => _imagePlaceholder(context),
                placeholder: (_, _) => _imagePlaceholder(context),
              ),
            )
          else
            _imagePlaceholder(context),
          const SizedBox(height: 16),
          // Title
          Text(
            summary.itemName,
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          if (summary.endedAt != null)
            Text(
              _formatDate(summary.endedAt),
              style: TextStyle(color: AppColors.textTertiary(context), fontSize: 13),
            ),
          const SizedBox(height: 16),
          _Divider(),
          // Role-based info rows
          if (summary.isSeller) ...[
            _InfoRow(
              label: loc.t('directSaleSaleStatusLabel'),
              value: _statusLabel(summary.status),
              context: context,
            ),
            _InfoRow(
              label: loc.t('directSaleQuantityLabel'),
              value: '${summary.totalQuantitySold ?? 0}',
              context: context,
            ),
            _InfoRow(
              label: loc.t('directSaleTotalLabel'),
              value: TeqNumberFormatter.format(summary.totalRevenue ?? 0, fieldKey: 'price', unit: '₺'),
              valueColor: const Color(0xFF4ADE80),
              context: context,
            ),
            if ((summary.orderCount ?? 0) > 0) ...[
              _InfoRow(
                label: loc.t('directSaleBuyerCount').replaceFirst('{count}', '${summary.orderCount}'),
                value: '',
                context: context,
                hideDivider: true,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _showBuyersSheet(context, summary.saleId),
                  icon: const Icon(Icons.people_outline),
                  label: Text(loc.t('directSaleViewBuyersBtn')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kPrimary,
                    side: const BorderSide(color: kPrimary),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ] else ...[
            if (summary.sellerUsername != null)
              _InfoRow(
                label: '@${summary.sellerUsername}',
                value: '',
                context: context,
                hideDivider: true,
                isHeader: true,
              ),
            _InfoRow(
              label: loc.t('directSaleSaleStatusLabel'),
              value: _statusLabel(summary.status),
              context: context,
            ),
            _InfoRow(
              label: loc.t('directSaleOrderStatusLabel'),
              value: summary.buyerOrderStatus == 'completed'
                  ? loc.t('directSaleOrderCompleted')
                  : summary.buyerOrderStatus == 'cancelled'
                      ? loc.t('directSaleOrderCancelled')
                      : (summary.buyerOrderStatus ?? ''),
              context: context,
            ),
            _InfoRow(
              label: loc.t('directSaleQuantityLabel'),
              value: '${summary.buyerQuantity ?? 0}',
              context: context,
            ),
            _InfoRow(
              label: loc.t('directSaleUnitPriceLabel'),
              value: TeqNumberFormatter.format(summary.buyerUnitPrice ?? 0, fieldKey: 'price', unit: '₺'),
              context: context,
            ),
            _InfoRow(
              label: loc.t('directSaleTotalLabel'),
              value: TeqNumberFormatter.format(summary.buyerTotal ?? 0, fieldKey: 'price', unit: '₺'),
              valueColor: const Color(0xFF4ADE80),
              context: context,
            ),
          ],
        ],
      ),
    );
  }

  void _showBuyersSheet(BuildContext context, int saleId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BuyersSheet(saleId: saleId),
    );
  }

  Widget _imagePlaceholder(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 220,
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(Icons.shopping_bag_outlined, color: AppColors.iconSecondary(context), size: 64),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool hideDivider;
  final bool isHeader;
  final BuildContext context;

  const _InfoRow({
    required this.label,
    required this.value,
    required this.context,
    this.valueColor,
    this.hideDivider = false,
    this.isHeader = false,
  });

  @override
  Widget build(BuildContext _) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isHeader
                        ? AppColors.textPrimary(context)
                        : AppColors.textSecondary(context),
                    fontSize: isHeader ? 15 : 14,
                    fontWeight: isHeader ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              if (value.isNotEmpty)
                Text(
                  value,
                  style: TextStyle(
                    color: valueColor ?? AppColors.textPrimary(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
        if (!hideDivider) _Divider(),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      color: AppColors.border(context),
    );
  }
}

class _BuyersSheet extends StatefulWidget {
  final int saleId;

  const _BuyersSheet({required this.saleId});

  @override
  State<_BuyersSheet> createState() => _BuyersSheetState();
}

class _BuyersSheetState extends State<_BuyersSheet> {
  List<DirectSaleOrder>? _orders;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    DirectSaleService.getOrders(widget.saleId).then((orders) {
      if (mounted) setState(() { _orders = orders; _loading = false; });
    }).catchError((_) {
      if (mounted) setState(() { _loading = false; });
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: AppColors.surface(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Consumer(
                      builder: (_, ref, _) {
                        final loc = ref.watch(localizationProvider);
                        return Text(
                          loc.t('directSaleOrdersTitle'),
                          style: TextStyle(
                            color: AppColors.textPrimary(context),
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      },
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: AppColors.iconSecondary(context)),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: kPrimary))
                  : _orders == null || _orders!.isEmpty
                      ? Center(
                          child: Consumer(
                            builder: (_, ref, _) {
                              final loc = ref.watch(localizationProvider);
                              return Text(
                                loc.t('searchNoResults'),
                                style: TextStyle(color: AppColors.textSecondary(context)),
                              );
                            },
                          ),
                        )
                      : ListView.separated(
                          controller: controller,
                          padding: const EdgeInsets.all(16),
                          itemCount: _orders!.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
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
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Consumer(
                                          builder: (_, ref, _) {
                                            final loc = ref.watch(localizationProvider);
                                            return Text(
                                              loc.t('directSaleOrderQuantity').replaceFirst('{count}', '${o.quantity}'),
                                              style: TextStyle(color: AppColors.textSecondary(context), fontSize: 13),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        TeqNumberFormatter.format(o.totalPrice, fieldKey: 'price', unit: '₺'),
                                        style: const TextStyle(
                                          color: Color(0xFF4ADE80),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      if (o.isCancelled)
                                        Consumer(
                                          builder: (_, ref, _) {
                                            final loc = ref.watch(localizationProvider);
                                            return Text(
                                              loc.t('directSaleOrderCancelled'),
                                              style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12),
                                            );
                                          },
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
