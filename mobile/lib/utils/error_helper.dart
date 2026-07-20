import 'package:flutter/material.dart';
import '../core/app_exception.dart';
import '../l10n/app_localizations.dart';
import '../ui_library/components/overlays/teq_snackbar.dart';

/// Merkezi UI hata gösterme helper'ı.
///
/// Gelen hatanın türüne göre kullanıcıya uygun mesajı
/// projenin tema standartlarına uygun kırmızı bir Snackbar ile gösterir.
///
/// Kullanım:
/// ```dart
/// try {
///   await SomeService.doSomething();
/// } catch (e) {
///   if (mounted) showErrorSnackbar(context, e);
/// }
/// ```
void showErrorSnackbar(BuildContext context, dynamic error) {
  final message = _extractMessage(context, error);

  TeqSnackBar.show(
    context,
    message: message,
    type: TeqSnackBarType.error,
  );
}

String _extractMessage(BuildContext context, dynamic error) {
  final l = AppLocalizations.of(context)!;
  if (error is NetworkException) return l.errorNetworkMessage;
  if (error is AppException) return error.message;
  if (error is String) return error;
  if (error is Exception) {
    final msg = error.toString();
    if (msg.startsWith('Exception: ')) return msg.substring(11);
    return msg;
  }
  return l.errorGenericRetry;
}
