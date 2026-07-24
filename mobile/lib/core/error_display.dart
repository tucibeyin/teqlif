import 'package:flutter/material.dart';
import 'package:teqlif/core/app_error.dart';
import 'package:teqlif/core/app_exception.dart';
import 'package:teqlif/l10n/app_localizations.dart';
import 'package:teqlif/services/auth_service.dart';
import 'package:teqlif/ui_library/components/overlays/teq_toast.dart';

/// Merkezi hata gösterim katmanı.
///
/// Tüm ekranlar hata göstermek için bu sınıfı kullanır.
/// AppError tipine göre doğru davranışı seçer:
///   - NetworkError  → "bağlantı yok" toast
///   - AuthError     → logout + login ekranına yönlendir (toast yok)
///   - ClientError   → error toast (hint varsa ikinci satırda)
///   - ServerError   → error toast
///
/// AppException ile gelen hatalar da [fromException] ile doğrudan verilebilir.
class ErrorDisplay {
  ErrorDisplay._();

  static void show(BuildContext context, AppError error) {
    switch (error) {
      case NetworkError():
        TeqToast.warning(AppLocalizations.of(context)!.errorNetworkMessage,
        );

      case AuthError():
        _handleAuth(context);

      case ClientError():
        final msg = error.hint != null
            ? '${error.message} ${error.hint}'
            : error.message;
        TeqToast.error(msg);

      case ServerError():
        TeqToast.error(error.message);
    }
  }

  /// AppException'ı doğrudan verilen durumlarda kullanılır.
  /// F4 migrasyonu tamamlandıkça bu metod kullanımı azalacak.
  static void fromException(BuildContext context, AppException e) {
    show(context, AppError.from(e));
  }

  static void _handleAuth(BuildContext context) {
    AuthService.logout().then((_) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true)
          .pushNamedAndRemoveUntil('/login', (_) => false);
    });
  }
}
