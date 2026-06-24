import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import 'storage_service.dart';

/// Canlı yayın akışındaki video ilan davranışlarını (impression/skip/click)
/// toplu olarak backend'e gönderen singleton servis.
///
/// Kullanım:
///   FeedTelemetryService.instance.logEvent(
///     listingId: '42', eventType: 'impression', dwellTimeMs: 1800,
///   );
///
/// Servis başlatma (main.dart veya app widget'ı içinde bir kez):
///   FeedTelemetryService.instance.init();
class FeedTelemetryService with WidgetsBindingObserver {
  FeedTelemetryService._();
  static final FeedTelemetryService instance = FeedTelemetryService._();

  static const int _flushThreshold = 5;
  static const String _endpoint = '$kBaseUrl/analytics/feed-events';

  final List<Map<String, dynamic>> _eventQueue = [];
  bool _flushing = false;

  /// Uygulama başlangıcında bir kez çağrılmalı.
  void init() {
    WidgetsBinding.instance.addObserver(this);
  }

  /// Uygulama yaşam döngüsü değişimlerini dinle — arka plana geçince flush yap.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      flush();
    }
  }

  /// Olayı kuyruğa ekler; eleman sayısı eşiğe ulaşırsa otomatik flush tetikler.
  void logEvent({
    required String listingId,
    required String eventType,
    required int dwellTimeMs,
    String contentType = 'video',
    int slotIndex = 0,
    String streamCategory = '',
  }) {
    _eventQueue.add({
      'listing_id': listingId,
      'event_type': eventType,
      'dwell_time_ms': dwellTimeMs,
      'content_type': contentType,
      'slot_index': slotIndex,
      'stream_category': streamCategory,
    });
    if (_eventQueue.length >= _flushThreshold) {
      flush();
    }
  }

  /// Kuyruktaki tüm olayları backend'e gönderir ve kuyruğu temizler.
  /// UI'ı bloke etmez; hata olursa sadece loglar.
  void flush() {
    if (_eventQueue.isEmpty || _flushing) return;
    _flushing = true;

    final batch = List<Map<String, dynamic>>.from(_eventQueue);
    _eventQueue.clear();

    _send(batch).whenComplete(() => _flushing = false);
  }

  Future<void> _send(List<Map<String, dynamic>> events) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return;

      await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'events': events}),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Ağ hatası veya timeout — olaylar sessizce atılır, UI etkilenmez.
    }
  }

  /// Observer'ı kaldır (genellikle gerekmez — singleton ömrü app ile aynı).
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }
}
