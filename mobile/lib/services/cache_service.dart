import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
  static const _boxName            = 'api_cache';
  // §12.8 — version bump'ı entity store formatına geçişi tetikler.
  static const _kApiCacheVersion   = 2;
  static const _kVersionKey        = '__api_cache_v';
  // CACHE-01 — AES-256 şifreleme anahtarı adı (Android Keystore / iOS Keychain)
  static const _kEncryptionKeyName = 'teqlif_hive_encryption_key';
  // CACHE-11: 200 anahtar limiti ve her 20 yazmada arka plan tahliyesi
  static const _kMaxKeys       = 200;
  static const _kEvictInterval = 20;
  static late Box<String> _box;
  // LRU: son erişim zamanını in-memory tutar; senkron read sözleşmesini bozmaz.
  static final Map<String, int> _lastRead = {};
  static int _writeCount = 0;

  /// Uygulama başlangıcında (runApp öncesi) çağrılmalıdır.
  static Future<void> init() async {
    await Hive.initFlutter();
    final keyBytes = await _getOrCreateEncryptionKey();
    try {
      _box = await Hive.openBox<String>(
        _boxName,
        encryptionCipher: HiveAesCipher(keyBytes),
      );
    } catch (_) {
      // Eski şifresiz box → sil ve şifreli olarak yeniden aç.
      // Mevcut stale cache temizlenir; uygulama açılışında SWR ile yeniden dolar.
      await Hive.deleteBoxFromDisk(_boxName);
      _box = await Hive.openBox<String>(
        _boxName,
        encryptionCipher: HiveAesCipher(keyBytes),
      );
    }
    await _migrate();
  }

  /// Android Keystore / iOS Keychain'de saklanan 256-bit AES anahtarını döner.
  /// İlk çalıştırmada rastgele üretir ve güvenli depoya yazar.
  ///
  /// Android Keystore transient-null koruması: Doze modu veya bazı OEM
  /// uygulamalarında var olan anahtar tek bir okumada null dönebilir. Üç
  /// denemede null gelirse gerçekten yoktur; yeni anahtar üretilir.
  static Future<List<int>> _getOrCreateEncryptionKey() async {
    const secureStorage = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
      iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    );
    String? existing;
    for (var i = 0; i < 3; i++) {
      try {
        existing = await secureStorage.read(key: _kEncryptionKeyName);
        if (existing != null) break;
      } catch (_) {}
      if (i < 2) await Future.delayed(const Duration(milliseconds: 50));
    }
    if (existing != null) return base64Decode(existing);
    final key = Hive.generateSecureKey();
    await secureStorage.write(
      key: _kEncryptionKeyName,
      value: base64Encode(key),
    );
    return key;
  }

  /// Logout anında api_cache'i temizler.
  ///
  /// Box zaten şifreli ve açık olduğundan doğrudan `.clear()` çağrılır;
  /// StorageService'in Hive.openBox('api_cache') ile şifresiz açmasına gerek kalmaz.
  static Future<void> clearBox() async {
    await _box.clear();
    _lastRead.clear();
  }

  static Future<void> _migrate() async {
    final stored = int.tryParse(_box.get(_kVersionKey) ?? '0') ?? 0;
    if (stored < _kApiCacheVersion) {
      await _box.clear();
      _lastRead.clear();
      await _box.put(_kVersionKey, _kApiCacheVersion.toString());
    }
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
        _lastRead[key] = DateTime.now().millisecondsSinceEpoch;
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
        _lastRead[key] = DateTime.now().millisecondsSinceEpoch;
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
    _lastRead[key] = DateTime.now().millisecondsSinceEpoch;
    // CACHE-11: her _kEvictInterval yazışta arka planda TTL+LRU tahliyesi
    if (++_writeCount % _kEvictInterval == 0) clearExpired().ignore();
  }

  /// Belirli bir [key] silerek ya da [key] verilmezse tüm kutuyu temizler.
  Future<void> clearData([String? key]) async {
    if (key != null) {
      await _box.delete(key);
      _lastRead.remove(key);
    } else {
      await _box.clear();
      _lastRead.clear();
    }
  }

  // ── §12.8 Entity Store ────────────────────────────────────────────────────────

  /// Listing / user entity'sini api_cache'e yazar.
  Future<void> saveEntity(
    String type,
    int id,
    Map<String, dynamic> data, {
    Duration ttl = const Duration(hours: 2),
  }) =>
      saveData('entity_${type}_$id', data, ttl: ttl);

  /// Entity'yi senkron olarak okur; yoksa ya da bayatsa null.
  Map<String, dynamic>? getEntity(String type, int id) =>
      getData('entity_${type}_$id') as Map<String, dynamic>?;

  /// api_cache box'unu tamamen temizler (migration için).
  Future<void> clearAll() async {
    await _box.clear();
    _lastRead.clear();
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
    for (final k in toDelete) { _lastRead.remove(k); }

    // CACHE-11: LRU kırpma — sırala: son erişim zamanı (in-memory), yoksa oluşturma zamanı
    if (_box.length > _kMaxKeys) {
      final entries = <MapEntry<String, int>>[];
      for (final key in _box.keys.cast<String>()) {
        final raw = _box.get(key);
        if (raw == null) continue;
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map && decoded.containsKey('_t')) {
            final lruTime = _lastRead[key] ?? (decoded['_t'] as num).toInt();
            entries.add(MapEntry(key, lruTime));
          }
        } catch (_) {}
      }
      entries.sort((a, b) => a.value.compareTo(b.value));
      final keysToDelete = entries
          .take(_box.length - _kMaxKeys)
          .map((e) => e.key)
          .toList();
      await _box.deleteAll(keysToDelete);
      for (final k in keysToDelete) { _lastRead.remove(k); }
    }
  }
}

final cacheServiceProvider = Provider<CacheService>((_) => CacheService());

/// §12.8 — Entity'yi api_cache'den senkron okur.
final entityProvider = Provider.family<Map<String, dynamic>?, (String, int)>(
  (ref, args) => ref.watch(cacheServiceProvider).getEntity(args.$1, args.$2),
);
