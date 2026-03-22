/// Backend'den dönen standart hata yapısını temsil eder.
///
/// Backend yanıt formatı:
/// ```json
/// {"success": false, "error": {"code": "NOT_FOUND", "message": "..."}}
/// ```
class AppException implements Exception {
  /// Kullanıcıya gösterilebilecek hata mesajı.
  final String message;

  /// Backend'den gelen hata kodu (örn: "NOT_FOUND", "UNAUTHORIZED").
  final String code;

  /// HTTP status kodu (örn: 404, 401, 500).
  final int statusCode;

  const AppException(
    this.message, {
    this.code = 'ERR_UNKNOWN',
    this.statusCode = 0,
  });

  /// 4xx/5xx hataları için Sentry'e gönderilip gönderilmeyeceği.
  /// Sunucu kaynaklı hatalar (4xx) birer "expected" hata sayılır;
  /// sadece 5xx ve network hataları Sentry'e iletilmeli.
  bool get shouldCapture => statusCode == 0 || statusCode >= 500;

  @override
  String toString() => 'AppException($statusCode/$code): $message';
}
