import '../ui_library/components/overlays/teq_snackbar.dart';

void showSuccessSnackbar(String message) {
  TeqSnackBar.show(message: message, type: TeqSnackBarType.success);
}

void showInfoSnackbar(String message) {
  TeqSnackBar.show(message: message, type: TeqSnackBarType.info);
}

void showWarningSnackbar(String message) {
  TeqSnackBar.show(message: message, type: TeqSnackBarType.warning);
}
