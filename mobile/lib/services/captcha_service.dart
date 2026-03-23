import 'dart:async';
import 'package:cloudflare_turnstile/cloudflare_turnstile.dart';
import 'package:flutter/material.dart';
import '../core/logger_service.dart';

/// Cloudflare Turnstile görünmez (invisible) CAPTCHA servisi.
///
/// Kullanım:
/// ```dart
/// final token = await CaptchaService.getToken(context);
/// // token → header'a ekle: 'X-Captcha-Token': token ?? ''
/// ```
///
/// Site Key'i Cloudflare Dashboard → Turnstile → Sites bölümünden alın.
/// Secret Key backend'dedir (.env → CAPTCHA_SECRET_KEY).
class CaptchaService {
  CaptchaService._();

  // TODO: Cloudflare Dashboard'dan aldığın SITE KEY ile değiştir.
  // Test key (her zaman geçer, prod'da kullanma): '1x00000000000000000000AA'
  static const String _siteKey = '0x4AAAAAACu_Bb1lbiRXqw4Q';
  static const String _baseUrl = 'https://teqlif.com';
  static const Duration _timeout = Duration(seconds: 10);

  /// Görünmez Turnstile challenge'ı arka planda çalıştırır ve token döner.
  ///
  /// - Token başarıyla alınırsa: `String` döner (backend'e X-Captcha-Token header'ı olarak gönder)
  /// - Timeout veya WebView hatası: `null` döner
  ///
  /// Çağıran taraf `null` durumunda fail-open davranabilir
  /// (token'ı header'a eklemez) ya da kullanıcıyı uyarabilir.
  static Future<String?> getToken(BuildContext context) async {
    final completer = Completer<String?>();
    OverlayEntry? entry;

    void complete(String? value) {
      if (!completer.isCompleted) {
        completer.complete(value);
        try {
          entry?.remove();
        } catch (_) {}
        entry = null;
      }
    }

    try {
      // Widget, Overlay'e 1×1 piksel görünmez alan olarak eklenir.
      // Invisible mod challenge'ı otomatik olarak arka planda başlatır.
      entry = OverlayEntry(
        builder: (_) => Positioned(
          left: -2,
          top: -2,
          width: 2,
          height: 2,
          child: CloudflareTurnstile(
            siteKey: _siteKey,
            baseUrl: _baseUrl,
            mode: TurnstileMode.invisible,
            onTokenReceived: (token) => complete(token),
            onError: (error) {
              LoggerService.instance.warning(
                'CaptchaService',
                'Turnstile hatası: $error',
              );
              complete(null);
            },
          ),
        ),
      );

      Overlay.of(context).insert(entry!);

      return await completer.future.timeout(
        _timeout,
        onTimeout: () {
          LoggerService.instance.warning(
            'CaptchaService',
            'Token alınamadı: ${_timeout.inSeconds}s timeout',
          );
          complete(null);
          return null;
        },
      );
    } catch (e, stack) {
      LoggerService.instance.captureException(
        e,
        stackTrace: stack,
        tag: 'CaptchaService',
        shouldCapture: false, // Geliştirme aşaması — Sentry'e gönderme
      );
      try {
        entry?.remove();
      } catch (_) {}
      return null;
    }
  }
}
