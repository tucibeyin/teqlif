import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_client.dart';
import 'auth_service.dart' show authServiceProvider, AuthService, RefreshOutcome;
import 'storage_service.dart';

final wsServiceProvider = Provider<WsService>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  final authService = ref.watch(authServiceProvider);
  final ws = WsService(apiClient, authService);
  
  ref.onDispose(() {
    ws.dispose();
  });
  
  return ws;
});

class WsService with WidgetsBindingObserver {
  final ApiClient _api;
  final AuthService _authService;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _channelSub;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  bool _shouldStay = false;
  bool _connecting = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  
  double? _lastCallEventTs;
  Timer? _lifecycleDebounce;
  AppLifecycleState? _pendingLifecycleState;

  int _connectionLocks = 0;
  bool _pendingPause = false;

  final Set<String> _seenKeys = {};
  static const int _maxSeenKeys = 200;

  final StreamController<Map<String, dynamic>> messageStream =
      StreamController<Map<String, dynamic>>.broadcast();

  bool _isObserverRegistered = false;

  WsService(this._api, this._authService);

  String? _dedupeKey(Map<String, dynamic> data) {
    final type = data['type'];
    if (type == null) return null;
    final id = data['id'];
    if (id != null) return '${type}_$id';
    final callId = data['call_id'];
    if (callId != null) return '${type}_$callId';
    return null;
  }

  void _debounceLifecycle(AppLifecycleState state) {
    _pendingLifecycleState = state;
    _lifecycleDebounce?.cancel();
    _lifecycleDebounce = Timer(const Duration(milliseconds: 200), () {
      final s = _pendingLifecycleState;
      if (s == null) return;
      if (s == AppLifecycleState.paused ||
          s == AppLifecycleState.inactive ||
          s == AppLifecycleState.hidden) {
        debugPrint('[WS][${DateTime.now().toIso8601String()}] Uygulama arka planda, soket bekletiliyor...');
        pauseConnection();
      } else if (s == AppLifecycleState.resumed) {
        debugPrint('[WS][${DateTime.now().toIso8601String()}] Uygulama ön planda, yeniden bağlanılıyor...');
        resumeConnection();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _debounceLifecycle(state);
  }

  Future<void> connect() async {
    _shouldStay = true;
    
    if (!_isObserverRegistered) {
      WidgetsBinding.instance.addObserver(this);
      _isObserverRegistered = true;
    }

    _connectivitySub ??= Connectivity().onConnectivityChanged.listen((results) {
      if (results.contains(ConnectivityResult.none)) {
        debugPrint('[WS][${DateTime.now().toIso8601String()}] İnternet bağlantısı kesildi, arka plan denemeleri durduruluyor.');
        _closeResources();
      } else {
        debugPrint('[WS][${DateTime.now().toIso8601String()}] Ağ bağlantısı aktifleştirildi (${results.first.name}), hızlı yeniden bağlanılıyor...');
        if (_shouldStay && _channel == null) {
          _connect();
        }
      }
    });

    if (_channel != null) return;
    await _connect();
  }

  void sendJson(Map<String, dynamic> data) {
    try {
      _channel?.sink.add(jsonEncode(data));
    } catch (_) {}
  }

  void disconnect() {
    _shouldStay = false;
    
    if (_isObserverRegistered) {
      WidgetsBinding.instance.removeObserver(this);
      _isObserverRegistered = false;
    }

    _connectivitySub?.cancel();
    _connectivitySub = null;
    _lastCallEventTs = null;
    _seenKeys.clear();

    _closeResources();
  }

  void acquireConnectionLock(String reason) {
    _connectionLocks++;
    debugPrint('[WS][LOCK][${DateTime.now().toIso8601String()}] acquired ($reason) | locks=$_connectionLocks');
  }

  void releaseConnectionLock(String reason) {
    _connectionLocks = (_connectionLocks - 1).clamp(0, 999);
    debugPrint('[WS][LOCK][${DateTime.now().toIso8601String()}] released ($reason) | locks=$_connectionLocks');
    if (_connectionLocks == 0 && _pendingPause) {
      _pendingPause = false;
      debugPrint('[WS][LOCK][${DateTime.now().toIso8601String()}] executing deferred pauseConnection');
      _closeResources();
    }
  }

  void pauseConnection() {
    if (_connectionLocks > 0) {
      _pendingPause = true;
      debugPrint('[WS][LOCK][${DateTime.now().toIso8601String()}] pauseConnection DEFERRED | locks=$_connectionLocks');
      return;
    }
    _pendingPause = false;
    _closeResources();
  }

  void resumeConnection() {
    _pendingPause = false;
    if (_shouldStay && _channel == null) {
      _connect();
    }
  }

  void dispose() {
    disconnect();
    messageStream.close();
  }

  void _closeResources() {
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _channelSub?.cancel();
    _channel?.sink.close();
    _channel = null;
  }

  Future<void> _connect() async {
    if (_connecting || _channel != null) return;
    _connecting = true;
    final token = await StorageService.getToken();
    if (token == null || _channel != null) {
      _connecting = false;
      return;
    }

    final wsBase = _api.config.baseUrl
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');

    try {
      final uri = Uri.parse('$wsBase/messages/ws');
      _channel = WebSocketChannel.connect(uri);
      
      _lastCallEventTs ??= DateTime.now().millisecondsSinceEpoch / 1000.0 - 5.0;
      final authMsg = <String, dynamic>{'type': 'auth', 'token': token};
      if (_lastCallEventTs != null) authMsg['since_ts'] = _lastCallEventTs;
      _channel!.sink.add(jsonEncode(authMsg));

      _channelSub = _channel!.stream.listen(
        (raw) {
          if (raw is! String) return;
          if (raw == 'pong') return;
          try {
            final data = jsonDecode(raw) as Map<String, dynamic>;
            final type = data['type'] as String?;

            final key = _dedupeKey(data);
            if (key != null) {
              if (_seenKeys.contains(key)) {
                debugPrint('[WS][DEDUP] Duplikat atlandı: $key');
                return;
              }
              _seenKeys.add(key);
              if (_seenKeys.length > _maxSeenKeys) {
                _seenKeys.remove(_seenKeys.first);
              }
            }

            if (type != null && type.startsWith('call_')) {
              debugPrint('[LIVE_SCREEN_CALL][${DateTime.now().toIso8601String()}] WsService received message type: $type');
              _lastCallEventTs = DateTime.now().millisecondsSinceEpoch / 1000.0;
              if (type == 'call_incoming') {
                final callId = data['call_id'];
                if (callId != null) {
                  sendJson({'type': 'call_incoming_ack', 'call_id': callId});
                  debugPrint('[LIVE_SCREEN_CALL][${DateTime.now().toIso8601String()}] WsService sent call_incoming_ack | call_id=$callId');
                }
              }
            }
            messageStream.add(data);
          } catch (_) {}
        },
        onDone: _onDisconnected,
        onError: (error) {
          final errStr = error.toString();
          if (errStr.contains('Bad file descriptor') || errStr.contains('errno = 9')) {
            debugPrint('[WS][${DateTime.now().toIso8601String()}] OS tarafından soket kapatıldı (Normal davranış).');
          } else {
            debugPrint('[WS][${DateTime.now().toIso8601String()}] Beklenmeyen Hata: $error');
          }
          _onDisconnected();
        },
        cancelOnError: true,
      );

      _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
        try {
          _channel?.sink.add('ping');
        } catch (_) {}
      });

      messageStream.add({'type': 'connected'});
      _connecting = false;
      debugPrint('[WS][${DateTime.now().toIso8601String()}] Bağlandı');
    } catch (_) {
      _connecting = false;
      _channel = null;
      _scheduleReconnect();
    }
  }

  void _onDisconnected() {
    final closeCode = _channel?.closeCode;
    _pingTimer?.cancel();
    _channelSub?.cancel();
    _channel = null;
    _connecting = false;
    debugPrint('[WS][${DateTime.now().toIso8601String()}] Bağlantı kesildi (code: $closeCode)');
    if (!_shouldStay) return;
    if (closeCode == 4001) {
      _refreshAndReconnect();
    } else if (closeCode == 4008) {
      _scheduleReconnect(delay: const Duration(seconds: 15));
    } else {
      _scheduleReconnect();
    }
  }

  Future<void> _refreshAndReconnect() async {
    final outcome = await _authService.tryRefresh();
    if (outcome == RefreshOutcome.succeeded) {
      debugPrint('[WS][${DateTime.now().toIso8601String()}] Token yenilendi, yeniden bağlanılıyor');
      _scheduleReconnect();
    } else {
      debugPrint('[WS][${DateTime.now().toIso8601String()}] Token yenilenemedi ($outcome), yeniden bağlanılmayacak');
      _shouldStay = false;
    }
  }

  void _scheduleReconnect({Duration delay = const Duration(seconds: 3)}) {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () async {
      if (!_shouldStay || _channel != null) return;
      final results = await Connectivity().checkConnectivity();
      if (results.contains(ConnectivityResult.none)) {
        debugPrint('[WS][${DateTime.now().toIso8601String()}] (Bekleme) İnternet yok, bağlantı tetiklenmeyecek.');
        return;
      }
      _connect();
    });
  }
}