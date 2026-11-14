import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Cihazın internete bağlı olup olmadığını anlık olarak takip eder.
class ConnectivityService {
  final Connectivity _connectivity = Connectivity();
  static bool isDeviceOnline = true;

  ConnectivityService() {
    _connectivity.checkConnectivity().then((res) => isDeviceOnline = _isOnline(res));
  }

  // iOS, WiFi→mobile geçişinde aynı saniyede 10+ connectivity event atar.
  // Debounce bu platform davranışını servis katmanında soyutlar; dinleyiciler
  // platform quirk'inden habersiz, sadece nihai durumu alır.
  Stream<bool>? _debounced;

  /// Her bağlantı değişikliğinde bool yayınlar: true = çevrimiçi.
  /// Debounced (300ms): iOS geçiş sırasında gelen rapid event'ler birleştirilir.
  Stream<bool> get onConnectivityChanged => _debounced ??= _buildDebounced();

  Stream<bool> _buildDebounced() {
    final controller = StreamController<bool>.broadcast();
    Timer? timer;
    _connectivity.onConnectivityChanged.listen((results) {
      final online = _isOnline(results);
      isDeviceOnline = online;
      timer?.cancel();
      timer = Timer(const Duration(milliseconds: 300), () => controller.add(online));
    });
    return controller.stream;
  }

  /// Anlık bağlantı durumunu döner.
  Future<bool> get isConnected async {
    final results = await _connectivity.checkConnectivity();
    return _isOnline(results);
  }

  bool _isOnline(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);
}

// ── Riverpod provider'ları ───────────────────────────────────────────────────

/// ConnectivityService singleton'ı.
final connectivityServiceProvider = Provider<ConnectivityService>(
  (_) => ConnectivityService(),
);

/// Anlık bağlantı durumu: true = çevrimiçi, false = çevrimdışı.
/// `ref.watch(isConnectedProvider)` ile her yerden dinlenebilir.
final isConnectedProvider = StreamProvider<bool>((ref) {
  final svc = ref.watch(connectivityServiceProvider);
  // Mevcut durumu ilk değer olarak yayınla, sonra değişimleri dinle
  final controller = StreamController<bool>();
  svc.isConnected.then(controller.add);
  final sub = svc.onConnectivityChanged.listen(controller.add);
  ref.onDispose(() {
    sub.cancel();
    controller.close();
  });
  return controller.stream;
});
