import '../core/app_exception.dart';
import '../core/error_mapper.dart';
import '../core/logger_service.dart';
import '../services/auth_service.dart';
import '../services/localization_service.dart';
import '../ui_library/components/overlays/teq_toast.dart';

/// OTA-localized ekranlar için: hata yakala → lokalize et → göster → logla.
///
/// ```dart
/// } catch (e) {
///   handleError(e, ref.read(localizationProvider));
/// }
/// ```
void handleError(Object error, TranslationPack loc) {
  // 401: oturum süresi dolmuş (login/register dışındaki istekler) → authFailedStream'e sinyal ver.
  // INVALID_CREDENTIALS / UNAUTHORIZED giriş hataları ise kullanıcıya gösterilmelidir.
  if (error is AppException &&
      error.statusCode == 401 &&
      error.code != 'INVALID_CREDENTIALS' &&
      error.code != 'UNAUTHORIZED') {
    AuthService.authFailedStream.add(null);
    return;
  }

  final message = ErrorMapper.toMessage(error, loc);
  TeqToast.error(message);
  if (ErrorMapper.shouldLog(error)) {
    LoggerService.instance.captureException(error);
  }
}
