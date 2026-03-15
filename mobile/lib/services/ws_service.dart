import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/api.dart';
import 'storage_service.dart';

/// Uygulama genelinde tek bir WebSocket bağlantısı yönetir.
/// Mesajlar [messageStream] üzerinden broadcast edilir.
class WsService {
  WsService._();

  static WebSocketChannel? _channel;
  static StreamSubscription<dynamic>? _channelSub;
  static Timer? _pingTimer;
  static Timer? _reconnectTimer;
  static bool _shouldStay = false;

  /// Gelen WS mesajlarını tüm dinleyicilere iletir.
  static final StreamController<Map<String, dynamic>> messageStream =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Kullanıcı giriş yaptıktan sonra çağrılır.
  static Future<void> connect() async {
    _shouldStay = true;
    if (_channel != null) return;
    await _connect();
  }

  /// Kullanıcı çıkış yaptığında çağrılır.
  static void disconnect() {
    _shouldStay = false;
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _channelSub?.cancel();
    _channel?.sink.close();
    _channel = null;
  }

  static Future<void> _connect() async {
    final token = await StorageService.getToken();
    if (token == null) return;

    final wsBase = kBaseUrl
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');

    try {
      final uri = Uri.parse('$wsBase/messages/ws?token=$token');
      _channel = WebSocketChannel.connect(uri);

      _channelSub = _channel!.stream.listen(
        (raw) {
          if (raw is! String) return;
          if (raw == 'pong') return;
          try {
            final data = jsonDecode(raw) as Map<String, dynamic>;
            messageStream.add(data);
          } catch (_) {}
        },
        onDone: _onDisconnected,
        onError: (_) => _onDisconnected(),
        cancelOnError: true,
      );

      _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
        try {
          _channel?.sink.add('ping');
        } catch (_) {}
      });

      debugPrint('[WS] Bağlandı');
    } catch (_) {
      _channel = null;
      _scheduleReconnect();
    }
  }

  static void _onDisconnected() {
    _pingTimer?.cancel();
    _channelSub?.cancel();
    _channel = null;
    debugPrint('[WS] Bağlantı kesildi');
    if (_shouldStay) _scheduleReconnect();
  }

  static void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (_shouldStay) _connect();
    });
  }
}
