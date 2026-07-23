import 'package:teqlif/core/app_error.dart';

/// Başarı veya hata sonucunu taşıyan tip.
///
/// Kullanım:
/// ```dart
/// final result = await listingService.create(data);
/// switch (result) {
///   case Ok(:final value): // başarı
///   case Err(:final error): ErrorDisplay.show(context, error);
/// }
/// ```
sealed class Result<T> {
  const Result();
}

final class Ok<T> extends Result<T> {
  final T value;
  const Ok(this.value);
}

final class Err<T> extends Result<T> {
  final AppError error;
  const Err(this.error);
}
