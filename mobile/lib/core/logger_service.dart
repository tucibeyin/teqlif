import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Merkezi loglama ve hata izleme servisi (Singleton).
///
/// Tüm [debugPrint] ve [Sentry.captureException] çağrıları
/// bu sınıf üzerinden yapılmalıdır — doğrudan kullanım yasaktır.
class LoggerService {
  LoggerService._();
  static final LoggerService instance = LoggerService._();

  /// Bilgilendirme amaçlı konsol logu.
  void log(String tag, String message) {
    debugPrint('[$tag] $message');
  }

  /// Uyarı seviyesinde konsol logu (Sentry'e gönderilmez).
  void warning(String tag, String message) {
    debugPrint('[WARNING][$tag] $message');
  }

  /// Hatayı konsola basar ve Sentry'e iletir.
  ///
  /// [shouldCapture] false olduğunda sadece konsola basılır
  /// (örn: OS seviyesi beklenen socket hataları).
  void captureException(
    Object exception, {
    StackTrace? stackTrace,
    String? tag,
    bool shouldCapture = true,
  }) {
    final label = tag != null ? '[$tag] ' : '';
    debugPrint('${label}HATA: $exception');
    if (shouldCapture) {
      // Fire-and-forget: Sentry SDK olayları kuyruğa alır,
      // await kullanmak global error handler'larda bloke eder.
      Sentry.captureException(exception, stackTrace: stackTrace);
    }
  }
}
