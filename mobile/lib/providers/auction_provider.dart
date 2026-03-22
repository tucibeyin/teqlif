import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/api.dart';
import '../models/auction.dart';

/// Bir [streamId] için açık artırma WebSocket bağlantısını ve [AuctionState]'i
/// yönetir. Provider dispose edildiğinde soket otomatik kapatılır.
class AuctionNotifier extends StateNotifier<AuctionState> {
  final int streamId;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _heartbeat;
  bool _reconnecting = false;

  AuctionNotifier(this.streamId) : super(AuctionState.idle()) {
    _connect();
  }

  String get _wsBaseUrl => kBaseUrl
      .replaceFirst('https://', 'wss://')
      .replaceFirst('http://', 'ws://');

  void _connect() {
    _heartbeat?.cancel();
    try {
      final uri = Uri.parse('$_wsBaseUrl/auction/$streamId/ws');
      _channel = WebSocketChannel.connect(uri);
      _sub = _channel!.stream.listen(
        (data) {
          try {
            final json = jsonDecode(data as String) as Map<String, dynamic>;
            if (json['type'] == 'state') {
              state = AuctionState.fromJson(json);
            } else if (json['type'] == 'auction_ended_by_buy_it_now') {
              final buyer = json['buyer'] as Map<String, dynamic>?;
              final buyerUsername = buyer?['username'] as String?;
              state = AuctionState(
                status: 'ended',
                itemName: json['item_name'] as String? ?? state.itemName,
                startPrice: state.startPrice,
                buyItNowPrice: state.buyItNowPrice,
                currentBid: (json['price'] as num?)?.toDouble(),
                currentBidder: buyerUsername,
                bidCount: state.bidCount,
                listingId: state.listingId,
                isBoughtItNow: true,
                buyerUsername: buyerUsername,
              );
            } else if (json['type'] == 'buy_it_now_requested') {
              final buyer = json['buyer'] as Map<String, dynamic>?;
              final buyerUsername = buyer?['username'] as String?;
              state = AuctionState(
                status: 'buy_it_now_pending',
                itemName: state.itemName,
                startPrice: state.startPrice,
                buyItNowPrice: state.buyItNowPrice,
                currentBid: state.currentBid,
                currentBidder: state.currentBidder,
                bidCount: state.bidCount,
                listingId: state.listingId,
                pendingBuyerUsername: buyerUsername,
              );
            } else if (json['type'] == 'buy_it_now_rejected') {
              state = AuctionState(
                status: 'active',
                itemName: state.itemName,
                startPrice: state.startPrice,
                buyItNowPrice: state.buyItNowPrice,
                currentBid: state.currentBid,
                currentBidder: state.currentBidder,
                bidCount: state.bidCount,
                listingId: state.listingId,
              );
            }
          } catch (e) {
            debugPrint('[AuctionNotifier] WS mesajı ayrıştırılamadı: $e');
          }
        },
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
        cancelOnError: false,
      );
      _heartbeat = Timer.periodic(const Duration(seconds: 25), (_) {
        try {
          _channel?.sink.add('ping');
        } catch (_) {}
      });
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_reconnecting) return;
    _reconnecting = true;
    _heartbeat?.cancel();
    Future.delayed(const Duration(seconds: 4), () {
      if (!mounted) return;
      _reconnecting = false;
      _sub?.cancel();
      try {
        _channel?.sink.close();
      } catch (_) {}
      _connect();
    });
  }

  @override
  void dispose() {
    _reconnecting = false;
    _heartbeat?.cancel();
    _sub?.cancel();
    try {
      _channel?.sink.close();
    } catch (_) {}
    debugPrint('[AuctionNotifier] disposed (streamId=$streamId)');
    super.dispose();
  }
}

/// Verilen [streamId] için otomatik dispose edilen açık artırma provider'ı.
/// Widget ağacından ayrıldığında WS bağlantısı kapatılır.
final auctionProvider =
    StateNotifierProvider.family.autoDispose<AuctionNotifier, AuctionState, int>(
  (ref, streamId) => AuctionNotifier(streamId),
);
