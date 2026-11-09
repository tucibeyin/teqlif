import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../core/network/api_client.dart';
import '../core/app_exception.dart';
import 'cache_service.dart';
import 'storage_service.dart';

/// Stale-While-Revalidate (SWR) mantığını uygulayan merkezi GET yardımcısı.
///
/// [get] bir `Stream<T>` üretir:
///   1. **Anında (sync):** [cacheKey] varsa Hive'dan eski veri okunur ve
///      hemen yayılır (emit); UI sıfır gecikmeyle eski veriyi gösterir.
///   2. **Arka planda (async):** HTTP isteği atılır; başarılı yanıt gelince
///      cache güncellenir ve taze veri yayılır; UI sessizce güncellenir.
///   3. **Hata yönetimi:** cache yayılmışsa ağ hataları yutulur (kullanıcı
///      eski veriyi görmeye devam eder). Cache yoksa hata fırlatılır.
///
/// Kullanım örneği (Riverpod provider):
/// ```dart
/// await for (final items in ApiService.get<List<Foo>>(
///   url: '${ref.read(apiClientProvider).config.baseUrl}/foos',
///   cacheKey: 'foo_list',
///   fromJson: (raw) => (raw as List).cast<Map<String,dynamic>>().map(Foo.fromJson).toList(),
/// )) {
///   if (!_disposed) state = AsyncData(items);
/// }
/// ```
final apiServiceProvider = Provider<ApiService>(
  (ref) => ApiService(ref.watch(apiClientProvider), ref.watch(cacheServiceProvider)),
);

class ApiService {
  final ApiClient _api;
  final CacheService _cache;
  ApiService(this._api, this._cache);

  // CACHE-15: aynı URL için paralel SWR isteklerini tek bir HTTP GET'te birleştirir.
  // URL key: aynı endpoint'e eş zamanlı yapılan N istek → tek ağ çağrısı, N yanıt.
  static final Map<String, Future<http.Response>> _inFlight = {};

  Future<Map<String, String>> _headers({bool auth = true}) async {
    final token = auth ? await StorageService.getToken() : null;
    return _api.buildApiHeaders(token, json: true);
  }

  /// SWR GET isteği — önce cache, sonra network olmak üzere iki kez emit eder.
  ///
  /// Parametreler:
  ///   [url]          : Tam API URL'si.
  ///   [cacheKey]     : Hive önbellek anahtarı. Verilmezse cache kullanılmaz.
  ///   [fromJson]     : Ham API yanıtını `T` tipine dönüştüren fonksiyon.
  ///   [bypassCache]  : `true` ise cache READ atlanır (refresh senaryosu).
  ///                    Cache WRITE yine de yapılır ([cacheKey] verilmişse).
  ///   [cacheTtl]     : Cache yaşam süresi. Varsayılan 5 dakika.
  ///   [auth]         : `false` ise Authorization header eklenmez.
  ///   [extraHeaders] : Ek HTTP başlıkları.
  ///   [timeout]      : İstek zaman aşımı. Varsayılan 10 saniye.
  Stream<T> get<T>({
    required String url,
    String? cacheKey,
    required T Function(dynamic raw) fromJson,
    bool bypassCache = false,
    Duration cacheTtl = const Duration(minutes: 5),
    bool auth = true,
    Map<String, String>? extraHeaders,
    Duration timeout = const Duration(seconds: 10),
  }) async* {
    bool cacheYielded = false;

    // ── 1. Cache okuma (senkron — await yok) ────────────────────────────────
    if (!bypassCache && cacheKey != null) {
      final cached = _cache.getWithStaleness(cacheKey);
      if (cached != null) {
        try {
          yield fromJson(cached.data);
          cacheYielded = true;
          // CACHE-06: erken return kaldırıldı — gerçek SWR için arka plan
          // revalidation her zaman çalışır (ETag ile 304 → 0 bayt gövde).
        } catch (e) {
          debugPrint('[ApiService] Cache parse hatası ($cacheKey): $e');
        }
      }
    }

    // ── 2. Ağdan taze veri çek ───────────────────────────────────────────────
    try {
      final headers = await _headers(auth: auth);
      if (extraHeaders != null) headers.addAll(extraHeaders);

      // ETag varsa If-None-Match ekle — sunucu "değişmedi" ise 304 döner
      if (cacheKey != null) {
        final storedEtag = _cache.getEtag(cacheKey);
        if (storedEtag != null) headers['If-None-Match'] = storedEtag;
      }

      // ApiClient.getRaw: 401 alınırsa tryRefresh+retry yapar; raw response döner.
      // CACHE-15: paralel aynı-URL isteklerini tek Future'da birleştirir.
      final resp = await _getRaw(url, headers, timeout);

      if (resp.statusCode == 304 && cacheKey != null) {
        // CACHE-13: veri değişmedi — gövdeyi yeniden encode etme; sadece TTL +
        // sunucudan gelen ETag (varsa) güncelle.  Eski kod saveData yapıyordu:
        // getWithStaleness → yeni wrapper Map → jsonEncode(entire body) → Hive write.
        await _cache.touchData(
          cacheKey,
          ttl: cacheTtl,
          newEtag: resp.headers['etag'], // null ise mevcut ETag korunur (RFC 7232 §4.1)
        );
        return;
      }

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (cacheKey != null) {
          // CACHE-14: Cache-Control direktiflerini dikkate al (RFC 9111).
          // no-store → hiç kaydetme; önceden kayıtlı zombie veriyi de sil.
          // no-cache / max-age=0 → ttl=0 (SWR her zaman revalidate eder).
          final cc = resp.headers['cache-control'];
          if (_noStore(cc)) {
            await _cache.clearData(cacheKey);
          } else {
            await _cache.saveData(
              cacheKey,
              data,
              ttl: _effectiveTtl(cc, cacheTtl),
              etag: resp.headers['etag'],
            );
          }
        }
        yield fromJson(data);
      } else if (resp.statusCode == 401) {
        // CACHE-07: 401 — oturum düşmüş; cache+storage temizle ve fırlat.
        // cacheYielded olsa bile yutulmaz: güvenlik kritik.
        if (cacheKey != null) await _cache.clearData(cacheKey);
        await StorageService.clear();
        throw const UnauthorizedException();
      } else if (resp.statusCode == 403) {
        // CACHE-07: 403 — ban veya yetki eksikliği; her zaman fırlat.
        final body = _safeBody(resp.body);
        final errMap = body['error'];
        throw AppException(
          errMap is Map ? (errMap['message'] as String? ?? 'Erişim reddedildi') : 'Erişim reddedildi',
          code: errMap is Map ? (errMap['code'] as String? ?? 'FORBIDDEN') : 'FORBIDDEN',
          statusCode: 403,
        );
      } else if (resp.statusCode == 404) {
        // CACHE-07: 404 — kayıt silinmiş; bayat cache'i temizle ve fırlat.
        if (cacheKey != null) await _cache.clearData(cacheKey);
        throw const NotFoundException();
      } else if (!cacheYielded) {
        // Diğer HTTP hataları — cache yoksa fırlat
        final body = _safeBody(resp.body);
        final errMap = body['error'];
        throw AppException(
          errMap is Map
              ? (errMap['message'] as String? ?? 'Bir hata oluştu')
              : (body['detail'] as String? ?? 'HTTP ${resp.statusCode}'),
          code: errMap is Map
              ? (errMap['code'] as String? ?? 'ERR_${resp.statusCode}')
              : 'HTTP_${resp.statusCode}',
          statusCode: resp.statusCode,
        );
      }
      // cacheYielded == true && diğer HTTP hataları (5xx, vb.) → yut (ağ gürültüsü)
    } on SocketException {
      if (!cacheYielded) throw const NetworkException();
      debugPrint('[ApiService] Ağ hatası — cache korunuyor ($cacheKey)');
    } on TimeoutException {
      if (!cacheYielded) throw const NetworkException();
      debugPrint('[ApiService] Timeout — cache korunuyor ($cacheKey)');
    } catch (e) {
      // AppException alt sınıfları (401/403/404 ve türevleri) her zaman yukarı taşınır
      if (e is AppException) rethrow;
      if (!cacheYielded) rethrow;
      debugPrint('[ApiService] Ağ hatası — cache korunuyor ($cacheKey): $e');
    }
  }

  /// Aynı URL için eş zamanlı gelen istekleri tek bir `getRaw` çağrısında
  /// birleştirir.  İstek tamamlanınca (başarı veya hata) map'ten temizlenir.
  Future<http.Response> _getRaw(
    String url,
    Map<String, String> headers,
    Duration timeout,
  ) {
    final existing = _inFlight[url];
    if (existing != null) return existing;
    final future = _api
        .getRaw(url, headers, timeout: timeout)
        .whenComplete(() => _inFlight.remove(url));
    _inFlight[url] = future;
    return future;
  }

  Map<String, dynamic> _safeBody(String raw) {
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  /// RFC 9111 — `Cache-Control: no-store` direktifi var mı?
  static bool _noStore(String? cc) {
    if (cc == null) return false;
    return cc.split(',').any((d) => d.trim().toLowerCase() == 'no-store');
  }

  /// RFC 9111 — `no-cache` veya `max-age=0` direktifi varsa `Duration.zero`
  /// döner (SWR'da her erişim anında stale → arka plan revalidation tetikler).
  /// Aksi hâlde istenen [requested] TTL uygulanır.
  static Duration _effectiveTtl(String? cc, Duration requested) {
    if (cc == null) return requested;
    final dirs = cc.split(',').map((d) => d.trim().toLowerCase());
    if (dirs.any((d) => d == 'no-cache' || d == 'max-age=0')) return Duration.zero;
    return requested;
  }
}
