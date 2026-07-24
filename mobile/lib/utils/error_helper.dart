import 'package:flutter/widgets.dart';
import '../core/app_exception.dart';
import '../core/error_mapper.dart';
import '../core/logger_service.dart';
import '../l10n/app_localizations.dart';
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
  // 401: oturum süresi dolmuş → authFailedStream'e sinyal ver.
  // main_screen bunu dinleyip logout + /login yapar; toast gösterilmez.
  if (error is AppException && error.statusCode == 401) {
    AuthService.authFailedStream.add(null);
    return;
  }

  final message = ErrorMapper.toMessage(error, loc);
  TeqToast.error(message);
  if (ErrorMapper.shouldLog(error)) {
    LoggerService.instance.captureException(error);
  }
}

/// Compat shim — AppLocalizations kullanan (henüz OTA'ya geçmemiş) ekranlar için.
/// context sadece AppLocalizations lookup'ı için kullanılır; TeqToast artık context-free.
void showErrorSnackbar(BuildContext context, Object error) {
  final l = AppLocalizations.of(context);
  final String message;

  if (error is NetworkException || (error is AppException && error.statusCode == 0)) {
    message = l?.errorNetworkMessage ?? 'Bağlantı hatası';
  } else if (error is AppException) {
    message = error.message.isNotEmpty ? error.message : (l?.errorGenericRetry ?? 'Bir hata oluştu');
  } else if (error is String) {
    message = error;
  } else {
    message = l?.errorGenericRetry ?? 'Bir hata oluştu';
  }

  TeqToast.error(message);

  if (error is AppException && error.shouldCapture) {
    LoggerService.instance.captureException(error);
  }
}
