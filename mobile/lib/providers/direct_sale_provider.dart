import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/api.dart';
import '../models/direct_sale.dart';
import '../services/storage_service.dart';

// ── Host ViewModel (Task 4.4) ─────────────────────────────────────────────────

/// Host tarafı — satış yaşam döngüsünü (start/pause/resume/end/cancel) yönetir.
/// WS bağlantısı auction kanalından (aynı Redis stream) direct_sale_* event'leri alır.
/// Host API çağrısı başarılıysa [applyState] ile anında state'i günceller;
/// WS event'i eşzamanlı gelebilir ama override etmez (sonuncusu kazanır).
class DirectSaleHostNotifier extends StateNotifier<DirectSaleState> {
  final int streamId;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _heartbeat;
  bool _reconnecting = false;
  int _reconnectAttempt = 0;

  DirectSaleHostNotifier(this.streamId) : super(DirectSaleState.idle()) {
    unawaited(_connect());
  }

  String get _wsBase => kBaseUrl
      .replaceFirst('https://', 'wss://')
      .replaceFirst('http://', 'ws://');

  Future<void> _connect() async {
    _heartbeat?.cancel();
    final token = await StorageService.getToken();
    try {
      // Auction WS kanalı — direct_sale_* event'leri de buradan gelir (T-2)
      final uri = Uri.parse('$_wsBase/auction/$streamId/ws');
      _channel = WebSocketChannel.connect(uri);
      if (token != null) {
        _channel!.sink.add(jsonEncode({'token': token}));
      }
      _reconnectAttempt = 0;
      _sub = _channel!.stream.listen(
        _onEvent,
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

  void _onEvent(dynamic data) {
    try {
      final json = jsonDecode(data as String) as Map<String, dynamic>;
      final type = json['type'] as String?;
      if (type == null || !type.startsWith('direct_sale_')) return;
      _applyWsEvent(type, json);
    } catch (e) {
      debugPrint('[DirectSaleHostNotifier] WS ayrıştırma hatası: $e');
    }
  }

  void _applyWsEvent(String type, Map<String, dynamic> j) {
    switch (type) {
      case 'direct_sale_started':
        state = DirectSaleState.fromJson(j);
      case 'direct_sale_paused':
        state = state.copyWith(status: 'paused');
      case 'direct_sale_resumed':
        state = state.copyWith(status: 'active');
      case 'direct_sale_sold_out':
        state = state.copyWith(status: 'sold_out', remainingStock: 0);
      case 'direct_sale_purchased':
        final remaining = (j['remaining_stock'] as num?)?.toInt();
        if (remaining != null) state = state.copyWith(remainingStock: remaining);
      case 'direct_sale_ended':
        state = state.copyWith(
          status: 'ended',
          endReason: j['end_reason'] as String?,
        );
      case 'direct_sale_cancelled':
        state = state.copyWith(status: 'cancelled');
    }
  }

  void _scheduleReconnect() {
    if (_reconnecting) return;
    _reconnecting = true;
    _heartbeat?.cancel();
    final delayMs = (1000 * pow(1.5, _reconnectAttempt)).clamp(1000, 60000).toInt();
    _reconnectAttempt++;
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

  /// API çağrısı başarılıysa WS broadcast beklenmeden anında güncelle.
  void applyState(DirectSaleState newState) {
    state = newState;
  }

  void reset() => state = DirectSaleState.idle();

  @override
  void dispose() {
    _reconnecting = false;
    _heartbeat?.cancel();
    _sub?.cancel();
    try {
      _channel?.sink.close();
    } catch (_) {}
    debugPrint('[DirectSaleHostNotifier] disposed (streamId=$streamId)');
    super.dispose();
  }
}

final directSaleHostProvider = StateNotifierProvider.family
    .autoDispose<DirectSaleHostNotifier, DirectSaleState, int>(
  (ref, streamId) => DirectSaleHostNotifier(streamId),
);

// ── Viewer ViewModel (Task 4.5) ───────────────────────────────────────────────

/// Viewer durumu — purchase akışı ve lokal stok sayacını yönetir.
/// WS aynı kanaldan izlenir; purchase sonrası yerel state anında güncellenir.
class DirectSaleViewerNotifier extends StateNotifier<DirectSaleViewerState> {
  final int streamId;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _heartbeat;
  bool _reconnecting = false;
  int _reconnectAttempt = 0;

  DirectSaleViewerNotifier(this.streamId) : super(const DirectSaleViewerState()) {
    unawaited(_connect());
  }

  String get _wsBase => kBaseUrl
      .replaceFirst('https://', 'wss://')
      .replaceFirst('http://', 'ws://');

  Future<void> _connect() async {
    _heartbeat?.cancel();
    final token = await StorageService.getToken();
    try {
      final uri = Uri.parse('$_wsBase/auction/$streamId/ws');
      _channel = WebSocketChannel.connect(uri);
      if (token != null) {
        _channel!.sink.add(jsonEncode({'token': token}));
      }
      _reconnectAttempt = 0;
      _sub = _channel!.stream.listen(
        _onEvent,
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

  void _onEvent(dynamic data) {
    try {
      final json = jsonDecode(data as String) as Map<String, dynamic>;
      final type = json['type'] as String?;
      if (type == null || !type.startsWith('direct_sale_')) return;
      _applyWsEvent(type, json);
    } catch (e) {
      debugPrint('[DirectSaleViewerNotifier] WS ayrıştırma hatası: $e');
    }
  }

  void _applyWsEvent(String type, Map<String, dynamic> j) {
    switch (type) {
      case 'direct_sale_started':
        state = state.copyWith(
          saleState: DirectSaleState.fromJson(j),
          purchaseStatus: ViewerPurchaseStatus.idle,
          errorMessage: null,
        );
      case 'direct_sale_paused':
        state = state.copyWith(
          saleState: state.saleState?.copyWith(status: 'paused'),
        );
      case 'direct_sale_resumed':
        state = state.copyWith(
          saleState: state.saleState?.copyWith(status: 'active'),
        );
      case 'direct_sale_sold_out':
        state = state.copyWith(
          saleState: state.saleState?.copyWith(status: 'sold_out', remainingStock: 0),
        );
      case 'direct_sale_purchased':
        final remaining = (j['remaining_stock'] as num?)?.toInt();
        if (remaining != null) {
          state = state.copyWith(
            saleState: state.saleState?.copyWith(remainingStock: remaining),
          );
        }
      case 'direct_sale_ended':
        state = state.copyWith(
          saleState: state.saleState?.copyWith(
            status: 'ended',
            endReason: j['end_reason'] as String?,
          ),
          purchaseStatus: ViewerPurchaseStatus.idle,
        );
      case 'direct_sale_cancelled':
        state = state.copyWith(
          saleState: state.saleState?.copyWith(status: 'cancelled'),
          purchaseStatus: ViewerPurchaseStatus.idle,
        );
    }
  }

  void _scheduleReconnect() {
    if (_reconnecting) return;
    _reconnecting = true;
    _heartbeat?.cancel();
    final delayMs = (1000 * pow(1.5, _reconnectAttempt)).clamp(1000, 60000).toInt();
    _reconnectAttempt++;
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

  /// Purchase başlatılırken loading state'e geç; sonuç gelince güncelle.
  void beginPurchase() {
    state = state.copyWith(purchaseStatus: ViewerPurchaseStatus.loading, errorMessage: null);
  }

  void purchaseSuccess() {
    state = state.copyWith(purchaseStatus: ViewerPurchaseStatus.success);
  }

  void purchaseError(String message) {
    state = state.copyWith(purchaseStatus: ViewerPurchaseStatus.error, errorMessage: message);
  }

  void resetPurchase() {
    state = state.copyWith(purchaseStatus: ViewerPurchaseStatus.idle, errorMessage: null);
  }

  @override
  void dispose() {
    _reconnecting = false;
    _heartbeat?.cancel();
    _sub?.cancel();
    try {
      _channel?.sink.close();
    } catch (_) {}
    debugPrint('[DirectSaleViewerNotifier] disposed (streamId=$streamId)');
    super.dispose();
  }
}

enum ViewerPurchaseStatus { idle, loading, success, error }

class DirectSaleViewerState {
  final DirectSaleState? saleState; // null → henüz idle (WS bağlandı ama satış yok)
  final ViewerPurchaseStatus purchaseStatus;
  final String? errorMessage;

  const DirectSaleViewerState({
    this.saleState,
    this.purchaseStatus = ViewerPurchaseStatus.idle,
    this.errorMessage,
  });

  DirectSaleViewerState copyWith({
    DirectSaleState? saleState,
    ViewerPurchaseStatus? purchaseStatus,
    String? errorMessage,
  }) =>
      DirectSaleViewerState(
        saleState: saleState ?? this.saleState,
        purchaseStatus: purchaseStatus ?? this.purchaseStatus,
        errorMessage: errorMessage ?? this.errorMessage,
      );

  bool get hasSale => saleState != null && !saleState!.isIdle;
  bool get isLoading => purchaseStatus == ViewerPurchaseStatus.loading;
  bool get isPurchaseSuccess => purchaseStatus == ViewerPurchaseStatus.success;
  bool get isPurchaseError => purchaseStatus == ViewerPurchaseStatus.error;
}

final directSaleViewerProvider = StateNotifierProvider.family
    .autoDispose<DirectSaleViewerNotifier, DirectSaleViewerState, int>(
  (ref, streamId) => DirectSaleViewerNotifier(streamId),
);
