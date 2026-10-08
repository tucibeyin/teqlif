import 'package:cached_network_image/cached_network_image.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../config/app_colors.dart';
import '../config/theme.dart';
import '../models/recording.dart';
import '../services/localization_service.dart';
import 'public_profile_screen.dart';
import 'viewmodels/recording_detail_view_model.dart';

class RecordingDetailScreen extends ConsumerStatefulWidget {
  final int streamId;
  const RecordingDetailScreen({super.key, required this.streamId});

  @override
  ConsumerState<RecordingDetailScreen> createState() =>
      _RecordingDetailScreenState();
}

class _RecordingDetailScreenState
    extends ConsumerState<RecordingDetailScreen> {
  VideoPlayerController? _vpCtrl;
  ChewieController? _chewieCtrl;
  bool _playerInitialized = false;
  String? _currentUrl;

  @override
  void dispose() {
    _chewieCtrl?.dispose();
    _vpCtrl?.dispose();
    super.dispose();
  }

  void _initPlayer(String url) {
    if (_currentUrl == url) return;
    _currentUrl = url;
    _chewieCtrl?.dispose();
    _vpCtrl?.dispose();
    _vpCtrl = VideoPlayerController.networkUrl(Uri.parse(url));
    _vpCtrl!.initialize().then((_) {
      if (!mounted) return;
      _chewieCtrl = ChewieController(
        videoPlayerController: _vpCtrl!,
        autoPlay: false,
        looping: false,
        allowFullScreen: true,
        allowMuting: true,
        showControls: true,
        aspectRatio: 16 / 9,
      );
      setState(() => _playerInitialized = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(localizationProvider);
    final stateAsync =
        ref.watch(recordingDetailProvider(widget.streamId));

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        backgroundColor: AppColors.surface(context),
        foregroundColor: AppColors.textPrimary(context),
        elevation: 0,
        title: Text(
          loc.tOr('recordingDetailTitle', 'Kayıt Detayı'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: stateAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(e.toString(),
              style: TextStyle(color: AppColors.textSecondary(context))),
        ),
        data: (s) => _buildBody(context, s, loc),
      ),
    );
  }

  Widget _buildBody(
      BuildContext context, RecordingDetailState s, TranslationPack loc) {
    // Kick off summary fetch on first data render
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(recordingDetailProvider(widget.streamId).notifier).fetchSummary();
      }
    });

    // Init or recover player
    if (s.urlError != null && s.urlError == 'RECORDING_EXPIRED') {
      return _ErrorState(
        message: loc.t('errorRecordingExpired'),
        icon: Icons.lock_outline,
      );
    }
    if (s.urlData != null) {
      _initPlayer(s.urlData!.url);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Video player ──────────────────────────────────────────────
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              color: Colors.black,
              child: s.urlData == null
                  ? _playerError(s.urlError, loc)
                  : _playerInitialized && _chewieCtrl != null
                      ? Chewie(controller: _chewieCtrl!)
                      : const Center(
                          child: CircularProgressIndicator(color: Colors.white)),
            ),
          ),

          // 403 recovery banner
          if (s.urlError != null &&
              s.urlError != 'RECORDING_EXPIRED' &&
              s.urlData == null)
            _RecoveryBanner(
              streamId: widget.streamId,
              loc: loc,
            ),

          const SizedBox(height: 16),

          // ── Summary section ───────────────────────────────────────────
          if (s.summaryLoading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (s.summary != null)
            _SummarySection(detail: s.summary!, loc: loc),
        ],
      ),
    );
  }

  Widget _playerError(String? code, TranslationPack loc) {
    final msg = code == null
        ? loc.tOr('recordingLoading', 'Yükleniyor...')
        : loc.t('errorRecordingNotAvailable');
    return Center(
      child: Text(msg,
          style: const TextStyle(color: Colors.white70, fontSize: 14)),
    );
  }
}

// ── Recovery banner ───────────────────────────────────────────────────────────

class _RecoveryBanner extends ConsumerWidget {
  final int streamId;
  final TranslationPack loc;

  const _RecoveryBanner({required this.streamId, required this.loc});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.refresh, color: Colors.orange, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              loc.tOr('recordingUrlExpiredRetry', 'Bağlantı süresi doldu. Yenilemek için dokun.'),
              style: const TextStyle(color: Colors.orange, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: () => ref
                .read(recordingDetailProvider(streamId).notifier)
                .recoverUrl(),
            child: Text(loc.tOr('retry', 'Yenile'),
                style: const TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );
  }
}

// ── Summary section ───────────────────────────────────────────────────────────

class _SummarySection extends StatelessWidget {
  final RecordingDetail detail;
  final TranslationPack loc;

  const _SummarySection({required this.detail, required this.loc});

  @override
  Widget build(BuildContext context) {
    final m = detail.metrics;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Metrics row
          Row(
            children: [
              _MetricTile(
                label: loc.tOr('recordingMetricRevenue', 'Gelir'),
                value: '₺${m.totalRevenue.toStringAsFixed(2)}',
              ),
              const SizedBox(width: 8),
              _MetricTile(
                label: loc.t('recordingDetailAuctions'),
                value: '${detail.auctions.length}',
              ),
              const SizedBox(width: 8),
              _MetricTile(
                label: loc.t('recordingDetailDirectSales'),
                value: '${detail.directSales.length}',
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Auctions
          if (detail.auctions.isNotEmpty) ...[
            _SectionHeader(title: loc.t('recordingDetailAuctions')),
            const SizedBox(height: 8),
            ...detail.auctions.map((a) => _AuctionCard(auction: a, loc: loc)),
            const SizedBox(height: 16),
          ],

          // Direct Sales
          if (detail.directSales.isNotEmpty) ...[
            _SectionHeader(title: loc.t('recordingDetailDirectSales')),
            const SizedBox(height: 8),
            ...detail.directSales.map((ds) => _DirectSaleCard(sale: ds, loc: loc)),
            const SizedBox(height: 16),
          ],

          // Gifts
          if (detail.gifts.totalTeqlik > 0) ...[
            _SectionHeader(title: loc.t('recordingDetailGifts')),
            const SizedBox(height: 8),
            _GiftsCard(gifts: detail.gifts, loc: loc),
          ],
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;

  const _MetricTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border(context)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: kPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                  fontSize: 11, color: AppColors.textSecondary(context)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary(context),
      ),
    );
  }
}

// ── Auction card ──────────────────────────────────────────────────────────────

class _AuctionCard extends StatelessWidget {
  final RecordingAuction auction;
  final TranslationPack loc;

  const _AuctionCard({required this.auction, required this.loc});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showAuctionModal(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border(context)),
        ),
        child: Row(
          children: [
            if (auction.proofImageUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: CachedNetworkImage(
                  imageUrl: auction.proofImageUrl!,
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) =>
                      const Icon(Icons.gavel, size: 30),
                ),
              )
            else
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: kPrimary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(Icons.gavel, color: kPrimary, size: 22),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    auction.itemName,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary(context)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (auction.sold && auction.finalPrice != null)
                        Text(
                          '₺${auction.finalPrice!.toStringAsFixed(2)}',
                          style: const TextStyle(
                              color: Color(0xFF16A34A),
                              fontWeight: FontWeight.bold,
                              fontSize: 13),
                        )
                      else
                        Text(
                          loc.tOr('auctionNotSold', 'Satılmadı'),
                          style: TextStyle(
                              color: AppColors.textSecondary(context),
                              fontSize: 13),
                        ),
                      const SizedBox(width: 8),
                      Text(
                        '${auction.bidCount} teklif',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textTertiary(context)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: AppColors.textTertiary(context)),
          ],
        ),
      ),
    );
  }

  void _showAuctionModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AuctionModal(auction: auction),
    );
  }
}

// ── Direct sale card ──────────────────────────────────────────────────────────

class _DirectSaleCard extends StatelessWidget {
  final RecordingDirectSale sale;
  final TranslationPack loc;

  const _DirectSaleCard({required this.sale, required this.loc});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showSaleModal(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border(context)),
        ),
        child: Row(
          children: [
            if (sale.productImageUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: CachedNetworkImage(
                  imageUrl: sale.productImageUrl!,
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) =>
                      const Icon(Icons.shopping_bag, size: 30),
                ),
              )
            else
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.shopping_bag,
                    color: Color(0xFF6366F1), size: 22),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sale.title,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary(context)),
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
                              fontSize: 13),
                        ),
                      const SizedBox(width: 8),
                      Text(
                        '${sale.soldCount}/${sale.totalStock ?? "?"}',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textTertiary(context)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: AppColors.textTertiary(context)),
          ],
        ),
      ),
    );
  }

  void _showSaleModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DirectSaleModal(sale: sale),
    );
  }
}

// ── Gifts card ────────────────────────────────────────────────────────────────

class _GiftsCard extends StatelessWidget {
  final RecordingGifts gifts;
  final TranslationPack loc;

  const _GiftsCard({required this.gifts, required this.loc});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _GiftsModal(gifts: gifts),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border(context)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFF97316).withValues(alpha: 0.10),
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
                        color: AppColors.textPrimary(context)),
                  ),
                  Text(
                    '${gifts.senderCount} gönderici',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary(context)),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: AppColors.textTertiary(context)),
          ],
        ),
      ),
    );
  }
}

// ── Bottom sheet modals ───────────────────────────────────────────────────────

class _ModalSheet extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _ModalSheet({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border(context),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(title,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary(context))),
          ),
          Divider(color: AppColors.border(context), height: 1),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: children),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuctionModal extends StatelessWidget {
  final RecordingAuction auction;

  const _AuctionModal({required this.auction});

  @override
  Widget build(BuildContext context) {
    return _ModalSheet(
      title: auction.itemName,
      children: [
        if (auction.winner != null) ...[
          _ParticipantRow(participant: auction.winner!),
          const SizedBox(height: 12),
        ],
        if (auction.bids.isNotEmpty) ...[
          Text('Teklifler',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary(context))),
          const SizedBox(height: 8),
          ...auction.bids.map((b) => _BidRow(bid: b)),
        ],
      ],
    );
  }
}

class _DirectSaleModal extends StatelessWidget {
  final RecordingDirectSale sale;

  const _DirectSaleModal({required this.sale});

  @override
  Widget build(BuildContext context) {
    return _ModalSheet(
      title: sale.title,
      children: sale.orders
          .map((o) => _OrderRow(order: o))
          .toList(),
    );
  }
}

class _GiftsModal extends StatelessWidget {
  final RecordingGifts gifts;

  const _GiftsModal({required this.gifts});

  @override
  Widget build(BuildContext context) {
    return _ModalSheet(
      title: 'Hediyeler',
      children: gifts.events
          .map((e) => _GiftEventRow(event: e))
          .toList(),
    );
  }
}

// ── Row widgets ───────────────────────────────────────────────────────────────

class _ParticipantRow extends StatelessWidget {
  final RecordingParticipant participant;

  const _ParticipantRow({required this.participant});

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
                ? CachedNetworkImageProvider(participant.avatarUrl!)
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
                color: AppColors.textPrimary(context)),
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
                  ? CachedNetworkImageProvider(bid.avatarUrl!)
                  : null,
              child: bid.avatarUrl == null
                  ? const Icon(Icons.person, size: 15)
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text('@${bid.username}',
                  style: TextStyle(color: AppColors.textPrimary(context))),
            ),
            Text(
              '₺${bid.amount.toStringAsFixed(2)}',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ],
        ),
      ),
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
            builder: (_) =>
                PublicProfileScreen(username: order.username)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            CircleAvatar(
              radius: 15,
              backgroundImage: order.avatarUrl != null
                  ? CachedNetworkImageProvider(order.avatarUrl!)
                  : null,
              child: order.avatarUrl == null
                  ? const Icon(Icons.person, size: 15)
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text('@${order.username}',
                  style:
                      TextStyle(color: AppColors.textPrimary(context))),
            ),
            Text(
              '×${order.quantity}  ₺${order.unitPrice.toStringAsFixed(2)}',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ],
        ),
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
            builder: (_) =>
                PublicProfileScreen(username: event.username)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            CircleAvatar(
              radius: 15,
              backgroundImage: event.avatarUrl != null
                  ? CachedNetworkImageProvider(event.avatarUrl!)
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
                      style: TextStyle(
                          color: AppColors.textPrimary(context))),
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
                  color: Color(0xFFF97316)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Error state ───────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  final String message;
  final IconData icon;

  const _ErrorState({required this.message, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: AppColors.textTertiary(context)),
          const SizedBox(height: 12),
          Text(
            message,
            style:
                TextStyle(color: AppColors.textSecondary(context), fontSize: 15),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
