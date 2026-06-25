import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/app_exception.dart';
import '../core/logger_service.dart';
import '../services/auth_service.dart';

const String kBaseUrl = 'https://www.teqlif.com/api';

// AuthService.tryRefresh() mutex'ini kullanarak çift refresh'i önler
Future<bool> _tryRefreshOnce() => AuthService.tryRefresh();
const String kBaseHost = 'https://www.teqlif.com';

/// /uploads/... → https://teqlif.com/uploads/...
String imgUrl(String? path) {
  if (path == null || path.isEmpty) return '';
  if (path.startsWith('http')) return path;
  return '$kBaseHost$path';
}

/// 429 yanıtındaki Retry-After başlığını okur, 1–5 saniye arasında bekler.
Future<void> _waitForRateLimit(http.Response response) async {
  final retryAfter = int.tryParse(response.headers['retry-after'] ?? '') ?? 2;
  await Future.delayed(Duration(seconds: retryAfter.clamp(1, 5)));
}

/// JSON olmayan hata yanıtını [AppException]'a dönüştürür.
/// 429 → RATE_LIMITED, 502/503/504 → SERVER_DOWN, diğer 4xx → INVALID_RESPONSE.
/// Hata yoksa null döner (başarılı yanıt için JSON olmayabilir).
AppException? _parseGatewayError(http.Response response) {
  if (response.statusCode == 429) {
    return AppException(
      'Çok fazla istek gönderildi. Lütfen bir süre bekleyin.',
      code: 'RATE_LIMITED',
      statusCode: 429,
    );
  }
  if (response.statusCode == 502 ||
      response.statusCode == 503 ||
      response.statusCode == 504) {
    return AppException(
      'Sistemlerimizde anlık bir bakım çalışması var. Lütfen birazdan tekrar deneyin.',
      code: 'SERVER_DOWN',
      statusCode: response.statusCode,
    );
  }
  if (response.statusCode >= 400) {
    return AppException(
      'Sunucu geçersiz yanıt döndürdü',
      code: 'INVALID_RESPONSE',
      statusCode: response.statusCode,
    );
  }
  return null;
}

/// Başarısız yanıtın JSON gövdesinden [AppException] üretir.
/// Yeni format `{"error": {...}}` ve eski format `{"detail": "..."}` desteklenir.
Never _parseErrorBody(Map<String, dynamic> body, int statusCode) {
  if (body['error'] is Map) {
    final error = body['error'] as Map<String, dynamic>;
    throw AppException(
      error['message']?.toString() ?? 'Bir hata oluştu',
      code: error['code']?.toString() ?? 'ERR_$statusCode',
      statusCode: statusCode,
    );
  }
  throw AppException(
    body['detail']?.toString() ?? 'Bir hata oluştu',
    code: 'HTTP_$statusCode',
    statusCode: statusCode,
  );
}

/// Merkezi HTTP istek wrapper'ı.
///
/// Tüm API çağrıları bu fonksiyon üzerinden yapılmalıdır.
/// Backend'den dönen hata formatlarını otomatik parse eder ve
/// [AppException] fırlatır:
///
/// **Yeni format** (Phase 2 refactor sonrası):
/// ```json
/// {"success": false, "error": {"code": "NOT_FOUND", "message": "..."}}
/// ```
///
/// **Eski format** (geriye dönük uyumluluk):
/// ```json
/// {"detail": "Hata mesajı"}
/// ```
///
/// Kullanım:
/// ```dart
/// final body = await apiCall(() => http.get(Uri.parse('$kBaseUrl/endpoint')));
/// ```
Future<Map<String, dynamic>> apiCall(
  Future<http.Response> Function() request, {
  bool retried = false,
  bool retried429 = false,
}) async {
  try {
    final response = await request();

    // 429 → Retry-After kadar bekle, bir kez yeniden dene
    if (response.statusCode == 429 && !retried429) {
      await _waitForRateLimit(response);
      return apiCall(request, retried: retried, retried429: true);
    }

    final Map<String, dynamic> body;

    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      // JSON parse hatası — Nginx 429/502/503/504 HTML sayfası veya boş yanıt
      final gatewayErr = _parseGatewayError(response);
      if (gatewayErr != null) throw gatewayErr;
      return {};
    }

    if (response.statusCode >= 400) {
      // 401 → refresh dene, bir kez retry yap
      if (response.statusCode == 401 && !retried) {
        final refreshed = await _tryRefreshOnce();
        if (refreshed) return apiCall(request, retried: true);
        // Her iki token da geçersiz → global logout sinyali
        AuthService.authFailedStream.add(null);
      }
      _parseErrorBody(body, response.statusCode);
    }

    return body;
  } on AppException {
    rethrow;
  } catch (e, stack) {
    // Ağ hatası (timeout, DNS, VPS tamamen kapalı, vb.)
    LoggerService.instance.captureException(
      e,
      stackTrace: stack,
      tag: 'apiCall',
    );
    throw AppException(
      'Sunucuya ulaşılamıyor veya internet bağlantınız kopuk. Lütfen daha sonra tekrar deneyin.',
      code: 'NETWORK_ERROR',
      statusCode: 0,
    );
  }
}

/// Liste döndüren endpoint'ler için [apiCall] muadili.
/// 401 → token yenile → bir kez retry mekanizması dahildir.
/// 429 → Retry-After kadar bekle → bir kez retry mekanizması dahildir.
Future<List<dynamic>> apiCallList(
  Future<http.Response> Function() request, {
  bool retried = false,
  bool retried429 = false,
}) async {
  try {
    final response = await request();

    // 429 → Retry-After kadar bekle, bir kez yeniden dene
    if (response.statusCode == 429 && !retried429) {
      await _waitForRateLimit(response);
      return apiCallList(request, retried: retried, retried429: true);
    }

    if (response.statusCode == 401 && !retried) {
      final refreshed = await _tryRefreshOnce();
      if (refreshed) return apiCallList(request, retried: true);
      // Her iki token da geçersiz → global logout sinyali
      AuthService.authFailedStream.add(null);
    }

    if (response.statusCode >= 400) {
      try {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        _parseErrorBody(body, response.statusCode); // her zaman throw eder
      } catch (e) {
        if (e is AppException) rethrow;
        final gatewayErr = _parseGatewayError(response);
        if (gatewayErr != null) throw gatewayErr;
        throw AppException(
          'Sunucu geçersiz yanıt döndürdü',
          code: 'INVALID_RESPONSE',
          statusCode: response.statusCode,
        );
      }
    }

    try {
      return jsonDecode(response.body) as List<dynamic>;
    } catch (_) {
      return [];
    }
  } on AppException {
    rethrow;
  } catch (e, stack) {
    LoggerService.instance.captureException(
      e,
      stackTrace: stack,
      tag: 'apiCallList',
    );
    throw AppException(
      'Sunucuya ulaşılamıyor veya internet bağlantınız kopuk. Lütfen daha sonra tekrar deneyin.',
      code: 'NETWORK_ERROR',
      statusCode: 0,
    );
  }
}
