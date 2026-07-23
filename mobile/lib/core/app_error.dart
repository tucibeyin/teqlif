import 'package:teqlif/core/app_exception.dart';

/// Tip-güvenli hata hiyerarşisi — Result<T> ile birlikte kullanılır.
///
/// AppException (ağ katmanı exception'ı) → AppError (UI katmanı tipi)
/// dönüşümü [AppError.from] factory ile yapılır.
sealed class AppError {
  final String message;
  final String code;
  final String? hint;
  final int? secondsRemaining;

  const AppError({
    required this.message,
    required this.code,
    this.hint,
    this.secondsRemaining,
  });

  /// AppException veya NetworkException'ı tiplendirilmiş AppError'a çevirir.
  factory AppError.from(AppException e) {
    final hint = e.extra['hint'] as String?;
    final secs = e.extra['seconds_remaining'] as int?;

    if (e.statusCode == 0) {
      return NetworkError(
        message: 'İnternet bağlantısı yok.',
        code: e.code,
      );
    }
    if (e.statusCode == 401) {
      return AuthError(
        message: e.message,
        code: e.code,
        hint: hint,
      );
    }
    if (e.statusCode >= 500) {
      return ServerError(
        message: e.message,
        code: e.code,
        hint: hint,
      );
    }
    return ClientError(
      message: e.message,
      code: e.code,
      hint: hint,
      secondsRemaining: secs,
    );
  }
}

/// Ağ bağlantısı yok veya zaman aşımı.
final class NetworkError extends AppError {
  const NetworkError({required super.message, required super.code});
}

/// 401 — oturum süresi doldu veya kimlik doğrulama başarısız.
/// ErrorDisplay bu tipi alınca login ekranına yönlendirir.
final class AuthError extends AppError {
  const AuthError({
    required super.message,
    required super.code,
    super.hint,
  });
}

/// 4xx (401 hariç) — iş kuralı hatası, yetersiz bakiye, rate limit vb.
final class ClientError extends AppError {
  const ClientError({
    required super.message,
    required super.code,
    super.hint,
    super.secondsRemaining,
  });
}

/// 5xx — sunucu taraflı beklenmeyen hata.
final class ServerError extends AppError {
  const ServerError({
    required super.message,
    required super.code,
    super.hint,
  });
}
