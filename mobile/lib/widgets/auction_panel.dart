import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/api.dart';
import '../config/theme.dart';
import '../models/auction.dart';
import '../services/auction_service.dart';

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
    final itemCtrl = TextEditingController();
    final priceCtrl = TextEditingController();

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Açık Artırma Başlat',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dialogInput(itemCtrl, 'Ürün adı'),
            const SizedBox(height: 12),
            _dialogInput(priceCtrl, 'Başlangıç fiyatı (₺)', isNumber: true),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal',
                style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              final item = itemCtrl.text.trim();
              final price = double.tryParse(priceCtrl.text);
              if (item.isEmpty || price == null || price < 0) return;
              Navigator.pop(ctx, {'item': item, 'price': price});
            },
            child:
                const Text('Başlat', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (result == null) return;
    try {
      await AuctionService.startAuction(
          widget.streamId, result['item'] as String, result['price'] as double);
    } catch (e) {
      _setMsg(e.toString(), error: true);
    }
  }

  Widget _dialogInput(TextEditingController ctrl, String hint,
      {bool isNumber = false}) {
    return TextField(
      controller: ctrl,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF475569)),
        filled: true,
        fillColor: const Color(0xFF0F172A),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
        const SizedBox(width: 6),
        _iconBtn(Icons.stop_rounded, Colors.red, _endAuction),
      ]);
    }
    if (_state.isPaused) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        _iconBtn(Icons.play_arrow_rounded, Colors.green, _resumeAuction),
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
