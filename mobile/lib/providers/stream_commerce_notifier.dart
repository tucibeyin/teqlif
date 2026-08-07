import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/api.dart';
import '../services/storage_service.dart';

/// Tüm commerce ViewModel'leri için ortak WS altyapısı.
///
/// Alt sınıf yalnızca [onCommerceEvent] metodunu implement eder.
/// WS bağlantısı, heartbeat ve exponential backoff reconnect buraya aittir.
///
/// ÖNEMLİ: [DirectSaleViewerNotifier] bu sınıfı extend ETMEZ.
/// Viewer WS bağlantısı açmaz; state'i host notifier üzerinden gelir.
abstract class StreamCommerceNotifier<S> extends StateNotifier<S> {
  final int streamId;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _heartbeat;
  bool _reconnecting = false;
  int _reconnectAttempt = 0;

  StreamCommerceNotifier(this.streamId, S initialState) : super(initialState) {
    unawaited(_connect());
  }

  String get _wsBase => kBaseUrl
      .replaceFirst('https://', 'wss://')
      .replaceFirst('http://', 'ws://');

  /// Alt sınıf her gelen WS event'i bu metod üzerinden alır.
  /// Kendi domain'iyle ilgili olmayan event tiplerini [return] ile atar.
  void onCommerceEvent(String type, Map<String, dynamic> json);

  Future<void> _connect() async {
    _heartbeat?.cancel();
    final token = await StorageService.getToken();
    _wsLog('connecting | streamId=$streamId attempt=$_reconnectAttempt');
    try {
      final uri = Uri.parse('$_wsBase/auction/$streamId/ws');
      _channel = WebSocketChannel.connect(uri);
      if (token != null) {
        _channel!.sink.add(jsonEncode({'token': token}));
        _wsLog('connected, auth sent | streamId=$streamId');
      } else {
        _wsLog('connected, anonymous | streamId=$streamId');
      }
      _reconnectAttempt = 0;
      _sub = _channel!.stream.listen(
        _onRaw,
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
        cancelOnError: false,
      );
      _heartbeat = Timer.periodic(const Duration(seconds: 25), (_) {
        try { _channel?.sink.add('ping'); } catch (_) {}
      });
    } catch (e) {
      _wsLog('connect error | streamId=$streamId $e');
      _scheduleReconnect();
    }
  }

  void _onRaw(dynamic data) {
    try {
      final json = jsonDecode(data as String) as Map<String, dynamic>;
      final type = json['type'] as String?;
      if (type == null || type.isEmpty) return;
      onCommerceEvent(type, json);
    } catch (e) {
      _wsLog('parse error | streamId=$streamId $e');
    }
  }

  void _scheduleReconnect() {
    if (_reconnecting) return;
    _reconnecting = true;
    _heartbeat?.cancel();
    final delayMs = (1000 * pow(1.5, _reconnectAttempt)).clamp(1000, 60000).toInt();
    _reconnectAttempt++;
    _wsLog('reconnect scheduled | delay=${delayMs}ms attempt=$_reconnectAttempt streamId=$streamId');
    Future.delayed(Duration(milliseconds: delayMs), () {
      if (!mounted) return;
      _reconnecting = false;
      _sub?.cancel();
      try { _channel?.sink.close(); } catch (_) {}
      unawaited(_connect());
    });
  }

  void _wsLog(String msg) {
    debugPrint('[COMMERCE][${DateTime.now().toIso8601String()}][WS] $msg');
  }

  @override
  void dispose() {
    _reconnecting = false;
    _heartbeat?.cancel();
    _sub?.cancel();
    try { _channel?.sink.close(); } catch (_) {}
    _wsLog('disposed | streamId=$streamId type=${runtimeType}');
    super.dispose();
  }
}
