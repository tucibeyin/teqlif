import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
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
///   url: '$kBaseUrl/foos',
///   cacheKey: 'foo_list',
///   fromJson: (raw) => (raw as List).cast<Map<String,dynamic>>().map(Foo.fromJson).toList(),
/// )) {
///   if (!_disposed) state = AsyncData(items);
/// }
/// ```
class ApiService {
  ApiService._();

  static Future<Map<String, String>> _headers({bool auth = true}) async {
    final token = auth ? await StorageService.getToken() : null;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
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
  static Stream<T> get<T>({
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
      final cached = CacheService.getData(cacheKey);
      if (cached != null) {
        try {
          yield fromJson(cached);
          cacheYielded = true;
        } catch (e) {
          debugPrint('[ApiService] Cache parse hatası ($cacheKey): $e');
        }
      }
    }

    // ── 2. Ağdan taze veri çek ───────────────────────────────────────────────
    try {
      final headers = await _headers(auth: auth);
      if (extraHeaders != null) headers.addAll(extraHeaders);

      final resp = await http
          .get(Uri.parse(url), headers: headers)
          .timeout(timeout);

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (cacheKey != null) {
          await CacheService.saveData(cacheKey, data, ttl: cacheTtl);
        }
        yield fromJson(data);
      } else if (!cacheYielded) {
        // Cache yoksa HTTP hatasını fırlat
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
      // Cache zaten yayıldıysa ve HTTP != 200 → hatayı yut
    } on SocketException {
      if (!cacheYielded) throw const NetworkException();
      debugPrint('[ApiService] Ağ hatası — cache korunuyor ($cacheKey)');
    } on TimeoutException {
      if (!cacheYielded) throw const NetworkException();
      debugPrint('[ApiService] Timeout — cache korunuyor ($cacheKey)');
    } catch (e) {
      if (!cacheYielded) rethrow;
      debugPrint('[ApiService] Ağ hatası — cache korunuyor ($cacheKey): $e');
    }
  }

  static Map<String, dynamic> _safeBody(String raw) {
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }
}
