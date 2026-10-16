import 'package:cached_network_image/cached_network_image.dart';
import '../services/image_cache_manager.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../config/app_colors.dart';
import '../config/theme.dart';
import '../core/error_mapper.dart';
import '../models/recording.dart';
import '../models/replay_event.dart';
import '../services/category_service.dart';
import '../services/localization_service.dart';
import 'public_profile_screen.dart';
import 'viewmodels/recording_detail_view_model.dart';
import '../widgets/teq_search_field.dart';

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
  bool _recovering = false;
  double _replayPosSecs = 0.0;

  @override
  void dispose() {
    _vpCtrl?.removeListener(_onPlayerTick);
    _chewieCtrl?.dispose();
    _vpCtrl?.dispose();
    super.dispose();
  }

  void _onPlayerTick() {
    if (!mounted || _vpCtrl == null) return;
    final pos = _vpCtrl!.value.position.inSeconds.toDouble();
    if ((pos - _replayPosSecs).abs() >= 1.0) {
      setState(() => _replayPosSecs = pos);
    }
  }

  void _initPlayer(String url) {
    if (_currentUrl == url) return;
    _currentUrl = url;
    _recovering = false;
    _vpCtrl?.removeListener(_onPlayerTick);
    _chewieCtrl?.dispose();
    _vpCtrl?.dispose();
    setState(() => _playerInitialized = false);
    _vpCtrl = VideoPlayerController.networkUrl(Uri.parse(url));
    _vpCtrl!.initialize().then((_) {
      if (!mounted) return;
      _vpCtrl!.addListener(_onPlayerTick);
      _chewieCtrl = ChewieController(
        videoPlayerController: _vpCtrl!,
        autoPlay: false,
        looping: false,
        allowFullScreen: true,
        allowMuting: true,
        showControls: true,
        aspectRatio: _vpCtrl!.value.aspectRatio,
      );
      setState(() => _playerInitialized = true);
    }).catchError((_) {
      if (!mounted || _recovering) return;
      _recovering = true;
      ref
          .read(recordingDetailProvider(widget.streamId).notifier)
          .recoverUrl();
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
          loc.t('recordingDetailTitle'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: stateAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(ErrorMapper.toMessage(e, loc),
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
          // ── Video player + replay overlay ─────────────────────────────
          Stack(
            children: [
              AspectRatio(
                aspectRatio: _playerInitialized && _vpCtrl != null
                    ? _vpCtrl!.value.aspectRatio
                    : 16 / 9,
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
              if (s.replayEnabled)
                Positioned(
                  left: 8,
                  bottom: 48,
                  right: 60,
                  child: IgnorePointer(
                    child: _ReplayOverlay(
                      timeline: s.timeline,
                      posSecs: _replayPosSecs,
                    ),
                  ),
                ),
            ],
          ),

          // 403 recovery banner — yalnızca geçici URL hataları için
          if (s.urlError != null &&
              s.urlError != 'RECORDING_EXPIRED' &&
              s.urlError != 'RECORDING_NOT_AVAILABLE' &&
              s.urlError != 'RECORDING_NOT_FOUND' &&
              s.urlData == null)
            _RecoveryBanner(
              streamId: widget.streamId,
              loc: loc,
            ),

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
        ? loc.t('recordingLoading')
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
              loc.t('recordingUrlExpiredRetry'),
              style: const TextStyle(color: Colors.orange, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: () => ref
                .read(recordingDetailProvider(streamId).notifier)
                .recoverUrl(),
            child: Text(loc.t('retry'),
                style: const TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );
  }
}

// ── Summary section ───────────────────────────────────────────────────────────

enum _AuctionSort { newest, highPrice, lowPrice, mostBids }
enum _SaleSort    { newest, mostSold }
enum _GiftSort    { mostTeqlik, newest }
enum _ViewerSort  { byValue, byBids, byGifts }

// ── Viewer activity (client-side aggregate) ───────────────────────────────────

class _ViewerActivity {
  final int userId;
  final String username;
  final String? avatarUrl;
  final List<_ViewerBidAction>   bids   = [];
  final List<_ViewerOrderAction> orders = [];
  final List<_ViewerGiftAction>  gifts  = [];

  _ViewerActivity({required this.userId, required this.username, this.avatarUrl});

  double get bidTotal      => bids.fold(0.0, (s, b) => s + b.amount);
  double get orderTotal    => orders.fold(0.0, (s, o) => s + o.quantity * o.unitPrice);
  int    get giftTeqlik    => gifts.fold(0, (s, g) => s + g.costTeqlik);
  double get monetaryTotal => bidTotal + orderTotal;
}

class _ViewerBidAction {
  final String auctionName;
  final double amount;
  _ViewerBidAction({required this.auctionName, required this.amount});
}

class _ViewerOrderAction {
  final String itemName;
  final int quantity;
  final double unitPrice;
  _ViewerOrderAction({required this.itemName, required this.quantity, required this.unitPrice});
}

class _ViewerGiftAction {
  final String giftName;
  final int costTeqlik;
  _ViewerGiftAction({required this.giftName, required this.costTeqlik});
}

List<_ViewerActivity> _buildViewers(RecordingDetail detail) {
  final map = <int, _ViewerActivity>{};

  for (final a in detail.auctions) {
    for (final b in a.bids) {
      (map[b.userId] ??= _ViewerActivity(userId: b.userId, username: b.username, avatarUrl: b.avatarUrl))
          .bids.add(_ViewerBidAction(auctionName: a.itemName, amount: b.amount));
    }
  }
  for (final ds in detail.directSales) {
    for (final o in ds.orders) {
      (map[o.userId] ??= _ViewerActivity(userId: o.userId, username: o.username, avatarUrl: o.avatarUrl))
          .orders.add(_ViewerOrderAction(itemName: ds.title, quantity: o.quantity, unitPrice: o.unitPrice));
    }
  }
  for (final e in detail.gifts.events) {
    (map[e.userId] ??= _ViewerActivity(userId: e.userId, username: e.username, avatarUrl: e.avatarUrl))
        .gifts.add(_ViewerGiftAction(giftName: e.giftName, costTeqlik: e.costTeqlik));
  }

  return map.values.toList()
    ..sort((a, b) => b.monetaryTotal.compareTo(a.monetaryTotal));
}

class _SummarySection extends StatefulWidget {
  final RecordingDetail detail;
  final TranslationPack loc;

  const _SummarySection({required this.detail, required this.loc});

  @override
  State<_SummarySection> createState() => _SummarySectionState();
}

class _SummarySectionState extends State<_SummarySection> {
  _AuctionSort _auctionSort   = _AuctionSort.newest;
  _SaleSort    _saleSort      = _SaleSort.newest;
  _GiftSort    _giftSort      = _GiftSort.mostTeqlik;
  _ViewerSort  _viewerSort    = _ViewerSort.byValue;
  String       _usernameQuery = '';

  List<RecordingAuction> get _sortedAuctions {
    final list = [...widget.detail.auctions];
    switch (_auctionSort) {
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

  List<RecordingDirectSale> get _sortedSales {
    final list = [...widget.detail.directSales];
    switch (_saleSort) {
      case _SaleSort.mostSold:
        list.sort((a, b) => b.soldCount.compareTo(a.soldCount));
      case _SaleSort.newest:
        break;
    }
    return list;
  }

  List<RecordingGiftEvent> get _sortedGiftEvents {
    final list = [...widget.detail.gifts.events];
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

  List<_ViewerActivity> get _sortedViewers {
    final list = _buildViewers(widget.detail);
    switch (_viewerSort) {
      case _ViewerSort.byBids:
        list.sort((a, b) => b.bidTotal.compareTo(a.bidTotal));
      case _ViewerSort.byGifts:
        list.sort((a, b) => b.giftTeqlik.compareTo(a.giftTeqlik));
      case _ViewerSort.byValue:
        break;
    }
    return list;
  }

  // ── Username filter ───────────────────────────────────────────────────────

  bool _matchesQuery(String username) =>
      _usernameQuery.isEmpty ||
      username.toLowerCase().contains(_usernameQuery.toLowerCase());

  List<RecordingAuction> get _filteredAuctions {
    if (_usernameQuery.isEmpty) return _sortedAuctions;
    return _sortedAuctions
        .where((a) =>
            a.bids.any((b) => _matchesQuery(b.username)) ||
            (a.winner != null && _matchesQuery(a.winner!.username)))
        .toList();
  }

  List<RecordingDirectSale> get _filteredSales {
    if (_usernameQuery.isEmpty) return _sortedSales;
    return _sortedSales
        .where((ds) => ds.orders.any((o) => _matchesQuery(o.username)))
        .toList();
  }

  RecordingGifts get _filteredGifts {
    final events = _sortedGiftEvents
        .where((e) => _usernameQuery.isEmpty || _matchesQuery(e.username))
        .toList();
    return RecordingGifts(
      totalTeqlik: events.fold(0, (s, e) => s + e.costTeqlik),
      totalHostShare: _usernameQuery.isEmpty
          ? widget.detail.gifts.totalHostShare
          : 0,
      senderCount: events.map((e) => e.userId).toSet().length,
      events: events,
    );
  }

  List<_ViewerActivity> get _filteredViewers {
    if (_usernameQuery.isEmpty) return _sortedViewers;
    return _sortedViewers.where((v) => _matchesQuery(v.username)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.detail.metrics;
    final s = widget.detail.stream;
    final loc = widget.loc;

    final categoryLabel = s.category != null
        ? CategoryService.localizedLabelFor(loc, s.category!)
        : null;

    final filteredAuctions = _filteredAuctions;
    final filteredSales    = _filteredSales;
    final filteredGifts    = _filteredGifts;
    final filteredViewers  = _filteredViewers;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Stream başlığı ve meta ────────────────────────────────────
          Text(
            s.title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              if (s.startedAt != null) ...[
                Icon(Icons.calendar_today_outlined,
                    size: 13, color: AppColors.textTertiary(context)),
                const SizedBox(width: 4),
                Text(
                  _formatStreamDate(s.startedAt!),
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textTertiary(context)),
                ),
              ],
              if (s.startedAt != null && s.endedAt != null) ...[
                const SizedBox(width: 12),
                Icon(Icons.timer_outlined,
                    size: 13, color: AppColors.textTertiary(context)),
                const SizedBox(width: 4),
                Text(
                  _formatStreamDuration(s.startedAt!, s.endedAt!),
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textTertiary(context)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),

          // ── Kullanıcı arama ───────────────────────────────────────────
          TeqSearchField(
            hintText: loc.t('detailUserSearchHint'),
            prefixIcon: Icons.person_search_outlined,
            onChanged: (text) => setState(() => _usernameQuery = text.trim()),
          ),
          const SizedBox(height: 12),

          // ── Kategori badge'leri ───────────────────────────────────────
          if (categoryLabel != null) ...[
            Wrap(
              spacing: 6,
              children: [
                _CategoryBadge(label: categoryLabel),
                if (s.subcategory != null)
                  _CategoryBadge(label: loc.tOr('subcat_${s.subcategory}', s.subcategory!), secondary: true),
              ],
            ),
            const SizedBox(height: 10),
          ],

          // ── Metrik kartlar ────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _MetricTile(
                label: loc.t('recordingMetricRevenue'),
                value: '₺${m.totalRevenue.toStringAsFixed(2)}',
              ),
              const SizedBox(width: 8),
              _MetricTile(
                label: loc.t('recordingMetricViewers'),
                value: s.peakViewerCount != null ? '${s.peakViewerCount}' : '—',
              ),
              const SizedBox(width: 8),
              _MetricTile(
                label: loc.t('recordingDetailAuctions'),
                value: '${widget.detail.auctions.length}',
              ),
              const SizedBox(width: 8),
              _MetricTile(
                label: loc.t('recordingDetailDirectSales'),
                value: '${widget.detail.directSales.length}',
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Açık Arttırmalar ──────────────────────────────────────────
          if (filteredAuctions.isNotEmpty) ...[
            _SectionHeaderWithSort<_AuctionSort>(
              title: loc.t('recordingDetailAuctions'),
              current: _auctionSort,
              options: [
                (_AuctionSort.newest,    loc.t('recordingSortNewest')),
                (_AuctionSort.highPrice, loc.t('recordingSortHighLow')),
                (_AuctionSort.lowPrice,  loc.t('recordingSortLowHigh')),
                (_AuctionSort.mostBids,  loc.t('recordingSortMostBids')),
              ],
              onChanged: (v) => setState(() => _auctionSort = v),
            ),
            const SizedBox(height: 8),
            ...filteredAuctions.map((a) => _AuctionCard(auction: a, loc: loc)),
            const SizedBox(height: 16),
          ],

          // ── Direkt Satışlar ───────────────────────────────────────────
          if (filteredSales.isNotEmpty) ...[
            _SectionHeaderWithSort<_SaleSort>(
              title: loc.t('recordingDetailDirectSales'),
              current: _saleSort,
              options: [
                (_SaleSort.newest,   loc.t('recordingSortNewest')),
                (_SaleSort.mostSold, loc.t('recordingSortMostSold')),
              ],
              onChanged: (v) => setState(() => _saleSort = v),
            ),
            const SizedBox(height: 8),
            ...filteredSales.map((ds) => _DirectSaleCard(sale: ds, loc: loc)),
            const SizedBox(height: 16),
          ],

          // ── Hediyeler ─────────────────────────────────────────────────
          if (filteredGifts.totalTeqlik > 0) ...[
            _SectionHeaderWithSort<_GiftSort>(
              title: loc.t('recordingDetailGifts'),
              current: _giftSort,
              options: [
                (_GiftSort.mostTeqlik, loc.t('recordingSortMostGifts')),
                (_GiftSort.newest,     loc.t('recordingSortNewest')),
              ],
              onChanged: (v) => setState(() => _giftSort = v),
            ),
            const SizedBox(height: 8),
            _GiftsCard(gifts: filteredGifts, loc: loc),
          ],

          // ── Aktif İzleyiciler ─────────────────────────────────────────
          if (filteredViewers.isNotEmpty) ...[
            const SizedBox(height: 8),
            _SectionHeaderWithSort<_ViewerSort>(
              title: '${loc.t("viewerSectionTitle")} (${filteredViewers.length})',
              current: _viewerSort,
              options: [
                (_ViewerSort.byValue, loc.t('viewerSortByValue')),
                (_ViewerSort.byBids,  loc.t('viewerSortByBids')),
                (_ViewerSort.byGifts, loc.t('viewerSortByGifts')),
              ],
              onChanged: (v) => setState(() => _viewerSort = v),
            ),
            const SizedBox(height: 8),
            ...filteredViewers.map((v) => _ViewerCard(viewer: v, loc: loc)),
          ],
        ],
      ),
    );
  }
}

String _formatStreamDate(DateTime dt) {
  final d = dt.day.toString().padLeft(2, '0');
  final mo = dt.month.toString().padLeft(2, '0');
  return '$d.$mo.${dt.year}';
}

String _formatStreamDuration(DateTime start, DateTime end) {
  final diff = end.difference(start);
  final h = diff.inHours;
  final m = diff.inMinutes % 60;
  return h > 0 ? '${h}s ${m}dk' : '${m}dk';
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
          mainAxisAlignment: MainAxisAlignment.center,
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
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeaderWithSort<T> extends StatelessWidget {
  final String title;
  final T current;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  const _SectionHeaderWithSort({
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
            fontSize: 15,
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
                  style: TextStyle(fontSize: 12, color: AppColors.textTertiary(context)),
                ),
                const SizedBox(width: 2),
                Icon(Icons.sort, size: 16, color: AppColors.textTertiary(context)),
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

class _CategoryBadge extends StatelessWidget {
  final String label;
  final bool secondary;

  const _CategoryBadge({required this.label, this.secondary = false});

  @override
  Widget build(BuildContext context) {
    final color = secondary ? AppColors.textTertiary(context) : kPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: secondary ? FontWeight.normal : FontWeight.w600,
        ),
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
                  cacheManager: TeqlifCacheManager(),
                  memCacheWidth: 88,
                  memCacheHeight: 88,
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  errorWidget: (context, url, err) =>
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
                        _AuctionPriceLabel(auction: auction, context: context)
                      else
                        Text(
                          loc.t('auctionNotSold'),
                          style: TextStyle(
                              color: AppColors.textSecondary(context),
                              fontSize: 13),
                        ),
                      const SizedBox(width: 8),
                      Text(
                        loc.t('auctionBidCount').replaceAll('{count}', '${auction.bidCount}'),
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textTertiary(context)),
                      ),
                      if (auction.durationMinutes != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          '${auction.durationMinutes}dk',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textTertiary(context)),
                        ),
                      ],
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
      builder: (_) => _AuctionModal(auction: auction, loc: loc),
    );
  }
}

class _AuctionPriceLabel extends StatelessWidget {
  final RecordingAuction auction;
  final BuildContext context;

  const _AuctionPriceLabel({required this.auction, required this.context});

  @override
  Widget build(BuildContext ctx) {
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

    if (auction.startPrice != null &&
        auction.startPrice! < auction.finalPrice!) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Text(
          '₺${auction.startPrice!.toStringAsFixed(0)}',
          style: TextStyle(
              fontSize: 11,
              color: AppColors.textTertiary(ctx),
              decoration: TextDecoration.lineThrough),
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
                  cacheManager: TeqlifCacheManager(),
                  memCacheWidth: 88,
                  memCacheHeight: 88,
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  errorWidget: (context, url, err) =>
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
                  if (sale.totalStock != null && sale.totalStock! > 0) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: (sale.soldCount / sale.totalStock!)
                            .clamp(0.0, 1.0),
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
        builder: (_) => _GiftsModal(gifts: gifts, loc: loc),
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
                    loc.t('giftSenderCount').replaceAll('{count}', '${gifts.senderCount}'),
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

// ── Viewer card ───────────────────────────────────────────────────────────────

class _ViewerCard extends StatefulWidget {
  final _ViewerActivity viewer;
  final TranslationPack loc;
  const _ViewerCard({required this.viewer, required this.loc});

  @override
  State<_ViewerCard> createState() => _ViewerCardState();
}

class _ViewerCardState extends State<_ViewerCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final v = widget.viewer;
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          PublicProfileScreen(username: v.username),
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundImage: v.avatarUrl != null
                        ? CachedNetworkImageProvider(v.avatarUrl!, cacheKey: 'user_${v.userId}_avatar', cacheManager: TeqlifCacheManager())
                        : null,
                    child: v.avatarUrl == null
                        ? const Icon(Icons.person, size: 18)
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                PublicProfileScreen(username: v.username),
                          ),
                        ),
                        child: Text(
                          '@${v.username}',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary(context),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 10,
                        runSpacing: 2,
                        children: [
                          if (v.bids.isNotEmpty)
                            _ActionBadge(
                              icon: Icons.gavel,
                              label: '${v.bids.length} teklif · ₺${v.bidTotal.toStringAsFixed(0)}',
                              color: kPrimary,
                            ),
                          if (v.orders.isNotEmpty)
                            _ActionBadge(
                              icon: Icons.shopping_bag_outlined,
                              label: '${v.orders.length} alım · ₺${v.orderTotal.toStringAsFixed(0)}',
                              color: const Color(0xFF6366F1),
                            ),
                          if (v.gifts.isNotEmpty)
                            _ActionBadge(
                              icon: Icons.card_giftcard_outlined,
                              label: '${v.gifts.length} hediye · ${v.giftTeqlik}⚡',
                              color: const Color(0xFFF97316),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: AppColors.textTertiary(context),
                ),
              ],
            ),
            if (_expanded) ...[
              const SizedBox(height: 10),
              Divider(height: 1, color: AppColors.border(context)),
              const SizedBox(height: 8),
              if (v.bids.isNotEmpty) ...[
                _ActionGroupLabel(
                    icon: Icons.gavel,
                    label: widget.loc.t('detailBidsSectionTitle')),
                ...v.bids.map((b) => _ActionDetailRow(
                      label: b.auctionName,
                      value: '₺${b.amount.toStringAsFixed(2)}',
                      valueColor: kPrimary,
                    )),
                const SizedBox(height: 6),
              ],
              if (v.orders.isNotEmpty) ...[
                _ActionGroupLabel(
                    icon: Icons.shopping_bag_outlined,
                    label: widget.loc.t('detailPurchasesSectionTitle')),
                ...v.orders.map((o) => _ActionDetailRow(
                      label: o.itemName,
                      value: '×${o.quantity} · ₺${o.unitPrice.toStringAsFixed(2)}',
                      valueColor: const Color(0xFF6366F1),
                    )),
                const SizedBox(height: 6),
              ],
              if (v.gifts.isNotEmpty) ...[
                _ActionGroupLabel(
                    icon: Icons.card_giftcard_outlined,
                    label: widget.loc.t('recordingDetailGifts')),
                ...v.gifts.map((g) => _ActionDetailRow(
                      label: g.giftName,
                      value: '${g.costTeqlik}⚡',
                      valueColor: const Color(0xFFF97316),
                    )),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _ActionBadge({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
      ],
    );
  }
}

class _ActionGroupLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  const _ActionGroupLabel({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 12, color: AppColors.textTertiary(context)),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textTertiary(context),
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionDetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  const _ActionDetailRow({required this.label, required this.value, required this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            value,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: valueColor),
          ),
        ],
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
  final TranslationPack loc;

  const _AuctionModal({required this.auction, required this.loc});

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
          Text(
            loc.t('detailBidsSectionTitle'),
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary(context)),
          ),
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
  final TranslationPack loc;

  const _GiftsModal({required this.gifts, required this.loc});

  @override
  Widget build(BuildContext context) {
    return _ModalSheet(
      title: loc.t('recordingDetailGifts'),
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
                ? CachedNetworkImageProvider(participant.avatarUrl!, cacheKey: 'user_${participant.userId}_avatar', cacheManager: TeqlifCacheManager())
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
                  ? CachedNetworkImageProvider(bid.avatarUrl!, cacheKey: 'user_${bid.userId}_avatar', cacheManager: TeqlifCacheManager())
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
                  ? CachedNetworkImageProvider(order.avatarUrl!, cacheKey: 'user_${order.userId}_avatar', cacheManager: TeqlifCacheManager())
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
                  ? CachedNetworkImageProvider(event.avatarUrl!, cacheKey: 'user_${event.userId}_avatar', cacheManager: TeqlifCacheManager())
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

// ── Replay overlay ────────────────────────────────────────────────────────────

int _upperBound(List<ReplayEvent> timeline, double pos) {
  int lo = 0, hi = timeline.length;
  while (lo < hi) {
    final mid = (lo + hi) ~/ 2;
    timeline[mid].offsetSecs <= pos ? lo = mid + 1 : hi = mid;
  }
  return lo;
}

class _ReplayOverlay extends StatelessWidget {
  final List<ReplayEvent> timeline;
  final double posSecs;

  const _ReplayOverlay({required this.timeline, required this.posSecs});

  @override
  Widget build(BuildContext context) {
    final end = _upperBound(timeline, posSecs);
    final count = end.clamp(0, 5);
    final visible = timeline.sublist(end - count, end);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: visible.asMap().entries.map((e) {
        final opacity = ((e.key + 1) / count).clamp(0.3, 1.0);
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Opacity(
            opacity: opacity,
            child: _ReplayBubble(event: e.value),
          ),
        );
      }).toList(),
    );
  }
}

class _ReplayBubble extends StatelessWidget {
  final ReplayEvent event;

  const _ReplayBubble({required this.event});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (event.type) {
      ReplayEventType.bid      => (Icons.gavel,                 AppColors.replayBid(context)),
      ReplayEventType.gift     => (Icons.card_giftcard,         AppColors.replayGift(context)),
      ReplayEventType.purchase => (Icons.shopping_bag_outlined, AppColors.replayPurchase(context)),
      ReplayEventType.chat     => (Icons.chat_bubble_outline,   Colors.white70),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              event.label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
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
