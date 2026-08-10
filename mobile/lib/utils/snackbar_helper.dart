import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../ui_library/components/overlays/teq_dialog.dart';
import '../ui_library/components/overlays/teq_snackbar.dart';

/// İzin reddedildiğinde TeqDialog ile kullanıcıya açıklama + opsiyonel Settings butonu sunar.
/// Auto-redirect yok; kullanıcı kendi tercihi ile ayarlara gider.
void showPermissionDeniedDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String openSettingsLabel,
  required String cancelLabel,
}) {
  TeqDialog.show(
    context: context,
    title: title,
    message: message,
    primaryButtonText: openSettingsLabel,
    onPrimaryPressed: () {
      Navigator.of(context).pop();
      openAppSettings();
    },
    secondaryButtonText: cancelLabel,
    onSecondaryPressed: () => Navigator.of(context).pop(),
  );
}

void showSuccessSnackbar(String message) {
  TeqSnackBar.show(message: message, type: TeqSnackBarType.success);
}

void showInfoSnackbar(String message) {
  TeqSnackBar.show(message: message, type: TeqSnackBarType.info);
}

void showWarningSnackbar(String message) {
  TeqSnackBar.show(message: message, type: TeqSnackBarType.warning);
}
