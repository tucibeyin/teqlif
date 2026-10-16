import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../config/theme.dart';
import '../../models/recording.dart';
import '../../services/image_cache_manager.dart';
import '../../services/localization_service.dart';
import '../public_profile_screen.dart';
import 'widgets/modal_sheet.dart';
import 'widgets/price_curve_painter.dart';

enum _AuctionSort { newest, highPrice, lowPrice, mostBids }

class AuctionsTab extends StatefulWidget {
  final List<RecordingAuction> auctions;
  final double? durationSecs;
  final TranslationPack loc;

  const AuctionsTab({
    super.key,
    required this.auctions,
    required this.loc,
    this.durationSecs,
  });

  @override
  State<AuctionsTab> createState() => _AuctionsTabState();
}

class _AuctionsTabState extends State<AuctionsTab> {
  _AuctionSort _sort = _AuctionSort.newest;

  List<RecordingAuction> get _sorted {
    final list = [...widget.auctions];
    switch (_sort) {
      case _AuctionSort.highPrice:
        list.sort((a, b) => (b.finalPrice ?? 0).compareTo(a.finalPrice ?? 0));
      case _AuctionSort.lowPrice:
        list.sort((a, b) => (a.finalPrice ?? 0).compareTo(b.finalPrice ?? 0));
      case _AuctionSort.mostBids:
        list.sort((a, b) => b.bidCount.compareTo(a.bidCount));
      case _AuctionSort.newest:
        break;
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.auctions.isEmpty) {
      return Center(
        child: Text(
          widget.loc.t('recordingDetailAuctions'),
          style: TextStyle(color: AppColors.textSecondary(context)),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _SortHeader<_AuctionSort>(
          title: '${widget.loc.t("recordingDetailAuctions")} (${widget.auctions.length})',
          current: _sort,
          options: [
            (_AuctionSort.newest,    widget.loc.t('recordingSortNewest')),
            (_AuctionSort.highPrice, widget.loc.t('recordingSortHighLow')),
            (_AuctionSort.lowPrice,  widget.loc.t('recordingSortLowHigh')),
            (_AuctionSort.mostBids,  widget.loc.t('recordingSortMostBids')),
          ],
          onChanged: (v) => setState(() => _sort = v),
        ),
        const SizedBox(height: 12),
        ..._sorted.map((a) => _AuctionCard(
              auction: a,
              loc: widget.loc,
              durationSecs: widget.durationSecs,
            )),
      ],
    );
  }
}

class _AuctionCard extends StatelessWidget {
  final RecordingAuction auction;
  final TranslationPack loc;
  final double? durationSecs;

  const _AuctionCard({
    required this.auction,
    required this.loc,
    this.durationSecs,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _AuctionModal(auction: auction, loc: loc),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _itemIcon(context),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        auction.itemName,
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
                          if (auction.sold && auction.finalPrice != null)
                            _PriceLabel(auction: auction)
                          else
                            Text(
                              loc.t('auctionNotSold'),
                              style: TextStyle(
                                color: AppColors.textSecondary(context),
                                fontSize: 13,
                              ),
                            ),
                          const SizedBox(width: 8),
                          Text(
                            loc.t('auctionBidCount')
                                .replaceAll('{count}', '${auction.bidCount}'),
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textTertiary(context),
                            ),
                          ),
                          if (auction.durationMinutes != null) ...[
                            const SizedBox(width: 6),
                            Text(
                              '${auction.durationMinutes}dk',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textTertiary(context),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right,
                    color: AppColors.textTertiary(context)),
              ],
            ),
            if (auction.bids.length >= 2) ...[
              const SizedBox(height: 10),
              PriceCurvePainter(auction: auction, height: 60),
            ],
          ],
        ),
      ),
    );
  }

  Widget _itemIcon(BuildContext context) {
    if (auction.proofImageUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: CachedNetworkImage(
          imageUrl: auction.proofImageUrl!,
          cacheManager: TeqlifCacheManager(),
          memCacheWidth: 88,
          memCacheHeight: 88,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) =>
              const Icon(Icons.gavel, size: 30),
        ),
      );
    }
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: kPrimary.withAlpha(26),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(Icons.gavel, color: kPrimary, size: 22),
    );
  }
}

class _PriceLabel extends StatelessWidget {
  final RecordingAuction auction;
  const _PriceLabel({required this.auction});

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF16A34A);
    final finalStr = '₺${auction.finalPrice!.toStringAsFixed(2)}';

    if (auction.isBoughtItNow) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.flash_on, size: 13, color: green),
        const SizedBox(width: 2),
        Text(finalStr,
            style: const TextStyle(
                color: green, fontWeight: FontWeight.bold, fontSize: 13)),
      ]);
    }

    if (auction.startPrice != null && auction.startPrice! < auction.finalPrice!) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Text(
          '₺${auction.startPrice!.toStringAsFixed(0)}',
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textTertiary(context),
            decoration: TextDecoration.lineThrough,
          ),
        ),
        const SizedBox(width: 4),
        const Icon(Icons.arrow_forward, size: 11, color: green),
        const SizedBox(width: 3),
        Text(finalStr,
            style: const TextStyle(
                color: green, fontWeight: FontWeight.bold, fontSize: 13)),
      ]);
    }

    return Text(finalStr,
        style: const TextStyle(
            color: green, fontWeight: FontWeight.bold, fontSize: 13));
  }
}

class _AuctionModal extends StatelessWidget {
  final RecordingAuction auction;
  final TranslationPack loc;

  const _AuctionModal({required this.auction, required this.loc});

  @override
  Widget build(BuildContext context) {
    return RecordingModalSheet(
      title: auction.itemName,
      children: [
        if (auction.winner != null) ...[
          _WinnerRow(participant: auction.winner!),
          const SizedBox(height: 12),
        ],
        if (auction.bids.isNotEmpty) ...[
          Text(
            loc.t('detailBidsSectionTitle'),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary(context),
            ),
          ),
          const SizedBox(height: 8),
          ...auction.bids.map((b) => _BidRow(bid: b)),
        ],
      ],
    );
  }
}

class _WinnerRow extends StatelessWidget {
  final RecordingParticipant participant;
  const _WinnerRow({required this.participant});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) =>
                PublicProfileScreen(username: participant.username)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundImage: participant.avatarUrl != null
                ? CachedNetworkImageProvider(
                    participant.avatarUrl!,
                    cacheKey: 'user_${participant.userId}_avatar',
                    cacheManager: TeqlifCacheManager(),
                  )
                : null,
            child: participant.avatarUrl == null
                ? const Icon(Icons.person, size: 18)
                : null,
          ),
          const SizedBox(width: 10),
          Text(
            '@${participant.username}',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary(context),
            ),
          ),
          const Spacer(),
          Icon(Icons.emoji_events, color: kPrimary, size: 18),
        ],
      ),
    );
  }
}

class _BidRow extends StatelessWidget {
  final RecordingBid bid;
  const _BidRow({required this.bid});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => PublicProfileScreen(username: bid.username)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            CircleAvatar(
              radius: 15,
              backgroundImage: bid.avatarUrl != null
                  ? CachedNetworkImageProvider(
                      bid.avatarUrl!,
                      cacheKey: 'user_${bid.userId}_avatar',
                      cacheManager: TeqlifCacheManager(),
                    )
                  : null,
              child: bid.avatarUrl == null
                  ? const Icon(Icons.person, size: 15)
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '@${bid.username}',
                style: TextStyle(color: AppColors.textPrimary(context)),
              ),
            ),
            Text(
              '₺${bid.amount.toStringAsFixed(2)}',
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
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
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary(context),
          ),
        ),
        const Spacer(),
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
                      fontSize: 12,
                      color: AppColors.textTertiary(context)),
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
