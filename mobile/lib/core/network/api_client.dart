import 'dart:convert';
import 'dart:io' show SocketException;
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_exception.dart';
import '../logger_service.dart';
import '../result.dart';
import '../config/app_config.dart';
import '../../services/auth_service.dart' show authServiceProvider, RefreshOutcome;

class ApiClient {
  final AppConfig config;
  final Ref ref;

  ApiClient(this.config, this.ref);

  /// API'den gelen medya linkini döndürür. V1.4 mimarisinde API zaten mutlak
  /// URL döndürdüğü için doğrudan kullanılır.
  String imgUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    
    // API dışında kalan statik istekler için AppConfig'den gelen mediaBaseUrl kullanılır.
    return '${config.mediaBaseUrl}$path';
  }

  /// Authorization + Accept-Language header map'ini oluşturur.
  Future<Map<String, String>> buildApiHeaders(String? token, {bool json = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final lang = prefs.getString('app_locale_language_code') ?? 'tr';
    return {
      if (token != null) 'Authorization': 'Bearer $token',
      'Accept-Language': lang,
      if (json) 'Content-Type': 'application/json',
    };
  }

  Future<void> _waitForRateLimit(http.Response response) async {
    final retryAfter = int.tryParse(response.headers['retry-after'] ?? '') ?? 2;
    await Future.delayed(Duration(seconds: retryAfter.clamp(1, 5)));
  }

  AppException? _parseGatewayError(http.Response response) {
    if (response.statusCode == 429) {
      return AppException(
        'Çok fazla istek gönderildi. Lütfen bir süre bekleyin.',
        code: 'RATE_LIMITED',
        statusCode: 429,
      );
    }
    if (response.statusCode == 502 || response.statusCode == 503 || response.statusCode == 504) {
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

  Never _parseErrorBody(Map<String, dynamic> body, int statusCode) {
    if (body['error'] is Map) {
      final error = body['error'] as Map<String, dynamic>;
      throw AppException(
        error['message']?.toString() ?? 'Bir hata oluştu',
        code: error['code']?.toString() ?? 'ERR_$statusCode',
        statusCode: statusCode,
        extra: error,
      );
    }
    throw AppException(
      body['detail']?.toString() ?? 'Bir hata oluştu',
      code: 'HTTP_$statusCode',
      statusCode: statusCode,
    );
  }

  Future<Map<String, dynamic>> call(
    Future<http.Response> Function() request, {
    bool retried = false,
    bool retried429 = false,
  }) async {
    try {
      final response = await request();

      if (response.statusCode == 429 && !retried429) {
        await _waitForRateLimit(response);
        return call(request, retried: retried, retried429: true);
      }

      final Map<String, dynamic> body;
      try {
        body = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        final gatewayErr = _parseGatewayError(response);
        if (gatewayErr != null) throw gatewayErr;
        return {};
      }

      if (response.statusCode >= 500 && !retried) {
        await Future.delayed(const Duration(milliseconds: 500));
        return call(request, retried: true, retried429: retried429);
      }

      if (response.statusCode >= 400) {
        if (response.statusCode == 401 && !retried) {
          final urlStr = response.request?.url.toString() ?? '';
          final isAuthEndpoint = urlStr.contains('/api/auth/login') || urlStr.contains('/api/auth/register');

          if (!isAuthEndpoint) {
            final authService = ref.read(authServiceProvider);
            final outcome = await authService.tryRefresh();
            if (outcome == RefreshOutcome.succeeded) return call(request, retried: true);
            if (outcome == RefreshOutcome.revoked) {
              authService.authFailedStream.add(null);
            }
          }
        }
        _parseErrorBody(body, response.statusCode);
      }

      return body;
    } on AppException {
      rethrow;
    } catch (e, stack) {
      if (e is SocketException || e is http.ClientException) {
        LoggerService.instance.warning('ApiClient.call', 'Ağ hatası: $e');
      } else {
        LoggerService.instance.captureException(e, stackTrace: stack, tag: 'ApiClient.call');
      }
      throw AppException(
        'Sunucuya ulaşılamıyor veya internet bağlantınız kopuk. Lütfen daha sonra tekrar deneyin.',
        code: 'NETWORK_ERROR',
        statusCode: 0,
      );
    }
  }

  Future<Result<Map<String, dynamic>>> callResult(
    Future<http.Response> Function() request,
  ) async {
    try {
      return Ok(await call(request));
    } on AppException catch (e) {
      return Err(e);
    }
  }

  Future<Result<List<dynamic>>> callListResult(
    Future<http.Response> Function() request,
  ) async {
    try {
      return Ok(await callList(request));
    } on AppException catch (e) {
      return Err(e);
    }
  }

  Future<List<dynamic>> callList(
    Future<http.Response> Function() request, {
    bool retried = false,
    bool retried429 = false,
  }) async {
    try {
      final response = await request();

      if (response.statusCode == 429 && !retried429) {
        await _waitForRateLimit(response);
        return callList(request, retried: retried, retried429: true);
      }

      if (response.statusCode == 401 && !retried) {
        final urlStr = response.request?.url.toString() ?? '';
        final isAuthEndpoint = urlStr.contains('/api/auth/login') || urlStr.contains('/api/auth/register');

        if (!isAuthEndpoint) {
          final authService = ref.read(authServiceProvider);
          final outcome = await authService.tryRefresh();
          if (outcome == RefreshOutcome.succeeded) return callList(request, retried: true);
          if (outcome == RefreshOutcome.revoked) {
            authService.authFailedStream.add(null);
          }
        }
      }

      if (response.statusCode >= 400) {
        try {
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          _parseErrorBody(body, response.statusCode);
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
      if (e is SocketException || e is http.ClientException) {
        LoggerService.instance.warning('ApiClient.callList', 'Ağ hatası: $e');
      } else {
        LoggerService.instance.captureException(e, stackTrace: stack, tag: 'ApiClient.callList');
      }
      throw AppException(
        'Sunucuya ulaşılamıyor veya internet bağlantınız kopuk. Lütfen daha sonra tekrar deneyin.',
        code: 'NETWORK_ERROR',
        statusCode: 0,
      );
    }
  }
}

final apiClientProvider = Provider<ApiClient>((ref) {
  final config = ref.watch(appConfigProvider);
  return ApiClient(config, ref);
});
