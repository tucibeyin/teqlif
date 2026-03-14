import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/api.dart';
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
  bool _reconnecting = false;

  final _itemCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
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
    _sub?.cancel();
    _channel?.sink.close();
    _itemCtrl.dispose();
    _priceCtrl.dispose();
    _customBidCtrl.dispose();
    super.dispose();
  }

  void _connectWS() {
    if (!mounted) return;
    final wsUrl = kBaseUrl
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
    try {
      _channel = WebSocketChannel.connect(
        Uri.parse('$wsUrl/auction/${widget.streamId}/ws'),
      );
      _sub = _channel!.stream.listen(
        (data) {
          if (!mounted) return;
          final json = jsonDecode(data as String) as Map<String, dynamic>;
          if (json['type'] == 'state') {
            setState(() => _state = AuctionState.fromJson(json));
          }
        },
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_reconnecting || !mounted) return;
    _reconnecting = true;
    Future.delayed(const Duration(seconds: 3), () {
      _reconnecting = false;
      _sub?.cancel();
      _channel?.sink.close();
      _connectWS();
    });
  }

  void _setMsg(String msg, {bool error = false}) {
    setState(() { _msg = msg; _msgError = error; });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _msg = null);
    });
  }

  Future<void> _startAuction() async {
    final item = _itemCtrl.text.trim();
    final price = double.tryParse(_priceCtrl.text);
    if (item.isEmpty) return _setMsg('Ürün adı girin', error: true);
    if (price == null || price < 0) return _setMsg('Geçerli fiyat girin', error: true);
    try {
      await AuctionService.startAuction(widget.streamId, item, price);
    } catch (e) { _setMsg(e.toString(), error: true); }
  }

  Future<void> _pauseAuction() async {
    try { await AuctionService.pauseAuction(widget.streamId); }
    catch (e) { _setMsg(e.toString(), error: true); }
  }

  Future<void> _resumeAuction() async {
    try { await AuctionService.resumeAuction(widget.streamId); }
    catch (e) { _setMsg(e.toString(), error: true); }
  }

  Future<void> _endAuction() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Açık Artırmayı Bitir'),
        content: const Text('Açık artırmayı sonlandırmak istediğinizden emin misiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Bitir', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try { await AuctionService.endAuction(widget.streamId); }
    catch (e) { _setMsg(e.toString(), error: true); }
  }

  Future<void> _placeBid(double amount) async {
    try {
      await AuctionService.placeBid(widget.streamId, amount);
      _setMsg('₺${_formatPrice(amount)} teklifiniz alındı!');
      _customBidCtrl.clear();
    } catch (e) { _setMsg(e.toString(), error: true); }
  }

  String _formatPrice(double? v) {
    if (v == null) return '—';
    return v.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (m) => '${m[1]}.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(),
          const SizedBox(height: 10),
          if (_state.currentBid != null || _state.startPrice != null) ...[
            _bidInfo(),
            const SizedBox(height: 10),
          ],
          if (widget.isHost) _hostControls() else _viewerControls(),
          if (_msg != null) ...[
            const SizedBox(height: 8),
            Text(
              _msg!,
              style: TextStyle(
                fontSize: 12,
                color: _msgError ? Colors.redAccent : Colors.greenAccent,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _header() {
    final (label, color) = switch (_state.status) {
      'active' => ('AKTİF', Colors.green),
      'paused' => ('DURAKLATILDI', Colors.amber),
      'ended'  => ('TAMAMLANDI', Colors.red),
      _        => ('AÇIK ARTIRMA', const Color(0xFF475569)),
    };
    return Row(
      children: [
        Expanded(
          child: Text(
            _state.itemName ?? 'Açık Artırma',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
          child: Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)),
        ),
      ],
    );
  }

  Widget _bidInfo() {
    final price = _state.currentBid ?? _state.startPrice;
    return Column(
      children: [
        Text(
          '₺${_formatPrice(price)}',
          style: const TextStyle(
            color: Color(0xFF4ADE80),
            fontSize: 28,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (_state.currentBidder != null)
          Text(
            '@${_state.currentBidder} en yüksek teklif',
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
          )
        else if (_state.startPrice != null && _state.currentBidder == null)
          Text(
            'Başlangıç fiyatı',
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
          ),
        if (_state.bidCount > 0)
          Text(
            '${_state.bidCount} teklif',
            style: const TextStyle(color: Color(0xFF475569), fontSize: 11),
          ),
      ],
    );
  }

  Widget _hostControls() {
    return Column(
      children: [
        if (_state.isIdle || _state.isEnded) ...[
          _input(_itemCtrl, 'Ürün adı'),
          const SizedBox(height: 8),
          _input(_priceCtrl, 'Başlangıç fiyatı (₺)', isNumber: true),
          const SizedBox(height: 10),
          _btn('▶  Başlat', Colors.green, _startAuction),
        ] else if (_state.isActive) ...[
          Row(children: [
            Expanded(child: _btn('⏸  Duraklat', const Color(0xFFD97706), _pauseAuction)),
            const SizedBox(width: 8),
            Expanded(child: _btn('⏹  Bitir', Colors.red, _endAuction)),
          ]),
        ] else if (_state.isPaused) ...[
          Row(children: [
            Expanded(child: _btn('▶  Devam', Colors.green, _resumeAuction)),
            const SizedBox(width: 8),
            Expanded(child: _btn('⏹  Bitir', Colors.red, _endAuction)),
          ]),
        ],
      ],
    );
  }

  Widget _viewerControls() {
    if (!_state.isActive) {
      return Text(
        _state.isEnded ? 'Açık artırma tamamlandı' : 'Açık artırma henüz başlamadı',
        style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
      );
    }
    final currentPrice = _state.currentBid ?? _state.startPrice ?? 0;
    return Column(
      children: [
        Row(children: [
          Expanded(child: _bidBtn('+₺100', currentPrice + 100)),
          const SizedBox(width: 6),
          Expanded(child: _bidBtn('+₺200', currentPrice + 200)),
          const SizedBox(width: 6),
          Expanded(child: _bidBtn('+₺500', currentPrice + 500)),
          const SizedBox(width: 6),
          Expanded(child: _bidBtn('+₺1000', currentPrice + 1000)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _customBidCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Özel teklif (₺)',
                hintStyle: const TextStyle(color: Color(0xFF475569), fontSize: 12),
                filled: true,
                fillColor: const Color(0xFF0F172A),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF334155)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF334155)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF6366F1)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () {
              final v = double.tryParse(_customBidCtrl.text);
              if (v == null || v <= 0) return _setMsg('Geçerli tutar girin', error: true);
              _placeBid(v);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF16A34A),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Teklif Ver', style: TextStyle(color: Colors.white, fontSize: 12)),
          ),
        ]),
      ],
    );
  }

  Widget _bidBtn(String label, double amount) {
    return GestureDetector(
      onTap: () => _placeBid(amount),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF334155),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _input(TextEditingController ctrl, String hint, {bool isNumber = false}) {
    return TextField(
      controller: ctrl,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF475569), fontSize: 12),
        filled: true,
        fillColor: const Color(0xFF0F172A),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF6366F1))),
      ),
    );
  }

  Widget _btn(String label, Color color, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(vertical: 11),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
      ),
    );
  }
}
