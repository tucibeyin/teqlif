import 'package:flutter/material.dart';
import '../ui_library/components/overlays/teq_snackbar.dart';

void showSuccessSnackbar(BuildContext context, String message) {
  TeqSnackBar.show(context, message: message, type: TeqSnackBarType.success);
}

void showInfoSnackbar(BuildContext context, String message) {
  TeqSnackBar.show(context, message: message, type: TeqSnackBarType.info);
}

void showWarningSnackbar(BuildContext context, String message) {
  TeqSnackBar.show(context, message: message, type: TeqSnackBarType.warning);
}
