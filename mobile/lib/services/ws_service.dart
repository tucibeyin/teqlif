import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart'; // Lifecycle dinleyicisi için eklendi
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../config/api.dart';
import 'auth_service.dart';
import 'storage_service.dart';

/// Uygulamanın arka plan/ön plan durumunu dinleyen özel sınıf
class _WsLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      debugPrint('[WS] Uygulama arka planda, soket bekletiliyor...');
      WsService.pauseConnection();
    } else if (state == AppLifecycleState.resumed) {
      debugPrint('[WS] Uygulama ön planda, yeniden bağlanılıyor...');
      WsService.resumeConnection();
    }
  }
}

/// Uygulama genelinde tek bir WebSocket bağlantısı yönetir.
/// Mesajlar [messageStream] üzerinden broadcast edilir.
class WsService {
  WsService._();

  static WebSocketChannel? _channel;
  static StreamSubscription<dynamic>? _channelSub;
  static Timer? _pingTimer;
  static Timer? _reconnectTimer;
  static bool _shouldStay = false;
  static bool _connecting = false;
  static StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  // Lifecycle dinleyicisi tanımlamaları
  static final _WsLifecycleObserver _observer = _WsLifecycleObserver();
  static bool _isObserverRegistered = false;

  /// Gelen WS mesajlarını tüm dinleyicilere iletir.
  /// Özel dahili event'ler de bu stream üzerinden gider:
  ///   {"type": "connected"}  — WS başarıyla (yeniden) bağlandı
  static final StreamController<Map<String, dynamic>> messageStream =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Kullanıcı giriş yaptıktan sonra çağrılır.
  static Future<void> connect() async {
    _shouldStay = true;
    
    // Observer daha önce kaydedilmediyse kaydet
    if (!_isObserverRegistered) {
      WidgetsBinding.instance.addObserver(_observer);
      _isObserverRegistered = true;
    }

    _connectivitySub ??= Connectivity().onConnectivityChanged.listen((results) {
      if (results.contains(ConnectivityResult.none)) {
        debugPrint('[WS] İnternet bağlantısı kesildi, arka plan denemeleri durduruluyor.');
        _closeResources();
      } else {
        debugPrint('[WS] Ağ bağlantısı aktifleştirildi (${results.first.name}), hızlı yeniden bağlanılıyor...');
        if (_shouldStay && _channel == null) {
          _connect();
        }
      }
    });

    if (_channel != null) return;
    await _connect();
  }

  /// WS üzerinden JSON mesajı gönderir (typing event gibi).
  static void sendJson(Map<String, dynamic> data) {
    try {
      debugPrint('[CALL_FLOW] [WS] Sending message: $data');
      _channel?.sink.add(jsonEncode(data));
    } catch (_) {}
  }

  /// Kullanıcı çıkış yaptığında çağrılır.
  static void disconnect() {
    _shouldStay = false;
    
    // Çıkış yapıldığında Observer'ı kaldır
    if (_isObserverRegistered) {
      WidgetsBinding.instance.removeObserver(_observer);
      _isObserverRegistered = false;
    }

    _connectivitySub?.cancel();
    _connectivitySub = null;
    
    _closeResources();
  }

  /// İşletim sistemi uygulamayı arka plana attığında çağrılır
  static void pauseConnection() {
    // Çıkış yapılmış gibi tamamen silmeyiz, sadece soketi kapatırız.
    // _shouldStay = true olarak kalır ki öne gelince tekrar bağlansın.
    _closeResources();
  }

  /// Uygulama tekrar ekrana geldiğinde çağrılır
  static void resumeConnection() {
    // Eğer kullanıcı çıkış yapmamışsa tekrar bağlan
    if (_shouldStay && _channel == null) {
      _connect();
    }
  }

  /// Tüm zamanlayıcıları ve soketleri güvenli bir şekilde temizler
  static void _closeResources() {
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _channelSub?.cancel();
    _channel?.sink.close();
    _channel = null;
  }

  static Future<void> _connect() async {
    if (_connecting || _channel != null) return;
    _connecting = true;
    final token = await StorageService.getToken();
    if (token == null || _channel != null) {
      _connecting = false;
      return;
    }

    final wsBase = kBaseUrl
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');

    try {
      final uri = Uri.parse('$wsBase/messages/ws');
      _channel = WebSocketChannel.connect(uri);
      // Token URL'de taşınmaz — bağlantı açılır açılmaz ilk mesaj olarak gönderilir
      _channel!.sink.add(jsonEncode({'type': 'auth', 'token': token}));

      _channelSub = _channel!.stream.listen(
        (raw) {
          if (raw is! String) return;
          if (raw == 'pong') return;
          try {
            debugPrint('[CALL_FLOW] [WS] Received message: $raw');
            final data = jsonDecode(raw) as Map<String, dynamic>;
            messageStream.add(data);
          } catch (_) {}
        },
        onDone: _onDisconnected,
        onError: (error) {
          final errStr = error.toString();
          // SENTRY ÇÖZÜMÜ: İşletim sisteminin attığı sahte fatal hataları filtrele
          if (errStr.contains('Bad file descriptor') || errStr.contains('errno = 9')) {
            debugPrint('[WS] OS tarafından soket kapatıldı (Normal davranış).');
          } else {
            debugPrint('[WS] Beklenmeyen Hata: $error');
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

      // Dinleyicilere "bağlandı" sinyali — DirectChatScreen kaçırılan mesajları çeker
      messageStream.add({'type': 'connected'});
      _connecting = false;
      debugPrint('[WS] Bağlandı');
    } catch (_) {
      _connecting = false;
      _channel = null;
      _scheduleReconnect();
    }
  }

  static void _onDisconnected() {
    final closeCode = _channel?.closeCode;
    _pingTimer?.cancel();
    _channelSub?.cancel();
    _channel = null;
    _connecting = false;
    debugPrint('[WS] Bağlantı kesildi (code: $closeCode)');
    if (!_shouldStay) return;
    if (closeCode == 4001) {
      _refreshAndReconnect();
    } else if (closeCode == 4008) {
      // Sunucu session limitini aştı — 15 sn bekle, döngüden kaç
      _scheduleReconnect(delay: const Duration(seconds: 15));
    } else {
      _scheduleReconnect();
    }
  }

  static Future<void> _refreshAndReconnect() async {
    final ok = await AuthService.tryRefresh();
    if (ok) {
      debugPrint('[WS] Token yenilendi, yeniden bağlanılıyor');
      _scheduleReconnect();
    } else {
      debugPrint('[WS] Token yenilenemedi, yeniden bağlanılmayacak');
      _shouldStay = false;
    }
  }

  static void _scheduleReconnect({Duration delay = const Duration(seconds: 3)}) {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () async {
      if (!_shouldStay || _channel != null) return;
      final results = await Connectivity().checkConnectivity();
      if (results.contains(ConnectivityResult.none)) {
        debugPrint('[WS] (Bekleme) İnternet yok, bağlantı tetiklenmeyecek.');
        return;
      }
      _connect();
    });
  }
}