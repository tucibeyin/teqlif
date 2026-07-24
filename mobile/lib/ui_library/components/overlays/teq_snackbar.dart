import 'teq_toast.dart';

enum TeqSnackBarType { success, error, info, warning }

class TeqSnackBar {
  TeqSnackBar._();

  static void show({
    required String message,
    TeqSnackBarType type = TeqSnackBarType.info,
    Duration duration = const Duration(seconds: 3),
  }) {
    switch (type) {
      case TeqSnackBarType.success:
        TeqToast.success(message, duration: duration);
      case TeqSnackBarType.error:
        TeqToast.error(message, duration: duration);
      case TeqSnackBarType.warning:
        TeqToast.warning(message, duration: duration);
      case TeqSnackBarType.info:
        TeqToast.info(message, duration: duration);
    }
  }
}
