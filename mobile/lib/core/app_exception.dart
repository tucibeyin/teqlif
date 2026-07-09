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

  /// Ekstra payload verisi (örn. EMAIL_NOT_VERIFIED için email)
  final Map<String, dynamic> extra;

  const AppException(
    this.message, {
    this.code = 'ERR_UNKNOWN',
    this.statusCode = 0,
    this.extra = const {},
  });

  /// 4xx/5xx hataları için Sentry'e gönderilip gönderilmeyeceği.
  /// Sunucu kaynaklı hatalar (4xx) birer "expected" hata sayılır;
  /// sadece 5xx ve network hataları Sentry'e iletilmeli.
  bool get shouldCapture => statusCode == 0 || statusCode >= 500;

  @override
  String toString() => 'AppException($statusCode/$code): $message';
}

/// SocketException / TimeoutException gibi ağ katmanı hatalarını temsil eder.
/// UI katmanı bu tipi yakalayıp standart "bağlantı yok" mesajını gösterebilir.
class NetworkException extends AppException {
  const NetworkException()
      : super('ERR_NETWORK', code: 'ERR_NETWORK', statusCode: 0);
}
