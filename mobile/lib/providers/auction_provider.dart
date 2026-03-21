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
            }
          } catch (_) {}
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
