import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Hive tabanlı anahtar-değer önbellek servisi.
///
/// Tasarım hedefleri:
///   • [getData] **senkron** — Hive kutusu uygulama başlangıcında bir kez
///     belleğe yüklenir; sonraki okumalar disk I/O beklemez.  Bu sayede
///     Riverpod provider'larının `build()` içindeki cache okuma adımı `await`
///     gerektirmez ve UI anında eski veriyi gösterir.
///   • [saveData] / [clearData] async — yazma işlemleri disk ile
///     senkronize edilir, UI thread'i bloke etmez.
///   • TTL desteği — her kayıt `{_d, _t, _x}` zarfıyla JSON string olarak
///     saklanır; böylece Hive'ın Map tip dönüşüm sorunları yaşanmaz.
///   • DIP — [cacheServiceProvider] aracılığıyla Riverpod'a enjekte edilir;
///     testlerde `ProviderContainer` ile mock subclass geçilebilir.
class CacheService {
  static const _boxName = 'api_cache';
  static late Box<String> _box;

  /// Uygulama başlangıcında (runApp öncesi) çağrılmalıdır.
  static Future<void> init() async {
    await Hive.initFlutter();
    _box = await Hive.openBox<String>(_boxName);
  }

  // ── Veri metodları (instance) ─────────────────────────────────────────────

  /// [key] için önbelleğe alınmış ham veriyi **senkron** olarak döner.
  ///
  /// TTL süresi dolmuşsa veya kayıt yoksa `null` döner.
  dynamic getData(String key) {
    final raw = _box.get(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map &&
          decoded.containsKey('_t') &&
          decoded.containsKey('_d')) {
        final savedAt = (decoded['_t'] as num).toInt();
        final ttlMs = (decoded['_x'] as num?)?.toInt() ?? 300000;
        final age = DateTime.now().millisecondsSinceEpoch - savedAt;
        if (age > ttlMs) return null;
        return decoded['_d'];
      }
      return decoded;
    } catch (_) {
      return null;
    }
  }

  /// Kayıt varsa veriyi ve bayatlık durumunu birlikte döner.
  ///
  /// TTL dolmuş olsa bile veriyi döndürür; [isStale] ile işaretler.
  /// Kayıt hiç yoksa `null` döner.
  ({dynamic data, bool isStale})? getWithStaleness(String key) {
    final raw = _box.get(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map &&
          decoded.containsKey('_t') &&
          decoded.containsKey('_d')) {
        final savedAt = (decoded['_t'] as num).toInt();
        final ttlMs = (decoded['_x'] as num?)?.toInt() ?? 300000;
        final age = DateTime.now().millisecondsSinceEpoch - savedAt;
        return (data: decoded['_d'], isStale: age > ttlMs);
      }
      return (data: decoded, isStale: false);
    } catch (_) {
      return null;
    }
  }

  /// [key] için kaydedilmiş ETag değerini senkron olarak döner.
  ///
  /// Cache kaydı yoksa veya ETag saklanmamışsa `null` döner.
  String? getEtag(String key) {
    final raw = _box.get(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return decoded['_e'] as String?;
    } catch (_) {}
    return null;
  }

  /// [data] (List veya Map) değerini [ttl] süreli TTL zarfıyla saklar.
  ///
  /// [etag] verilirse zarfa `_e` alanı olarak eklenir; sonraki isteklerde
  /// If-None-Match header'ı için [getEtag] ile okunur.
  Future<void> saveData(
    String key,
    dynamic data, {
    Duration ttl = const Duration(minutes: 5),
    String? etag,
  }) async {
    final wrapper = <String, dynamic>{
      '_d': data,
      '_t': DateTime.now().millisecondsSinceEpoch,
      '_x': ttl.inMilliseconds,
    };
    if (etag != null) wrapper['_e'] = etag;
    await _box.put(key, jsonEncode(wrapper));
  }

  /// Belirli bir [key] silerek ya da [key] verilmezse tüm kutuyu temizler.
  Future<void> clearData([String? key]) async {
    if (key != null) {
      await _box.delete(key);
    } else {
      await _box.clear();
    }
  }

  /// Süresi dolmuş tüm kayıtları siler (arka plan bakımı için).
  static Future<void> clearExpired() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final toDelete = <String>[];
    for (final key in _box.keys.cast<String>()) {
      final raw = _box.get(key);
      if (raw == null) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map && decoded.containsKey('_t')) {
          final age = now - (decoded['_t'] as num).toInt();
          final ttl = (decoded['_x'] as num?)?.toInt() ?? 300000;
          if (age > ttl) toDelete.add(key);
        }
      } catch (_) {
        toDelete.add(key);
      }
    }
    await _box.deleteAll(toDelete);

    // LRU kırpma: 200 anahtar limitini aşınca en eski kayıtları sil
    const maxKeys = 200;
    if (_box.length > maxKeys) {
      final entries = <MapEntry<String, int>>[];
      for (final key in _box.keys.cast<String>()) {
        final raw = _box.get(key);
        if (raw == null) continue;
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map && decoded.containsKey('_t')) {
            entries.add(MapEntry(key, (decoded['_t'] as num).toInt()));
          }
        } catch (_) {}
      }
      entries.sort((a, b) => a.value.compareTo(b.value));
      final keysToDelete = entries
          .take(_box.length - maxKeys)
          .map((e) => e.key)
          .toList();
      await _box.deleteAll(keysToDelete);
    }
  }
}

final cacheServiceProvider = Provider<CacheService>((_) => CacheService());
