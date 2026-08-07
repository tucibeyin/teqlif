import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/api.dart';
import '../models/direct_sale.dart';
import '../services/direct_sale_service.dart';
import '../services/localization_service.dart';
import '../services/storage_service.dart';
import '../utils/error_helper.dart';

void _dsLog(String phase, String msg) {
  debugPrint('[DIRECT_SALE][${DateTime.now().toIso8601String()}][$phase] $msg');
}

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
    _dsLog('WS', 'connecting | streamId=$streamId attempt=$_reconnectAttempt');
    try {
      // Auction WS kanalı — direct_sale_* event'leri de buradan gelir (T-2)
      final uri = Uri.parse('$_wsBase/auction/$streamId/ws');
      _channel = WebSocketChannel.connect(uri);
      if (token != null) {
        _channel!.sink.add(jsonEncode({'token': token}));
        _dsLog('WS', 'connected, auth sent | streamId=$streamId');
      } else {
        _dsLog('WS', 'connected, no token (anonymous) | streamId=$streamId');
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
    } catch (e) {
      _dsLog('WS', 'connect error | streamId=$streamId $e');
      _scheduleReconnect();
    }
  }

  void _onEvent(dynamic data) {
    try {
      final json = jsonDecode(data as String) as Map<String, dynamic>;
      final type = json['type'] as String?;
      if (type == null || !type.startsWith('direct_sale_')) return;
      _dsLog('WS', 'event received | type=$type streamId=$streamId');
      _applyWsEvent(type, json);
    } catch (e) {
      _dsLog('WS', 'parse error | streamId=$streamId $e');
    }
  }

  void _applyWsEvent(String type, Map<String, dynamic> j) {
    final prevStatus = state.status;
    switch (type) {
      case 'direct_sale_started':
        final parsed = DirectSaleState.fromJson(j);
        _dsLog('STATE', 'direct_sale_started parsed | status=${parsed.status} saleId=${parsed.saleId}');
        state = parsed;
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
    _dsLog('STATE', '$type → $prevStatus → ${state.status} | saleId=${state.saleId}');
  }

  void _scheduleReconnect() {
    if (_reconnecting) return;
    _reconnecting = true;
    _heartbeat?.cancel();
    final delayMs = (1000 * pow(1.5, _reconnectAttempt)).clamp(1000, 60000).toInt();
    _reconnectAttempt++;
    _dsLog('WS', 'reconnect scheduled | streamId=$streamId delay=${delayMs}ms attempt=$_reconnectAttempt');
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
    _dsLog('STATE', 'applyState | ${state.status} → ${newState.status} saleId=${newState.saleId}');
    state = newState;
  }

  void reset() {
    _dsLog('STATE', 'reset | streamId=$streamId');
    state = DirectSaleState.idle();
  }

  // ── Action metodları (View'dan çağrılır, BuildContext almaz) ───────────────

  bool _busy = false;

  Future<void> pause(TranslationPack loc) async {
    if (_busy) return;
    _busy = true;
    _dsLog('API', 'pause | saleId=${state.saleId}');
    try {
      state = await DirectSaleService.pauseSale(state.saleId);
      _dsLog('API', 'pause OK | status=${state.status}');
    } catch (e) {
      _dsLog('API', 'pause ERROR | $e');
      handleError(e, loc);
    } finally {
      _busy = false;
    }
  }

  Future<void> resume(TranslationPack loc) async {
    if (_busy) return;
    _busy = true;
    _dsLog('API', 'resume | saleId=${state.saleId}');
    try {
      state = await DirectSaleService.resumeSale(state.saleId);
      _dsLog('API', 'resume OK | status=${state.status}');
    } catch (e) {
      _dsLog('API', 'resume ERROR | $e');
      handleError(e, loc);
    } finally {
      _busy = false;
    }
  }

  Future<void> end(TranslationPack loc) async {
    if (_busy) return;
    _busy = true;
    _dsLog('API', 'end | saleId=${state.saleId}');
    try {
      state = await DirectSaleService.endSale(state.saleId);
      _dsLog('API', 'end OK | status=${state.status}');
    } catch (e) {
      _dsLog('API', 'end ERROR | $e');
      handleError(e, loc);
    } finally {
      _busy = false;
    }
  }

  Future<void> cancel(TranslationPack loc, {required bool ordersVoided}) async {
    if (_busy) return;
    _busy = true;
    _dsLog('API', 'cancel | saleId=${state.saleId} ordersVoided=$ordersVoided');
    try {
      await DirectSaleService.cancelSale(state.saleId, ordersVoided: ordersVoided);
      state = state.copyWith(status: 'cancelled');
      _dsLog('API', 'cancel OK');
    } catch (e) {
      _dsLog('API', 'cancel ERROR | $e');
      handleError(e, loc);
    } finally {
      _busy = false;
    }
  }

  /// Satış başlatıldıktan sonra state'i günceller (start dialog'dan dönen değer).
  Future<void> startSale(
    int streamId, {
    int? listingId,
    String? title,
    double? price,
    int? stock,
    String? proofImageUrl,
    String? productImageUrl,
    required TranslationPack loc,
  }) async {
    _dsLog(
      'API',
      'startSale | streamId=$streamId mode=${listingId != null ? "listing($listingId)" : "manual"}'
      ' price=$price stock=$stock',
    );
    try {
      state = await DirectSaleService.startSale(
        streamId,
        listingId: listingId,
        title: title,
        price: price,
        stock: stock,
        proofImageUrl: proofImageUrl,
        productImageUrl: productImageUrl,
      );
      _dsLog('API', 'startSale OK | status=${state.status} saleId=${state.saleId}');
    } catch (e) {
      _dsLog('API', 'startSale ERROR | $e');
      handleError(e, loc);
    }
  }

  /// Dialog öncesi sipariş sayısını çekmek için kullanılır.
  Future<int> fetchOrderCount() async {
    try {
      final orders = await DirectSaleService.getOrders(state.saleId);
      return orders.length;
    } catch (_) {
      return 0;
    }
  }

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

/// Viewer purchase akışını yönetir.
/// Satış durumu için DirectSaleHostNotifier tek kaynak; bu notifier yalnızca
/// purchase işleminin loading/success/error geçişini tutar (T-2: no duplicate WS).
class DirectSaleViewerNotifier extends StateNotifier<DirectSaleViewerState> {
  DirectSaleViewerNotifier() : super(const DirectSaleViewerState());

  /// Satın alma işlemi — loading state + API çağrısı + hata yönetimi.
  Future<void> purchase(int saleId, int quantity, TranslationPack loc) async {
    _dsLog('PURCHASE', 'attempt | saleId=$saleId qty=$quantity');
    state = state.copyWith(purchaseStatus: ViewerPurchaseStatus.loading);
    try {
      await DirectSaleService.purchase(saleId, quantity: quantity);
      state = state.copyWith(purchaseStatus: ViewerPurchaseStatus.success);
      _dsLog('PURCHASE', 'OK | saleId=$saleId qty=$quantity');
    } catch (e) {
      _dsLog('PURCHASE', 'ERROR | saleId=$saleId $e');
      handleError(e, loc);
      state = state.copyWith(purchaseStatus: ViewerPurchaseStatus.idle);
    }
  }

  void resetPurchase() {
    state = state.copyWith(purchaseStatus: ViewerPurchaseStatus.idle);
  }
}

enum ViewerPurchaseStatus { idle, loading, success }

class DirectSaleViewerState {
  final ViewerPurchaseStatus purchaseStatus;

  const DirectSaleViewerState({
    this.purchaseStatus = ViewerPurchaseStatus.idle,
  });

  DirectSaleViewerState copyWith({ViewerPurchaseStatus? purchaseStatus}) =>
      DirectSaleViewerState(
        purchaseStatus: purchaseStatus ?? this.purchaseStatus,
      );

  bool get isLoading => purchaseStatus == ViewerPurchaseStatus.loading;
  bool get isPurchaseSuccess => purchaseStatus == ViewerPurchaseStatus.success;
}

final directSaleViewerProvider = StateNotifierProvider.family
    .autoDispose<DirectSaleViewerNotifier, DirectSaleViewerState, int>(
  (ref, _) => DirectSaleViewerNotifier(),
);

final directSaleDetailProvider = FutureProvider.family
    .autoDispose<DirectSaleSummary, int>((ref, saleId) async {
  return DirectSaleService.getSummary(saleId);
});

// listingId == 0 → listing filtresi yok (host geneli)
final directSaleSuggestionsProvider = FutureProvider.family
    .autoDispose<DirectSaleSuggestion, int>((ref, listingId) async {
  return DirectSaleService.getSuggestions(
    listingId: listingId > 0 ? listingId : null,
  );
});
