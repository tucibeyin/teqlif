import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import '../core/logger_service.dart';
import 'storage_service.dart';

/// Mobil cihazda yakalanan kritik hataları VPS uvicorn log'una iletir.
///
/// Kullanım:
/// ```dart
/// } catch (e, st) {
///   ClientLogger.report(tag: 'StartStream', message: 'Yayın başlatılamadı', error: e, stackTrace: st);
/// }
/// ```
class ClientLogger {
  ClientLogger._();

  static Future<void> report({
    required String tag,
    required String message,
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? details,
  }) async {
    // Yerel loglara her zaman yaz (Sentry + debugPrint)
    LoggerService.instance.captureException(
      error ?? message,
      stackTrace: stackTrace,
      tag: tag,
    );

    // Backend'e arka planda gönder — hata fırlatmaz
    _sendToBackend(
      tag:     tag,
      message: message,
      error:   error?.toString(),
      details: details,
    ).ignore();
  }

  static Future<void> _sendToBackend({
    required String tag,
    required String message,
    String? error,
    Map<String, dynamic>? details,
  }) async {
    try {
      final token   = await StorageService.getToken();
      final headers = {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };
      final body = jsonEncode({
        'tag':      tag,
        'message':  message,
        if (error != null) 'error': error,
        if (details != null) 'details': details,
        'platform': Platform.isIOS ? 'ios' : 'android',
      });
      await http
          .post(Uri.parse('$kBaseUrl/client-log'), headers: headers, body: body)
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Log gönderimi başarısız olursa sessizce geç
    }
  }
}
