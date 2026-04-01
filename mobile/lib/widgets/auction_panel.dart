import 'dart:async';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import '../config/theme.dart';
import '../l10n/app_localizations.dart';
import '../core/app_exception.dart';
import '../core/logger_service.dart';
import '../models/auction.dart';
import '../providers/auction_provider.dart';
import '../services/auction_service.dart';
import '../services/storage_service.dart';
import '../utils/price_formatter.dart';
import 'shimmer_loading.dart';

class AuctionPanel extends ConsumerStatefulWidget {
  final int streamId;
  final bool isHost;
  final void Function(String bidder, double amount, String? itemName)? onBidAdded;
  final VoidCallback? onAuctionReset;
  /// false ise viewer teklif butonları devre dışı kalır (mute durumu)
  final bool enabled;
  /// true ise Co-Host modunda çalışır: host kontrol UI'ı gösterilir,
  /// viewer teklif butonları gizlenir. Kamera/mikrofon/yayın bitirme yetkisi yoktur.
  final bool isCoHost;

  const AuctionPanel({
    super.key,
    required this.streamId,
    required this.isHost,
    this.onBidAdded,
    this.onAuctionReset,
    this.enabled = true,
    this.isCoHost = false,
  });

  @override
  ConsumerState<AuctionPanel> createState() => _AuctionPanelState();
}

class _AuctionPanelState extends ConsumerState<AuctionPanel> {
  // isHost veya isCoHost ise host kontrol UI'ı gösterilir
  bool get _isHostLike => widget.isHost || widget.isCoHost;

  String? _msg;
  bool _msgError = false;
  // BIN onay dialog'unun context'i — host kararına göre otomatik kapatmak için
  BuildContext? _binDialogCtx;
  // Bu viewer BIN talebini başlattıysa true — async username'e gerek kalmaz
  bool _iAmBinBuyer = false;
  // Hızlı açık artırma sayacı — her yayın oturumunda Ürün 1, 2, 3... üretir
  int _quickAuctionCount = 0;

  @override
  void dispose() {
    super.dispose();
  }

  String _cleanErr(Object e) {
    final s = e.toString();
    if (s.startsWith('Exception: ')) return s.substring('Exception: '.length);
    return s;
  }

  void _setMsg(String msg, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _msg = msg;
      _msgError = error;
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _msg = null);
    });
  }

  Future<void> _startQuickAuction() async {
    _quickAuctionCount++;
    try {
      await AuctionService.startAuction(
        widget.streamId,
        itemName: 'Ürün $_quickAuctionCount',
        startPrice: 1.0,
      );
    } catch (e) {
      _quickAuctionCount--;
      _setMsg(_cleanErr(e), error: true);
    }
  }

  Future<void> _showStartDialog() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _StartAuctionDialog(),
    );

    if (result == null) return;
    try {
      await AuctionService.startAuction(
        widget.streamId,
        itemName: result['item'] as String?,
        startPrice: result['price'] as double?,
        listingId: result['listing_id'] as int?,
        buyItNowPrice: result['bin_price'] as double?,
      );
    } catch (e) {
      _setMsg(_cleanErr(e), error: true);
    }
  }

  Future<void> _pauseAuction() async {
    try {
      await AuctionService.pauseAuction(widget.streamId);
    } catch (e) {
      _setMsg(_cleanErr(e), error: true);
    }
  }

  Future<void> _resumeAuction() async {
    try {
      await AuctionService.resumeAuction(widget.streamId);
    } catch (e) {
      _setMsg(_cleanErr(e), error: true);
    }
  }

  Future<void> _acceptBid() async {
    final l = AppLocalizations.of(context)!;
    final state = ref.read(auctionProvider(widget.streamId));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('✅ ${l.auctionAcceptBidTitle}',
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Özet kartı
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _acceptRow(l.auctionItem, state.itemName ?? '—'),
                  const SizedBox(height: 10),
                  _acceptRow(l.auctionWinnerPrice,
                      '₺${_fmt(state.currentBid)}',
                      valueColor: const Color(0xFF4ADE80),
                      valueBold: true),
                  const SizedBox(height: 10),
                  _acceptRow(l.auctionBidder,
                      '@${state.currentBidder ?? '—'}'),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              l.auctionAcceptConfirm,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, height: 1.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx, false),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF334155)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text(l.auctionCancelBtn,
                    style: const TextStyle(color: Color(0xFF94A3B8))),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12)),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l.auctionContinueBtn,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await AuctionService.acceptBid(widget.streamId);
      _setMsg(l.auctionAccepted);
    } catch (e) {
      _setMsg(_cleanErr(e), error: true);
    }
  }

  Future<void> _endAuction() async {
    final l = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text(l.auctionEndTitle,
            style: const TextStyle(color: Colors.white)),
        content: Text(l.auctionEndDesc,
            style: const TextStyle(color: Color(0xFF94A3B8))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.btnCancel,
                  style: const TextStyle(color: Color(0xFF64748B)))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8))),
            onPressed: () => Navigator.pop(ctx, true),
            child:
                Text(l.auctionEndBtn, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await AuctionService.endAuction(widget.streamId);
    } catch (e) {
      _setMsg(_cleanErr(e), error: true);
    }
  }

  String _fmt(double? v) {
    if (v == null) return '—';
    return v
        .toStringAsFixed(0)
        .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.');
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final state = ref.watch(auctionProvider(widget.streamId));

    // Callback'leri provider değişimine bağla
    ref.listen<AuctionState>(auctionProvider(widget.streamId), (prev, next) {
      if (prev != null &&
          next.bidCount > prev.bidCount &&
          next.currentBidder != null &&
          next.currentBid != null) {
        widget.onBidAdded?.call(
            next.currentBidder!, next.currentBid!, next.itemName);
      }
      if (prev != null && next.isIdle && !prev.isIdle) {
        widget.onAuctionReset?.call();
      }
      // Hemen Al tamamlandığında bildirim göster
      if (prev != null && !prev.isBoughtItNow && next.isBoughtItNow) {
        if (widget.isHost) {
          final buyer = next.buyerUsername ?? next.currentBidder ?? '?';
          final price = _fmt(next.currentBid);
          _setMsg(l.auctionBuyNowCompleted(buyer, price));
        } else if (_iAmBinBuyer) {
          _setMsg(l.auctionBuyNowCongrats);
        } else {
          final buyer = next.buyerUsername ?? next.currentBidder ?? '?';
          _setMsg(l.auctionBuyNowSoldOther(buyer));
        }
        _iAmBinBuyer = false;
      }
      // Host: Hemen Al talebi geldiğinde onay diyaloğu göster
      if (widget.isHost && prev != null && !prev.isPending && next.isPending) {
        _showBuyItNowRequestDialog(next.pendingBuyerUsername ?? '?', next);
      }
      // Viewer: talep reddedildiğinde bilgi mesajı (isPending → active geçişi)
      if (!widget.isHost && prev != null && prev.isPending && !next.isPending && !next.isBoughtItNow) {
        if (_iAmBinBuyer) {
          // BIN talebini başlatan viewer: diyalog kapat + red mesajı
          if (_binDialogCtx != null && _binDialogCtx!.mounted) {
            Navigator.of(_binDialogCtx!).pop();
            _binDialogCtx = null;
          }
          _setMsg(l.auctionBinRejected, error: true);
        } else {
          _setMsg(l.auctionBinRejectedOther);
        }
        _iAmBinBuyer = false;
      }
      // Viewer: talep tamamlandığında dialog'u kapat (mesaj yukarıda)
      if (!widget.isHost && prev != null && prev.isPending && next.isBoughtItNow) {
        if (_binDialogCtx != null && _binDialogCtx!.mounted) {
          Navigator.of(_binDialogCtx!).pop();
          _binDialogCtx = null;
        }
      }
    });

    // Pure viewer için artırma yoksa gösterme (co-host paneli her zaman görünür)
    if (!_isHostLike && (state.isIdle || state.isEnded)) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xCC000000),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                // Status badge
                _statusBadge(state),
                const SizedBox(width: 8),
                // Ürün + fiyat
                Expanded(
                  child: GestureDetector(
                    onTap: (!_isHostLike && state.listingId != null)
                        ? () => _showListingPopup(context, state.listingId!)
                        : null,
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (state.itemName != null)
                              Text(
                                state.itemName!,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (state.currentBid != null ||
                                  state.startPrice != null)
                                Text(
                                  '₺${_fmt(state.currentBid ?? state.startPrice)}'
                                  '${state.currentBidder != null ? ' · @${state.currentBidder}' : ''}',
                                  style: const TextStyle(
                                      color: Color(0xFF4ADE80), fontSize: 11),
                                ),
                            ],
                          ),
                        ),
                        // Pure viewer: pinlenmiş ilan varsa ikon göster
                        if (!_isHostLike && state.listingId != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.amber.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: Colors.amber.withOpacity(0.6)),
                              ),
                              child: const Icon(Icons.open_in_new,
                                  color: Colors.amber, size: 12),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Host / Co-Host inline kontroller
                if (_isHostLike) _hostInlineControls(state),
                // Pure viewer: teklif butonu (co-host teklif vermez, yönetir)
                if (!_isHostLike && state.isActive)
                  _viewerBidButton(context, state),
              ],
            ),
          ),
          // Mesaj/hata çıktısı
          if (_msg != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 14),
              child: Text(
                _msg!,
                style: TextStyle(
                    fontSize: 11,
                    color: _msgError ? Colors.redAccent : Colors.greenAccent,
                    shadows: const [Shadow(blurRadius: 4, color: Colors.black)]),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showListingPopup(BuildContext context, int id) async {
    try {
      final resp = await http.get(Uri.parse('$kBaseUrl/listings/$id'));
      if (resp.statusCode != 200 || !mounted) return;
      final listing = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      _openListingSheet(context, listing);
    } catch (_) {}
  }

  void _openListingSheet(BuildContext context, Map<String, dynamic> listing) {
    final rawImgs = listing['image_urls'] as List? ?? [];
    final imageUrls = rawImgs
        .map((e) => imgUrl(e as String))
        .where((u) => u.isNotEmpty)
        .toList();
    if (imageUrls.isEmpty) {
      final single = listing['image_url'] as String?;
      if (single != null) imageUrls.add(imgUrl(single));
    }

    final price = listing['price'];
    final l = AppLocalizations.of(context)!;
    final priceStr = price != null
        ? '₺ ${(price as num).toInt().toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.')}'
        : l.listingPriceNotSet;
    final seller = (listing['user'] as Map?)?['username'] ?? '';

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        builder: (_, scrollCtrl) {
          final pageCtrl = PageController();
          final pageIdx = [0]; // mutable single-element list
          return StatefulBuilder(
          builder: (_, setSt) {
            return ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 38, height: 4,
                    decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 16),
                // Resim slider
                if (imageUrls.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 200,
                      child: Stack(
                        children: [
                          PageView.builder(
                            controller: pageCtrl,
                            itemCount: imageUrls.length,
                            onPageChanged: (i) => setSt(() => pageIdx[0] = i),
                            itemBuilder: (_, i) => CachedNetworkImage(
                              imageUrl: imageUrls[i],
                              fit: BoxFit.cover,
                              width: double.infinity,
                              placeholder: (_, __) => const ShimmerBox(),
                              errorWidget: (_, __, ___) => Container(
                                color: const Color(0xFF0F172A),
                                child: const Icon(Icons.image_outlined,
                                    color: Color(0xFF475569), size: 48),
                              ),
                            ),
                          ),
                          // Dot indicators
                          if (imageUrls.length > 1)
                            Positioned(
                              bottom: 8,
                              left: 0,
                              right: 0,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(imageUrls.length, (i) {
                                  final active = i == pageIdx[0];
                                  return AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    margin: const EdgeInsets.symmetric(horizontal: 3),
                                    width: active ? 16 : 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: active ? Colors.white : Colors.white38,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  );
                                }),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 14),
                // Başlık
                Text(
                  listing['title'] ?? '',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 17),
                ),
                const SizedBox(height: 6),
                // Fiyat
                Text(
                  priceStr,
                  style: const TextStyle(
                      color: Color(0xFF4ADE80),
                      fontWeight: FontWeight.w800,
                      fontSize: 20),
                ),
                if (seller.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('@$seller',
                      style: const TextStyle(
                          color: Color(0xFF64748B), fontSize: 13)),
                ],
                if ((listing['description'] as String?)?.isNotEmpty == true) ...[
                  const SizedBox(height: 12),
                  const Divider(color: Color(0xFF334155)),
                  const SizedBox(height: 8),
                  Text(
                    listing['description'] as String,
                    style: const TextStyle(
                        color: Color(0xFF94A3B8), fontSize: 13, height: 1.5),
                  ),
                ],
              ],
            );
          },
        );
        },
      ),
    );
  }

  Widget _statusBadge(AuctionState state) {
    final l = AppLocalizations.of(context)!;
    final String label;
    final Color color;
    if (state.status == 'active') {
      label = l.auctionStatusActive; color = Colors.green;
    } else if (state.status == 'buy_it_now_pending') {
      label = l.auctionStatusPending; color = Colors.orange;
    } else if (state.status == 'paused') {
      label = l.auctionStatusPaused; color = Colors.amber;
    } else if (state.status == 'ended' && state.isBoughtItNow) {
      label = l.auctionStatusSold; color = Colors.orange;
    } else if (state.status == 'ended') {
      label = l.auctionStatusEnded; color = Colors.red;
    } else {
      label = l.auctionStatusIdle; color = const Color(0xFF475569);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
      child: Text(label,
          style: const TextStyle(
              fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white)),
    );
  }

  Widget _hostInlineControls(AuctionState state) {
    final l = AppLocalizations.of(context)!;
    if (state.isIdle || state.isEnded) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        _pillIconBtn(Icons.bolt_rounded, 'Hızlı', Colors.orange, _startQuickAuction),
        const SizedBox(width: 6),
        _pillBtn(l.auctionStartBtn, Colors.green, _showStartDialog),
      ]);
    }
    if (state.isActive) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        _iconBtn(Icons.pause_rounded, Colors.amber, _pauseAuction),
        if (state.currentBidder != null) ...[
          const SizedBox(width: 6),
          _acceptBtn(),
        ],
        const SizedBox(width: 6),
        _iconBtn(Icons.stop_rounded, Colors.red, _endAuction),
      ]);
    }
    if (state.isPaused) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        _iconBtn(Icons.play_arrow_rounded, Colors.green, _resumeAuction),
        if (state.currentBidder != null) ...[
          const SizedBox(width: 6),
          _acceptBtn(),
        ],
        const SizedBox(width: 6),
        _iconBtn(Icons.stop_rounded, Colors.red, _endAuction),
      ]);
    }
    return const SizedBox.shrink();
  }

  Widget _viewerBidButton(BuildContext context, AuctionState state) {
    final l = AppLocalizations.of(context)!;
    final enabled = widget.enabled;
    final bin = state.buyItNowPrice;
    final showBin = enabled &&
        bin != null &&
        (state.currentBid == null || state.currentBid! < bin);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        GestureDetector(
          key: const Key('auction_btn_teklif_ver'),
          onTap: enabled ? () => _showBidSheet(context, state) : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            decoration: BoxDecoration(
              color: enabled ? const Color(0xFF16A34A) : const Color(0xFF334155),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              enabled ? l.auctionBidBtn : l.auctionMutedBtn,
              style: TextStyle(
                color: enabled ? Colors.white : const Color(0xFF64748B),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        if (showBin) ...[
          const SizedBox(height: 4),
          GestureDetector(
            key: const Key('auction_btn_hemen_al'),
            onTap: () => _buyItNow(state),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.orange.shade700,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${l.auctionBuyNowBtn}₺${_fmt(bin)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _buyItNow(AuctionState state) async {
    final l = AppLocalizations.of(context)!;
    var waiting = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        _binDialogCtx = dialogCtx;
        return StatefulBuilder(
          builder: (ctx, setS) {
            _binDialogCtx = ctx;

            if (waiting) {
              return AlertDialog(
                backgroundColor: const Color(0xFF1E293B),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                title: Text('⚡ ${l.auctionBuyNowTitle}',
                    style: const TextStyle(color: Colors.white, fontSize: 16)),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 8),
                    const Text('⏳', style: TextStyle(fontSize: 36)),
                    const SizedBox(height: 12),
                    Text(
                      l.auctionApprovalWaiting,
                      style: const TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.w700,
                          fontSize: 15),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l.auctionApprovalWaitingDesc,
                      style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12,
                          height: 1.5),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              );
            }

            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Text('⚡ ${l.auctionBuyNowTitle}',
                  style: const TextStyle(color: Colors.white, fontSize: 16)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(children: [
                      _acceptRow(l.auctionItem, state.itemName ?? '—'),
                      const SizedBox(height: 10),
                      _acceptRow(l.auctionBuyNowPrice,
                          '₺${_fmt(state.buyItNowPrice)}',
                          valueColor: Colors.orange,
                          valueBold: true),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    l.auctionBuyNowConfirm,
                    style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 12,
                        height: 1.5),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
              actionsPadding:
                  const EdgeInsets.fromLTRB(16, 0, 16, 16),
              actions: [
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                            color: Color(0xFF334155)),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(
                            vertical: 12),
                      ),
                      child: Text(l.btnCancel,
                          style: const TextStyle(
                              color: Color(0xFF94A3B8))),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor:
                              Colors.orange.shade700,
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(
                              vertical: 12)),
                      onPressed: () async {
                        setS(() => waiting = true);
                        try {
                          await AuctionService.buyItNow(widget.streamId);
                          // Başarılı → bu viewer BIN alıcısı olarak işaretlenir
                          _iAmBinBuyer = true;
                          // Dialog ref.listen üzerinden kapanacak (host kararıyla)
                        } on AppException catch (e) {
                          if (ctx.mounted) Navigator.pop(ctx);
                          _setMsg(e.message, error: true);
                        } catch (e, st) {
                          LoggerService.instance.captureException(
                              e,
                              stackTrace: st,
                              tag: '_AuctionPanelState._buyItNow');
                          if (ctx.mounted) Navigator.pop(ctx);
                          _setMsg(_cleanErr(e), error: true);
                        }
                      },
                      child: Text(l.auctionBuyNowBuyBtn,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                ]),
              ],
            );
          },
        );
      },
    );
    _binDialogCtx = null;
  }

  Future<void> _showBuyItNowRequestDialog(String buyerUsername, AuctionState state) async {
    if (!mounted) return;
    final l = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('⚡ ${l.auctionBuyNowRequest}',
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(children: [
                _acceptRow(l.auctionItem, state.itemName ?? '—'),
                const SizedBox(height: 10),
                _acceptRow(l.auctionBuyNowPrice, '₺${_fmt(state.buyItNowPrice)}',
                    valueColor: Colors.orange, valueBold: true),
                const SizedBox(height: 10),
                _acceptRow(l.auctionBuyNowRequester, '@$buyerUsername'),
              ]),
            ),
            const SizedBox(height: 14),
            Text(
              l.auctionBuyNowRequestConfirm,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, height: 1.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx, false),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF334155)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text(l.auctionBuyNowReject,
                    style: const TextStyle(color: Color(0xFFF87171))),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade700,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12)),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l.auctionBuyNowApprove,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ],
      ),
    );
    if (ok == true) {
      try {
        await AuctionService.acceptBuyItNow(widget.streamId);
      } on AppException catch (e) {
        _setMsg(e.message, error: true);
      } catch (e, st) {
        LoggerService.instance.captureException(e, stackTrace: st, tag: '_AuctionPanelState._showBuyItNowRequestDialog.accept');
        _setMsg(_cleanErr(e), error: true);
      }
    } else if (ok == false) {
      try {
        await AuctionService.rejectBuyItNow(widget.streamId);
      } on AppException catch (e) {
        _setMsg(e.message, error: true);
      } catch (e, st) {
        LoggerService.instance.captureException(e, stackTrace: st, tag: '_AuctionPanelState._showBuyItNowRequestDialog.reject');
        _setMsg(_cleanErr(e), error: true);
      }
    }
  }

  void _showBidSheet(BuildContext outerContext, AuctionState state) {
    showModalBottomSheet(
      context: outerContext,
      backgroundColor: const Color(0xF01E293B),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      isScrollControlled: true,
      builder: (_) => _BidSheetContent(streamId: widget.streamId, iAmBinBuyer: _iAmBinBuyer),
    );
  }

  Widget _pillIconBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration:
            BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 12),
            const SizedBox(width: 4),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _pillBtn(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration:
            BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
        child: Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _acceptRow(String label, String value,
      {Color valueColor = const Color(0xFFE2E8F0), bool valueBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(
                color: Color(0xFF64748B), fontSize: 12)),
        Flexible(
          child: Text(value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: valueColor,
                  fontSize: 13,
                  fontWeight:
                      valueBold ? FontWeight.w800 : FontWeight.w600)),
        ),
      ],
    );
  }

  Widget _acceptBtn() {
    return Builder(
      builder: (context) {
        final l = AppLocalizations.of(context)!;
        return GestureDetector(
          onTap: _acceptBid,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF059669),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(l.auctionAcceptBtn,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700)),
          ),
        );
      },
    );
  }

  Widget _iconBtn(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: color.withOpacity(0.2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Icon(icon, color: color, size: 16),
      ),
    );
  }
}

// ── Viewer teklif verme sheet içeriği ─────────────────────────────────────────

class _BidSheetContent extends ConsumerStatefulWidget {
  final int streamId;
  final bool iAmBinBuyer;
  const _BidSheetContent({required this.streamId, this.iAmBinBuyer = false});

  @override
  ConsumerState<_BidSheetContent> createState() => _BidSheetContentState();
}

class _BidSheetContentState extends ConsumerState<_BidSheetContent> {
  final _customBidCtrl = TextEditingController();
  String? _msg;
  bool _msgError = false;
  bool _loading = false;

  @override
  void dispose() {
    _customBidCtrl.dispose();
    super.dispose();
  }

  String _fmt(double? v) {
    if (v == null) return '—';
    return v
        .toStringAsFixed(0)
        .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.');
  }

  void _setMsg(String msg, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _msg = msg;
      _msgError = error;
    });
  }

  Future<void> _placeBid(double amount) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await AuctionService.placeBid(widget.streamId, amount);
      _customBidCtrl.clear();
      _setMsg('₺${_fmt(amount)} teklifiniz alındı!');
    } on AppException catch (e) {
      _setMsg(e.message, error: true);
    } catch (e, st) {
      LoggerService.instance.captureException(e, stackTrace: st, tag: '_BidSheetContent._placeBid');
      final s = e.toString();
      _setMsg(s.startsWith('Exception: ') ? s.substring('Exception: '.length) : s,
          error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _presetBtn(String label, double amount) {
    return GestureDetector(
      onTap: _loading ? null : () => _placeBid(amount),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
            color: _loading
                ? const Color(0xFF1E293B)
                : const Color(0xFF334155),
            borderRadius: BorderRadius.circular(10)),
        child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: _loading ? const Color(0xFF475569) : Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
      ),
    );
  }

  Future<void> _buyItNow() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await AuctionService.buyItNow(widget.streamId);
      // WS broadcast state güncelleyecek
    } on AppException catch (e) {
      _setMsg(e.message, error: true);
    } catch (e, st) {
      LoggerService.instance.captureException(e,
          stackTrace: st, tag: '_BidSheetContent._buyItNow');
      final s = e.toString();
      _setMsg(s.startsWith('Exception: ') ? s.substring('Exception: '.length) : s,
          error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final liveState = ref.watch(auctionProvider(widget.streamId));
    final base = liveState.currentBid ?? liveState.startPrice ?? 0;

    // Hemen Al talebi onay bekliyor (pending)
    if (liveState.isPending && !liveState.isBoughtItNow) {
      final isBuyer = widget.iAmBinBuyer;
      return Padding(
        padding: EdgeInsets.fromLTRB(
            20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 38, height: 4,
                decoration: BoxDecoration(
                    color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.orange.shade900.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.orange.shade600, width: 1.5),
              ),
              child: isBuyer
                  ? Column(children: [
                      Text('⚡ ${l.auctionApprovalWaiting}',
                          style: const TextStyle(color: Colors.orange, fontSize: 18,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      Text(l.auctionApprovalWaitingDesc,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                    ])
                  : Column(children: [
                      Text('⏳ ${l.auctionInProgress}',
                          style: const TextStyle(color: Colors.orange, fontSize: 18,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      Text(
                        l.auctionInProgressDesc(liveState.pendingBuyerUsername ?? '?'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l.auctionInProgressNoBid,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                      ),
                    ]),
            ),
            const SizedBox(height: 20),
          ],
        ),
      );
    }

    // Hemen Al ile satın alındıysa özel ekran göster
    if (liveState.isBoughtItNow && liveState.isEnded) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
            20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 38, height: 4,
                decoration: BoxDecoration(
                    color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.orange.shade900.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.orange.shade600, width: 1.5),
              ),
              child: Column(children: [
                Text('🛒 ${l.auctionSold}',
                    style: const TextStyle(color: Colors.orange, fontSize: 22,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(liveState.itemName ?? '',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 15,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text('₺${_fmt(liveState.currentBid)}',
                    style: const TextStyle(color: Color(0xFF4ADE80), fontSize: 20,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(l.auctionBoughtBy(liveState.buyerUsername ?? '?'),
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
              ]),
            ),
            const SizedBox(height: 20),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 14),
          // Canlı durum rozeti
          _AuctionStatusBadge(state: liveState),
          const SizedBox(height: 14),
          // Başlık + güncel fiyat
          Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    liveState.itemName ?? 'Teklif Ver',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16),
                  ),
                  if (liveState.currentBidder != null)
                    Text(l.auctionHighestBidder(liveState.currentBidder!),
                        style: const TextStyle(
                            color: Color(0xFF64748B), fontSize: 12))
                  else
                    Text(l.auctionFirstBid,
                        style:
                            const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                ],
              ),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(
                '₺${_fmt(liveState.currentBid ?? liveState.startPrice)}',
                style: const TextStyle(
                    color: Color(0xFF4ADE80),
                    fontWeight: FontWeight.w800,
                    fontSize: 22),
              ),
              if (liveState.bidCount > 0)
                Text(l.auctionBidCount(liveState.bidCount),
                    style: const TextStyle(
                        color: Color(0xFF64748B), fontSize: 11)),
              if (liveState.buyItNowPrice != null)
                Text('⚡ ₺${_fmt(liveState.buyItNowPrice)}',
                    style: TextStyle(
                        color: Colors.orange.shade400, fontSize: 11,
                        fontWeight: FontWeight.w600)),
            ]),
          ]),
          const SizedBox(height: 18),
          // Preset butonlar 2×2
          Row(children: [
            Expanded(child: _presetBtn('+₺100', base + 100)),
            const SizedBox(width: 8),
            Expanded(child: _presetBtn('+₺250', base + 250)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _presetBtn('+₺500', base + 500)),
            const SizedBox(width: 8),
            Expanded(child: _presetBtn('+₺1000', base + 1000)),
          ]),
          // Hemen Al butonu — buyItNowPrice varsa ve currentBid < buyItNowPrice ise göster
          Builder(builder: (_) {
            final bin = liveState.buyItNowPrice;
            if (bin == null || (liveState.currentBid != null && liveState.currentBid! >= bin)) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.only(top: 14),
              child: GestureDetector(
                key: const Key('auction_sheet_btn_hemen_al'),
                onTap: _loading ? null : _buyItNow,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: _loading
                        ? const Color(0xFF1E293B)
                        : Colors.orange.shade700,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _loading
                            ? const Color(0xFF334155)
                            : Colors.orange.shade500,
                        width: 1.5),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_loading)
                        const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      else ...[
                        Text('${l.auctionBuyNowBtn}',
                            style: const TextStyle(color: Colors.white,
                                fontWeight: FontWeight.w700, fontSize: 14)),
                        Text('₺${_fmt(bin)}',
                            style: const TextStyle(color: Colors.white,
                                fontWeight: FontWeight.w800, fontSize: 16)),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 14),
          // Özel tutar
          Row(children: [
            Expanded(
              child: TextField(
                key: const Key('auction_input_ozel_teklif'),
                controller: _customBidCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [ThousandsSeparatorInputFormatter()],
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: l.auctionCustomAmountHint,
                  hintStyle:
                      const TextStyle(color: Color(0xFF475569), fontSize: 13),
                  filled: true,
                  fillColor: const Color(0xFF0F172A),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 13),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          const BorderSide(color: Color(0xFF334155))),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          const BorderSide(color: Color(0xFF334155))),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: kPrimary)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                key: const Key('auction_btn_ozel_teklif_gonder'),
                onPressed: _loading
                    ? null
                    : () {
                        final raw =
                            _customBidCtrl.text.replaceAll('.', '');
                        final v = double.tryParse(raw);
                        if (v == null || v <= 0) {
                          _setMsg(l.auctionValidAmount, error: true);
                          return;
                        }
                        _placeBid(v);
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  disabledBackgroundColor: const Color(0xFF1E293B),
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(l.auctionBidBtn,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
          // Başarı / hata mesajı — alan her zaman ayrılır, içerik koşullu
          const SizedBox(height: 12),
          AnimatedOpacity(
            opacity: _msg != null ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _msgError
                    ? const Color(0xFF7F1D1D).withValues(alpha: 0.5)
                    : const Color(0xFF14532D).withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: _msgError
                        ? const Color(0xFFEF4444)
                        : const Color(0xFF4ADE80),
                    width: 1),
              ),
              child: Row(children: [
                Icon(
                  _msgError
                      ? Icons.error_outline_rounded
                      : Icons.check_circle_outline_rounded,
                  color: _msgError
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF4ADE80),
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _msg ?? '',
                    style: TextStyle(
                        color: _msgError
                            ? const Color(0xFFFCA5A5)
                            : const Color(0xFF86EFAC),
                        fontSize: 13),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Açık artırma başlatma dialogu ─────────────────────────────────────────────

class _StartAuctionDialog extends StatefulWidget {
  @override
  State<_StartAuctionDialog> createState() => _StartAuctionDialogState();
}

class _StartAuctionDialogState extends State<_StartAuctionDialog> {
  bool _fromListing = false;
  final _itemCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _binCtrl = TextEditingController();
  List<dynamic> _listings = [];
  bool _loadingListings = false;
  dynamic _selectedListing;

  @override
  void initState() {
    super.initState();
    _loadListings();
  }

  @override
  void dispose() {
    _itemCtrl.dispose();
    _priceCtrl.dispose();
    _binCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadListings() async {
    setState(() => _loadingListings = true);
    try {
      final token = await StorageService.getToken();
      if (token == null) return;
      final resp = await http.get(
        Uri.parse('$kBaseUrl/listings/my?active=true'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200 && mounted) {
        setState(() => _listings = jsonDecode(resp.body) as List);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingListings = false);
    }
  }

  String _fmtPrice(dynamic price) {
    if (price == null) return '';
    return '₺ ${(price as num).toInt().toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.')}';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      title: Text(l.auctionStartTitle,
          style: const TextStyle(color: Colors.white, fontSize: 16)),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Mod seçici
            Row(children: [
              Expanded(child: _modeBtn(l.auctionManualEntry, !_fromListing, () => setState(() { _fromListing = false; _selectedListing = null; }))),
              const SizedBox(width: 8),
              Expanded(child: _modeBtn(l.auctionFromListings, _fromListing, () => setState(() => _fromListing = true))),
            ]),
            const SizedBox(height: 14),
            // İçerik
            if (!_fromListing) ...[
              _inputField(_itemCtrl, l.auctionItemName),
              const SizedBox(height: 10),
              _inputField(_priceCtrl, l.auctionStartPrice, isNumber: true),
              const SizedBox(height: 10),
              _inputField(_binCtrl, l.auctionBuyNowPriceHint, isNumber: true),
            ] else ...[
              if (_loadingListings)
                const Column(
                  children: [
                    ShimmerListRow(),
                    ShimmerListRow(),
                    ShimmerListRow(),
                  ],
                )
              else if (_listings.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(l.auctionNoActiveListings,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _listings.length,
                    itemBuilder: (_, i) {
                      final l = _listings[i];
                      final isSelected = _selectedListing != null && _selectedListing['id'] == l['id'];
                      return GestureDetector(
                        onTap: () => setState(() => _selectedListing = l),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected ? kPrimary.withOpacity(0.15) : const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected ? kPrimary : const Color(0xFF334155),
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(children: [
                            // Küçük fotoğraf
                            Builder(builder: (_) {
                              final imgs = l['image_urls'] as List? ?? [];
                              final rawImg = imgs.isNotEmpty ? imgs[0] as String : (l['image_url'] as String?);
                              final url = rawImg != null ? imgUrl(rawImg) : null;
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: url != null && url.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: url,
                                        width: 38, height: 38,
                                        fit: BoxFit.cover,
                                        placeholder: (_, __) => const ShimmerBox(
                                          width: 38, height: 38,
                                        ),
                                        errorWidget: (_, __, ___) => _lpPlaceholder())
                                    : _lpPlaceholder(),
                              );
                            }),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(l['title'] ?? '',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13)),
                                  if (l['price'] != null)
                                    Text(_fmtPrice(l['price']),
                                        style: const TextStyle(
                                            color: Color(0xFF4ADE80), fontSize: 12)),
                                ],
                              ),
                            ),
                            if (isSelected)
                              const Icon(Icons.check_circle, color: kPrimary, size: 18),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
              if (_fromListing) ...[
                const SizedBox(height: 10),
                _inputField(_priceCtrl, l.auctionStartPrice, isNumber: true),
                const SizedBox(height: 10),
                _inputField(_binCtrl, l.auctionBuyNowPriceHint, isNumber: true),
              ],
            ],
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.btnCancel, style: const TextStyle(color: Color(0xFF64748B))),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () {
            final binRaw = _binCtrl.text.replaceAll('.', '').replaceAll(',', '.');
            final binPrice = binRaw.isNotEmpty ? double.tryParse(binRaw) : null;
            if (_fromListing) {
              if (_selectedListing == null) return;
              final raw = _priceCtrl.text.replaceAll('.', '').replaceAll(',', '.');
              final price = double.tryParse(raw);
              if (price == null || price < 0) return;
              Navigator.pop(context, {
                'listing_id': _selectedListing['id'] as int,
                'price': price,
                if (binPrice != null && binPrice > 0) 'bin_price': binPrice,
              });
            } else {
              final item = _itemCtrl.text.trim();
              final raw = _priceCtrl.text.replaceAll('.', '').replaceAll(',', '.');
              final price = double.tryParse(raw);
              if (item.length < 2 || price == null || price < 0) return;
              Navigator.pop(context, {
                'item': item,
                'price': price,
                if (binPrice != null && binPrice > 0) 'bin_price': binPrice,
              });
            }
          },
          child: Text(l.liveStartBtn, style: const TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  Widget _modeBtn(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: active ? kPrimary.withOpacity(0.2) : const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: active ? kPrimary : const Color(0xFF334155),
              width: active ? 1.5 : 1),
        ),
        child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: active ? kPrimary : const Color(0xFF64748B),
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _lpPlaceholder() => Container(
        width: 38, height: 38,
        decoration: BoxDecoration(color: const Color(0xFF334155), borderRadius: BorderRadius.circular(6)),
        child: const Icon(Icons.image_outlined, color: Color(0xFF475569), size: 18),
      );

  Widget _inputField(TextEditingController ctrl, String hint, {bool isNumber = false}) {
    return TextField(
      controller: ctrl,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      inputFormatters: isNumber ? [ThousandsSeparatorInputFormatter()] : null,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF475569)),
        filled: true,
        fillColor: const Color(0xFF0F172A),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF334155))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF334155))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: kPrimary)),
      ),
    );
  }
}

// ── Açık artırma durum rozeti ──────────────────────────────────────────────

class _AuctionStatusBadge extends StatelessWidget {
  final AuctionState state;
  const _AuctionStatusBadge({required this.state});

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (state.status) {
      'active'            => ('Aktif',   const Color(0xFF16A34A), Icons.circle),
      'paused'            => ('Durdu',   const Color(0xFFF59E0B), Icons.pause_circle),
      'ended'             => ('Bitti',   const Color(0xFFEF4444), Icons.stop_circle_outlined),
      'buy_it_now_pending'=> ('Bekliyor',const Color(0xFFF97316), Icons.hourglass_top),
      _                   => ('Bekleniyor', const Color(0xFF475569), Icons.radio_button_unchecked),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 10),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }
}
