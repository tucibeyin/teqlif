import 'dart:async';
import 'package:cloudflare_turnstile/cloudflare_turnstile.dart';
import '../core/logger_service.dart';

/// Cloudflare Turnstile görünmez (invisible) CAPTCHA servisi.
///
/// Kullanım:
/// ```dart
/// final token = await CaptchaService.getToken();
/// // token → header'a ekle: 'X-Captcha-Token': token ?? ''
/// ```
class CaptchaService {
  CaptchaService._();

  static const String _siteKey = '0x4AAAAAACu_Bb1lbiRXqw4Q';
  static const String _baseUrl = 'https://www.teqlif.com';
  static const Duration _timeout = Duration(seconds: 12);

  /// Görünmez Turnstile challenge'ı arka planda çalıştırır ve token döner.
  ///
  /// - Token başarıyla alınırsa: `String` döner (backend'e X-Captcha-Token header'ı olarak gönder)
  /// - Timeout veya WebView hatası: `null` döner
  static Future<String?> getToken() async {
    CloudflareTurnstile? turnstile;
    try {
      turnstile = CloudflareTurnstile.invisible(
        siteKey: _siteKey,
        baseUrl: _baseUrl,
        onTimeout: () {
          LoggerService.instance.warning(
            'CaptchaService',
            'Turnstile script yüklenemedi (8s script timeout)',
          );
        },
      );

      return await turnstile.getToken().timeout(
        _timeout,
        onTimeout: () {
          LoggerService.instance.warning(
            'CaptchaService',
            'Token alınamadı: ${_timeout.inSeconds}s timeout',
          );
          return null;
        },
      );
    } catch (e, stack) {
      LoggerService.instance.captureException(
        e,
        stackTrace: stack,
        tag: 'CaptchaService',
        shouldCapture: false,
      );
      return null;
    } finally {
      await turnstile?.dispose();
    }
  }
}
