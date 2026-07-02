import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'connectivity_service.dart';
import 'notification_service.dart';

/// Çevrimdışı DM mesaj kuyruğu.
///
/// Kullanıcı mesaj gönderirken internet yoksa (veya API başarısız olursa),
/// mesaj Hive kutusuna yazılır. İnternet geri gelince [drain] otomatik olarak
/// kuyruktaki mesajları sırayla gönderir ve başarılı olanları siler.
class OfflineQueueService {
  OfflineQueueService._();

  static const _boxName = 'offline_messages_queue';
  static Box<String>? _box;

  /// Hive kutusunu açar — [main.dart]'ta [CacheService.init()] ile birlikte çağrılmalı.
  static Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
  }

  /// Mesajı kuyruğa ekler; benzersiz [localId] döner.
  static Future<String> enqueue(int receiverId, String content, {int? listingId}) async {
    final localId = 'q_${DateTime.now().millisecondsSinceEpoch}';
    final data = {
      'local_id': localId,
      'receiver_id': receiverId,
      'content': content,
      'queued_at': DateTime.now().millisecondsSinceEpoch,
      if (listingId != null) 'listing_id': listingId,
    };
    await _box?.put(localId, jsonEncode(data));
    debugPrint('[OfflineQueue] enqueue: localId=$localId receiver=$receiverId');
    return localId;
  }

  /// [receiverId] için bekleyen mesajları döner (senkron — Hive bellekten okur).
  static List<Map<String, dynamic>> getPendingForReceiver(int receiverId) {
    final box = _box;
    if (box == null) return [];
    return box.values
        .map((v) {
          try {
            return jsonDecode(v) as Map<String, dynamic>;
          } catch (_) {
            return null;
          }
        })
        .whereType<Map<String, dynamic>>()
        .where((m) => (m['receiver_id'] as int?) == receiverId)
        .toList();
  }

  /// [localId]'yi kuyruktan siler.
  static Future<void> remove(String localId) async {
    await _box?.delete(localId);
  }

  /// Kuyruktaki tüm mesajları sırayla gönderir.
  /// Başarılı olan her mesaj kuyruktan silinir; başarısız olanlar bir sonraki
  /// drain'e kalır.
  static Future<void> drain() async {
    final box = _box;
    if (box == null || box.isEmpty) return;
    debugPrint('[OfflineQueue] drain başladı — ${box.length} bekleyen mesaj');

    final entries = Map<String, String>.from(
      box.toMap().cast<String, String>(),
    );

    for (final kv in entries.entries) {
      try {
        final data = jsonDecode(kv.value) as Map<String, dynamic>;
        final receiverId = data['receiver_id'] as int;
        final content    = data['content'] as String;
        final listingId  = data['listing_id'] as int?;
        final ok = await NotificationService.sendMessage(receiverId, content, listingId: listingId);
        if (ok) {
          await box.delete(kv.key);
          debugPrint('[OfflineQueue] gönderildi + silindi: ${kv.key}');
        }
      } catch (e) {
        debugPrint('[OfflineQueue] drain hatası (${kv.key}): $e');
      }
    }
  }

  // ── Connectivity → auto-drain bağlantısı ──────────────────────────────────

  static StreamSubscription<bool>? _connectSub;

  /// Uygulama başlangıcında [main.dart]'ta bir kez çağrılır.
  /// Cihaz çevrimiçi olduğunda kuyruktaki mesajları otomatik gönderir.
  static void startDrainOnReconnect() {
    _connectSub?.cancel();
    bool _wasOnline = true; // optimistik başlangıç

    final svc = ConnectivityService();
    // Anlık durumu öğren
    svc.isConnected.then((online) => _wasOnline = online);

    _connectSub = svc.onConnectivityChanged.listen((online) {
      if (online && !_wasOnline) {
        debugPrint('[OfflineQueue] İnternet geri geldi — drain tetiklendi');
        drain();
      }
      _wasOnline = online;
    });
  }
}
