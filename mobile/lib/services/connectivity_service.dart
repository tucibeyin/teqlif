import 'dart:async' show Stream, StreamController, StreamSubscription;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Cihazın internete bağlı olup olmadığını anlık olarak takip eder.
class ConnectivityService {
  final Connectivity _connectivity = Connectivity();

  /// Her bağlantı değişikliğinde bool yayınlar: true = çevrimiçi.
  Stream<bool> get onConnectivityChanged => _connectivity.onConnectivityChanged
      .map((results) => _isOnline(results));

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
