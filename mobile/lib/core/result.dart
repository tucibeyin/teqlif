/// Başarı veya hata sonucunu taşıyan tip.
///
/// Kullanım:
/// ```dart
/// final result = await listingService.create(data);
/// switch (result) {
///   case Ok(:final value): ...
///   case Err(:final error): handleError(error, loc);
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
  final Object error;
  const Err(this.error);
}
