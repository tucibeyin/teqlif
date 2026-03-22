import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/app_exception.dart';
import '../core/logger_service.dart';

const String kBaseUrl = 'https://teqlif.com/api';
const String kBaseHost = 'https://teqlif.com';

/// /uploads/... → https://teqlif.com/uploads/...
String imgUrl(String? path) {
  if (path == null || path.isEmpty) return '';
  if (path.startsWith('http')) return path;
  return '$kBaseHost$path';
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
  Future<http.Response> Function() request,
) async {
  try {
    final response = await request();
    final Map<String, dynamic> body;

    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      // JSON parse hatası — Nginx 502/503/504 HTML sayfası veya boş yanıt
      if (response.statusCode == 502 ||
          response.statusCode == 503 ||
          response.statusCode == 504) {
        throw AppException(
          'Sistemlerimizde anlık bir bakım çalışması var. Lütfen birazdan tekrar deneyin.',
          code: 'SERVER_DOWN',
          statusCode: response.statusCode,
        );
      }
      if (response.statusCode >= 400) {
        throw AppException(
          'Sunucu geçersiz yanıt döndürdü',
          code: 'INVALID_RESPONSE',
          statusCode: response.statusCode,
        );
      }
      return {};
    }

    if (response.statusCode >= 400) {
      // Yeni format: {"success": false, "error": {"code": "...", "message": "..."}}
      if (body['error'] is Map) {
        final error = body['error'] as Map<String, dynamic>;
        throw AppException(
          error['message']?.toString() ?? 'Bir hata oluştu',
          code: error['code']?.toString() ?? 'ERR_${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
      // Eski format: {"detail": "..."}
      throw AppException(
        body['detail']?.toString() ?? 'Bir hata oluştu',
        code: 'HTTP_${response.statusCode}',
        statusCode: response.statusCode,
      );
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
