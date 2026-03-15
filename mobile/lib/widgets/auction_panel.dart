import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/api.dart';
import '../config/theme.dart';
import '../models/auction.dart';
import '../services/auction_service.dart';
import '../services/storage_service.dart';

class AuctionPanel extends StatefulWidget {
  final int streamId;
  final bool isHost;

  const AuctionPanel({super.key, required this.streamId, required this.isHost});

  @override
  State<AuctionPanel> createState() => _AuctionPanelState();
}

class _AuctionPanelState extends State<AuctionPanel> {
  AuctionState _state = AuctionState.idle();
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _heartbeat;
  bool _reconnecting = false;

  final _customBidCtrl = TextEditingController();
  String? _msg;
  bool _msgError = false;

  @override
  void initState() {
    super.initState();
    _connectWS();
  }

  @override
  void dispose() {
    _reconnecting = false;
    _heartbeat?.cancel();
    _sub?.cancel();
    try {
      _channel?.sink.close();
    } catch (_) {}
    _customBidCtrl.dispose();
    super.dispose();
  }

  String get _wsBaseUrl {
    return kBaseUrl
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
  }

  void _connectWS() {
    if (!mounted) return;
    _heartbeat?.cancel();
    try {
      final uri = Uri.parse('$_wsBaseUrl/auction/${widget.streamId}/ws');
      _channel = WebSocketChannel.connect(uri);
      _sub = _channel!.stream.listen(
        (data) {
          if (!mounted) return;
          try {
            final json = jsonDecode(data as String) as Map<String, dynamic>;
            if (json['type'] == 'state') {
              setState(() => _state = AuctionState.fromJson(json));
            }
          } catch (_) {}
        },
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
        cancelOnError: false,
      );
      _heartbeat = Timer.periodic(const Duration(seconds: 25), (_) {
        if (!mounted) return;
        try {
          _channel?.sink.add('ping');
        } catch (_) {}
      });
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_reconnecting || !mounted) return;
    _reconnecting = true;
    _heartbeat?.cancel();
    Future.delayed(const Duration(seconds: 4), () {
      if (!mounted) return;
      _reconnecting = false;
      _sub?.cancel();
      try {
        _channel?.sink.close();
      } catch (_) {}
      _connectWS();
    });
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
      );
    } catch (e) {
      _setMsg(e.toString(), error: true);
    }
  }

  Future<void> _pauseAuction() async {
    try {
      await AuctionService.pauseAuction(widget.streamId);
    } catch (e) {
      _setMsg(e.toString(), error: true);
    }
  }

  Future<void> _resumeAuction() async {
    try {
      await AuctionService.resumeAuction(widget.streamId);
    } catch (e) {
      _setMsg(e.toString(), error: true);
    }
  }

  Future<void> _acceptBid() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Teklifi Kabul Et',
            style: TextStyle(color: Colors.white)),
        content: Text(
          '@${_state.currentBidder} kullanıcısının ₺${_fmt(_state.currentBid)} teklifini kabul edeceksiniz.\nÖzet sohbete gönderilecek ve artırma kapanacak.',
          style: const TextStyle(color: Color(0xFF94A3B8)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal',
                  style: TextStyle(color: Color(0xFF64748B)))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8))),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Kabul Et',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await AuctionService.acceptBid(widget.streamId);
      _setMsg('Teklif kabul edildi! Özet sohbete gönderildi.');
    } catch (e) {
      _setMsg(e.toString(), error: true);
    }
  }

  Future<void> _endAuction() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Açık Artırmayı Bitir',
            style: TextStyle(color: Colors.white)),
        content: const Text('Sonuç kaydedilecek ve artırma kapanacak.',
            style: TextStyle(color: Color(0xFF94A3B8))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal',
                  style: TextStyle(color: Color(0xFF64748B)))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8))),
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Bitir', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await AuctionService.endAuction(widget.streamId);
    } catch (e) {
      _setMsg(e.toString(), error: true);
    }
  }

  Future<void> _placeBid(double amount) async {
    try {
      final newState = await AuctionService.placeBid(widget.streamId, amount);
      if (mounted) setState(() => _state = newState);
      _setMsg('₺${_fmt(amount)} teklifiniz alındı!');
      _customBidCtrl.clear();
    } catch (e) {
      _setMsg(e.toString(), error: true);
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
    // Viewer için artırma yoksa gösterme
    if (!widget.isHost && (_state.isIdle || _state.isEnded)) {
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
                _statusBadge(),
                const SizedBox(width: 8),
                // Ürün + fiyat
                Expanded(
                  child: GestureDetector(
                    onTap: (!widget.isHost && _state.listingId != null)
                        ? () => _showListingPopup(context)
                        : null,
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _state.itemName ?? 'Açık Artırma',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (_state.currentBid != null ||
                                  _state.startPrice != null)
                                Text(
                                  '₺${_fmt(_state.currentBid ?? _state.startPrice)}'
                                  '${_state.currentBidder != null ? ' · @${_state.currentBidder}' : ''}',
                                  style: const TextStyle(
                                      color: Color(0xFF4ADE80), fontSize: 11),
                                ),
                            ],
                          ),
                        ),
                        // Viewer: pinlenmiş ilan varsa ikon göster
                        if (!widget.isHost && _state.listingId != null)
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
                // Host inline kontroller
                if (widget.isHost) _hostInlineControls(),
                // Viewer: teklif butonu
                if (!widget.isHost && _state.isActive)
                  _viewerBidButton(context),
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

  Future<void> _showListingPopup(BuildContext context) async {
    final id = _state.listingId;
    if (id == null) return;
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
    final priceStr = price != null
        ? '₺ ${(price as num).toInt().toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.')}'
        : 'Fiyat Belirtilmemiş';
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
                            itemBuilder: (_, i) => Image.network(
                              imageUrls[i],
                              fit: BoxFit.cover,
                              width: double.infinity,
                              errorBuilder: (_, __, ___) => Container(
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

  Widget _statusBadge() {
    final (label, color) = switch (_state.status) {
      'active' => ('AKTİF', Colors.green),
      'paused' => ('DURAKLADI', Colors.amber),
      'ended' => ('BİTTİ', Colors.red),
      _ => ('AÇIK ARTIRMA', const Color(0xFF475569)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
      child: Text(label,
          style: const TextStyle(
              fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white)),
    );
  }

  Widget _hostInlineControls() {
    if (_state.isIdle || _state.isEnded) {
      return _pillBtn('▶ Başlat', Colors.green, _showStartDialog);
    }
    if (_state.isActive) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        _iconBtn(Icons.pause_rounded, Colors.amber, _pauseAuction),
        if (_state.currentBidder != null) ...[
          const SizedBox(width: 6),
          _acceptBtn(),
        ],
        const SizedBox(width: 6),
        _iconBtn(Icons.stop_rounded, Colors.red, _endAuction),
      ]);
    }
    if (_state.isPaused) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        _iconBtn(Icons.play_arrow_rounded, Colors.green, _resumeAuction),
        if (_state.currentBidder != null) ...[
          const SizedBox(width: 6),
          _acceptBtn(),
        ],
        const SizedBox(width: 6),
        _iconBtn(Icons.stop_rounded, Colors.red, _endAuction),
      ]);
    }
    return const SizedBox.shrink();
  }

  Widget _viewerBidButton(BuildContext context) {
    return GestureDetector(
      onTap: () => _showBidSheet(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF16A34A),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text('Teklif Ver',
            style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700)),
      ),
    );
  }

  void _showBidSheet(BuildContext outerContext) {
    final base = _state.currentBid ?? _state.startPrice ?? 0;
    showModalBottomSheet(
      context: outerContext,
      backgroundColor: const Color(0xF01E293B),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 28),
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
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 18),
            // Başlık + fiyat
            Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _state.itemName ?? 'Teklif Ver',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16),
                    ),
                    if (_state.currentBidder != null)
                      Text('@${_state.currentBidder} en yüksek teklif sahibi',
                          style: const TextStyle(
                              color: Color(0xFF64748B), fontSize: 12))
                    else
                      const Text('İlk teklifi sen ver!',
                          style: TextStyle(
                              color: Color(0xFF64748B), fontSize: 12)),
                  ],
                ),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(
                  '₺${_fmt(_state.currentBid ?? _state.startPrice)}',
                  style: const TextStyle(
                      color: Color(0xFF4ADE80),
                      fontWeight: FontWeight.w800,
                      fontSize: 22),
                ),
                if (_state.bidCount > 0)
                  Text('${_state.bidCount} teklif',
                      style: const TextStyle(
                          color: Color(0xFF64748B), fontSize: 11)),
              ]),
            ]),
            const SizedBox(height: 18),
            // 2×2 preset grid
            Row(children: [
              Expanded(child: _sheetBidBtn('+₺100', base + 100, ctx)),
              const SizedBox(width: 8),
              Expanded(child: _sheetBidBtn('+₺250', base + 250, ctx)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _sheetBidBtn('+₺500', base + 500, ctx)),
              const SizedBox(width: 8),
              Expanded(child: _sheetBidBtn('+₺1000', base + 1000, ctx)),
            ]),
            const SizedBox(height: 14),
            // Özel teklif
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _customBidCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style:
                      const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Özel tutar (₺)',
                    hintStyle: const TextStyle(
                        color: Color(0xFF475569), fontSize: 13),
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
                        borderSide:
                            const BorderSide(color: kPrimary)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    final v = double.tryParse(_customBidCtrl.text);
                    if (v == null || v <= 0) {
                      _setMsg('Geçerli tutar girin', error: true);
                      return;
                    }
                    _placeBid(v);
                    Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Teklif Ver',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _sheetBidBtn(String label, double amount, BuildContext sheetCtx) {
    return GestureDetector(
      onTap: () {
        _placeBid(amount);
        Navigator.pop(sheetCtx);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
            color: const Color(0xFF334155),
            borderRadius: BorderRadius.circular(10)),
        child: Text(label,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
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

  Widget _acceptBtn() {
    return GestureDetector(
      onTap: _acceptBid,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF059669),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text('✅ Kabul',
            style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700)),
      ),
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

// ── Açık artırma başlatma dialogu ─────────────────────────────────────────────

class _StartAuctionDialog extends StatefulWidget {
  @override
  State<_StartAuctionDialog> createState() => _StartAuctionDialogState();
}

class _StartAuctionDialogState extends State<_StartAuctionDialog> {
  bool _fromListing = false;
  final _itemCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
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
    return AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      title: const Text('Açık Artırma Başlat',
          style: TextStyle(color: Colors.white, fontSize: 16)),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Mod seçici
            Row(children: [
              Expanded(child: _modeBtn('Manuel Gir', !_fromListing, () => setState(() { _fromListing = false; _selectedListing = null; }))),
              const SizedBox(width: 8),
              Expanded(child: _modeBtn('İlanlarımdan', _fromListing, () => setState(() => _fromListing = true))),
            ]),
            const SizedBox(height: 14),
            // İçerik
            if (!_fromListing) ...[
              _inputField(_itemCtrl, 'Ürün adı'),
              const SizedBox(height: 10),
              _inputField(_priceCtrl, 'Başlangıç fiyatı (₺)', isNumber: true),
            ] else ...[
              if (_loadingListings)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: CircularProgressIndicator(color: kPrimary, strokeWidth: 2)),
                )
              else if (_listings.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text('Aktif ilanınız yok.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
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
                                    ? Image.network(url, width: 38, height: 38, fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => _lpPlaceholder())
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
                _inputField(_priceCtrl, 'Başlangıç fiyatı (₺)', isNumber: true),
              ],
            ],
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('İptal', style: TextStyle(color: Color(0xFF64748B))),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () {
            if (_fromListing) {
              if (_selectedListing == null) return;
              final price = double.tryParse(_priceCtrl.text.replaceAll(',', '.'));
              if (price == null || price < 0) return;
              Navigator.pop(context, {'listing_id': _selectedListing['id'] as int, 'price': price});
            } else {
              final item = _itemCtrl.text.trim();
              final price = double.tryParse(_priceCtrl.text.replaceAll(',', '.'));
              if (item.length < 2 || price == null || price < 0) return;
              Navigator.pop(context, {'item': item, 'price': price});
            }
          },
          child: const Text('Başlat', style: TextStyle(color: Colors.white)),
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
