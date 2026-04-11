import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/api.dart';
import '../models/auction.dart';
import '../services/storage_service.dart';

/// Bir [streamId] için açık artırma WebSocket bağlantısını ve [AuctionState]'i
/// yönetir. Provider dispose edildiğinde soket otomatik kapatılır.
class AuctionNotifier extends StateNotifier<AuctionState> {
  final int streamId;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _heartbeat;
  bool _reconnecting = false;
  int _reconnectAttempt = 0;

  AuctionNotifier(this.streamId) : super(AuctionState.idle()) {
    unawaited(_connect());
  }

  String get _wsBaseUrl => kBaseUrl
      .replaceFirst('https://', 'wss://')
      .replaceFirst('http://', 'ws://');

  Future<void> _connect() async {
    _heartbeat?.cancel();
    final token = await StorageService.getToken();
    try {
      final uri = Uri.parse('$_wsBaseUrl/auction/$streamId/ws');
      _channel = WebSocketChannel.connect(uri);
      // Soft auth: token varsa gönder, yoksa anonim izleyici olarak devam
      if (token != null) {
        _channel!.sink.add(jsonEncode({'token': token}));
      }
      _reconnectAttempt = 0; // başarılı bağlantıda sıfırla
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

    // Exponential backoff: 1s, 1.5s, 2.25s … max 60s
    final delayMs = (1000 * pow(1.5, _reconnectAttempt)).clamp(1000, 60000).toInt();
    _reconnectAttempt++;

    if (_reconnectAttempt > 1 && state.status != 'error') {
      // İlk başarısız denemeden sonra hata durumunu UI'a yansıt
      state = AuctionState.error('Bağlantı kesildi, yeniden deneniyor…');
    }

    Future.delayed(Duration(milliseconds: delayMs), () {
      if (!mounted) return;
      _reconnecting = false;
      _sub?.cancel();
      try {
        _channel?.sink.close();
      } catch (_) {}
      unawaited(_connect());
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
