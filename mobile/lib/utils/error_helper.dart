import 'package:flutter/material.dart';
import '../core/app_exception.dart';

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
  final message = _extractMessage(error);

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFDC2626),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 4),
      ),
    );
}

String _extractMessage(dynamic error) {
  if (error is AppException) return error.message;
  if (error is Exception) {
    final msg = error.toString();
    // "Exception: ..." prefix'ini temizle
    if (msg.startsWith('Exception: ')) return msg.substring(11);
    return msg;
  }
  return 'Bilinmeyen bir hata oluştu.';
}
