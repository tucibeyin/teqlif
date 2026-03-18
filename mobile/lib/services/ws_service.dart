import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart'; // Lifecycle dinleyicisi için eklendi
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/api.dart';
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

  // Lifecycle dinleyicisi tanımlamaları
  static final _WsLifecycleObserver _observer = _WsLifecycleObserver();
  static bool _isObserverRegistered = false;

  /// Gelen WS mesajlarını tüm dinleyicilere iletir.
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

    if (_channel != null) return;
    await _connect();
  }

  /// Kullanıcı çıkış yaptığında çağrılır.
  static void disconnect() {
    _shouldStay = false;
    
    // Çıkış yapıldığında Observer'ı kaldır
    if (_isObserverRegistered) {
      WidgetsBinding.instance.removeObserver(_observer);
      _isObserverRegistered = false;
    }
    
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