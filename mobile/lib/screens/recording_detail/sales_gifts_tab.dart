import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../models/recording.dart';
import '../../services/image_cache_manager.dart';
import '../../services/localization_service.dart';
import '../public_profile_screen.dart';
import 'widgets/gift_bars_painter.dart';
import 'widgets/modal_sheet.dart';

enum _SaleSort { newest, mostSold }
enum _GiftSort { mostTeqlik, newest }

class SalesGiftsTab extends StatefulWidget {
  final List<RecordingDirectSale> directSales;
  final RecordingGifts gifts;
  final TranslationPack loc;

  const SalesGiftsTab({
    super.key,
    required this.directSales,
    required this.gifts,
    required this.loc,
  });

  @override
  State<SalesGiftsTab> createState() => _SalesGiftsTabState();
}

class _SalesGiftsTabState extends State<SalesGiftsTab> {
  _SaleSort _saleSort = _SaleSort.newest;
  _GiftSort _giftSort = _GiftSort.mostTeqlik;

  List<RecordingDirectSale> get _sortedSales {
    final list = [...widget.directSales];
    if (_saleSort == _SaleSort.mostSold) {
      list.sort((a, b) => b.soldCount.compareTo(a.soldCount));
    }
    return list;
  }

  List<RecordingGiftEvent> get _sortedGiftEvents {
    final list = [...widget.gifts.events];
    switch (_giftSort) {
      case _GiftSort.mostTeqlik:
        list.sort((a, b) => b.costTeqlik.compareTo(a.costTeqlik));
      case _GiftSort.newest:
        list.sort((a, b) {
          if (a.sentAt == null || b.sentAt == null) return 0;
          return b.sentAt!.compareTo(a.sentAt!);
        });
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final hasSales = widget.directSales.isNotEmpty;
    final hasGifts = widget.gifts.events.isNotEmpty;

    if (!hasSales && !hasGifts) {
      return Center(
        child: Text(
          widget.loc.t('recordingDetailDirectSales'),
          style: TextStyle(color: AppColors.textSecondary(context)),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        // ── Direkt satışlar ──────────────────────────────────────────────
        if (hasSales) ...[
          _SortHeader<_SaleSort>(
            title: '${widget.loc.t("recordingDetailDirectSales")} (${widget.directSales.length})',
            current: _saleSort,
            options: [
              (_SaleSort.newest,   widget.loc.t('recordingSortNewest')),
              (_SaleSort.mostSold, widget.loc.t('recordingSortMostSold')),
            ],
            onChanged: (v) => setState(() => _saleSort = v),
          ),
          const SizedBox(height: 10),
          ..._sortedSales.map((ds) => _SaleCard(sale: ds, loc: widget.loc)),
          const SizedBox(height: 20),
        ],

        // ── Hediyeler ────────────────────────────────────────────────────
        if (hasGifts) ...[
          _SortHeader<_GiftSort>(
            title: '${widget.loc.t("recordingDetailGifts")} (${widget.gifts.senderCount} ${widget.loc.t("giftSenderCount").replaceAll("{count}", "").trim()})',
            current: _giftSort,
            options: [
              (_GiftSort.mostTeqlik, widget.loc.t('recordingSortMostGifts')),
              (_GiftSort.newest,     widget.loc.t('recordingSortNewest')),
            ],
            onChanged: (v) => setState(() => _giftSort = v),
          ),
          const SizedBox(height: 10),
          _GiftSummaryCard(gifts: widget.gifts, loc: widget.loc),
          const SizedBox(height: 12),
          Text(
            widget.loc.t('recordingGiftDistribution'),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary(context),
            ),
          ),
          const SizedBox(height: 8),
          GiftBarsChart(
            gifts: RecordingGifts(
              totalTeqlik: widget.gifts.totalTeqlik,
              totalHostShare: widget.gifts.totalHostShare,
              senderCount: widget.gifts.senderCount,
              events: _sortedGiftEvents,
            ),
          ),
          const SizedBox(height: 12),
          ..._sortedGiftEvents.map((e) => _GiftEventRow(event: e)),
        ],
      ],
    );
  }
}

class _SaleCard extends StatelessWidget {
  final RecordingDirectSale sale;
  final TranslationPack loc;

  const _SaleCard({required this.sale, required this.loc});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _SaleModal(sale: sale),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border(context)),
        ),
        child: Row(
          children: [
            _itemIcon(context),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sale.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (sale.price != null)
                        Text(
                          '₺${sale.price!.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Color(0xFF6366F1),
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      const SizedBox(width: 8),
                      Text(
                        '${sale.soldCount}/${sale.totalStock ?? "?"}',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textTertiary(context),
                        ),
                      ),
                    ],
                  ),
                  if (sale.totalStock != null && sale.totalStock! > 0) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: (sale.soldCount / sale.totalStock!).clamp(0.0, 1.0),
                        minHeight: 3,
                        backgroundColor: AppColors.border(context),
                        valueColor: const AlwaysStoppedAnimation(
                            Color(0xFF6366F1)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: AppColors.textTertiary(context)),
          ],
        ),
      ),
    );
  }

  Widget _itemIcon(BuildContext context) {
    if (sale.productImageUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: CachedNetworkImage(
          imageUrl: sale.productImageUrl!,
          cacheManager: TeqlifCacheManager(),
          memCacheWidth: 88,
          memCacheHeight: 88,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) =>
              const Icon(Icons.shopping_bag, size: 30),
        ),
      );
    }
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFF6366F1).withAlpha(26),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Icon(Icons.shopping_bag, color: Color(0xFF6366F1), size: 22),
    );
  }
}

class _GiftSummaryCard extends StatelessWidget {
  final RecordingGifts gifts;
  final TranslationPack loc;

  const _GiftSummaryCard({required this.gifts, required this.loc});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFF97316).withAlpha(26),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.card_giftcard,
                color: Color(0xFFF97316), size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${gifts.totalTeqlik} Teqlik',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary(context),
                  ),
                ),
                Text(
                  loc.t('giftSenderCount')
                      .replaceAll('{count}', '${gifts.senderCount}'),
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GiftEventRow extends StatelessWidget {
  final RecordingGiftEvent event;
  const _GiftEventRow({required this.event});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => PublicProfileScreen(username: event.username)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            CircleAvatar(
              radius: 15,
              backgroundImage: event.avatarUrl != null
                  ? CachedNetworkImageProvider(
                      event.avatarUrl!,
                      cacheKey: 'user_${event.userId}_avatar',
                      cacheManager: TeqlifCacheManager(),
                    )
                  : null,
              child: event.avatarUrl == null
                  ? const Icon(Icons.person, size: 15)
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('@${event.username}',
                      style:
                          TextStyle(color: AppColors.textPrimary(context))),
                  Text(event.giftName,
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary(context))),
                ],
              ),
            ),
            Text(
              '${event.costTeqlik} TQL',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Color(0xFFF97316),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SaleModal extends StatelessWidget {
  final RecordingDirectSale sale;
  const _SaleModal({required this.sale});

  @override
  Widget build(BuildContext context) {
    return RecordingModalSheet(
      title: sale.title,
      children: sale.orders
          .map((o) => _OrderRow(order: o))
          .toList(),
    );
  }
}

class _OrderRow extends StatelessWidget {
  final RecordingOrder order;
  const _OrderRow({required this.order});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => PublicProfileScreen(username: order.username)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            CircleAvatar(
              radius: 15,
              backgroundImage: order.avatarUrl != null
                  ? CachedNetworkImageProvider(
                      order.avatarUrl!,
                      cacheKey: 'user_${order.userId}_avatar',
                      cacheManager: TeqlifCacheManager(),
                    )
                  : null,
              child: order.avatarUrl == null
                  ? const Icon(Icons.person, size: 15)
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text('@${order.username}',
                  style: TextStyle(color: AppColors.textPrimary(context))),
            ),
            Text(
              '×${order.quantity}  ₺${order.unitPrice.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _SortHeader<T> extends StatelessWidget {
  final String title;
  final T current;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  const _SortHeader({
    required this.title,
    required this.current,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary(context),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (options.length > 1)
          PopupMenuButton<T>(
            initialValue: current,
            onSelected: onChanged,
            icon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  options.firstWhere((o) => o.$1 == current).$2,
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textTertiary(context)),
                ),
                const SizedBox(width: 2),
                Icon(Icons.sort,
                    size: 16, color: AppColors.textTertiary(context)),
              ],
            ),
            itemBuilder: (_) => options
                .map((o) => PopupMenuItem(value: o.$1, child: Text(o.$2)))
                .toList(),
          ),
      ],
    );
  }
}
