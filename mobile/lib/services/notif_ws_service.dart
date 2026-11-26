import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/network/api_client.dart';
import 'storage_service.dart';

final notifWsServiceProvider = Provider<NotifWsService>((ref) {
  final ws = NotifWsService(ref.watch(apiClientProvider));
  ref.onDispose(ws.dispose);
  return ws;
});

/// WS client for /api/notifications/ws.
/// Connects when user is logged in (foreground), disconnects on background.
/// Backend skips FCM when this WS is online; we show an in-app banner instead.
class NotifWsService with WidgetsBindingObserver {
  final ApiClient _api;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  bool _shouldStay = false;
  bool _connecting = false;
  bool _observerRegistered = false;

  final StreamController<Map<String, dynamic>> messageStream =
      StreamController<Map<String, dynamic>>.broadcast();

  NotifWsService(this._api);

  void connect() {
    _shouldStay = true;
    if (!_observerRegistered) {
      WidgetsBinding.instance.addObserver(this);
      _observerRegistered = true;
    }
    if (_channel == null) _connect();
  }

  void disconnect() {
    _shouldStay = false;
    if (_observerRegistered) {
      WidgetsBinding.instance.removeObserver(this);
      _observerRegistered = false;
    }
    _closeResources();
  }

  void dispose() {
    disconnect();
    messageStream.close();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _closeResources();
    } else if (state == AppLifecycleState.resumed) {
      if (_shouldStay && _channel == null) _connect();
    }
  }

  void _closeResources() {
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    _channel = null;
  }

  Future<void> _connect() async {
    if (_connecting || _channel != null) return;
    _connecting = true;

    final token = await StorageService.getToken();
    if (token == null) {
      _connecting = false;
      return;
    }

    final wsBase = _api.config.baseUrl
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');

    try {
      final uri = Uri.parse('$wsBase/notifications/ws');
      _channel = WebSocketChannel.connect(uri);
      _channel!.sink.add(jsonEncode({'token': token}));

      _sub = _channel!.stream.listen(
        (raw) {
          if (raw is! String || raw == 'pong') return;
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

      _connecting = false;
      debugPrint('[NOTIF_WS] Bağlandı');
    } catch (_) {
      _connecting = false;
      _channel = null;
      _scheduleReconnect();
    }
  }

  void _onDisconnected() {
    _closeResources();
    if (_shouldStay) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (_shouldStay && _channel == null) _connect();
    });
  }
}
