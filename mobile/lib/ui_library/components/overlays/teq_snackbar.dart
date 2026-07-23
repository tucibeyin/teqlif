import 'package:flutter/material.dart';
import 'teq_toast.dart';

// TeqSnackBar is a backward-compatible alias for TeqToast.
// All calls are delegated to the overlay-based TeqToast widget.
// Use TeqToast directly in new code.

enum TeqSnackBarType { success, error, info, warning }

class TeqSnackBar {
  TeqSnackBar._();

  static void show(
    BuildContext context, {
    required String message,
    TeqSnackBarType type = TeqSnackBarType.info,
    Duration duration = const Duration(seconds: 3),
  }) {
    switch (type) {
      case TeqSnackBarType.success:
        TeqToast.success(context, message, duration: duration);
        break;
      case TeqSnackBarType.error:
        TeqToast.error(context, message, duration: duration);
        break;
      case TeqSnackBarType.warning:
        TeqToast.warning(context, message, duration: duration);
        break;
      case TeqSnackBarType.info:
        TeqToast.info(context, message, duration: duration);
        break;
    }
  }
}
