import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/auth_service.dart';
import '../../../../services/localization_service.dart';
import '../../../../utils/error_helper.dart';

class ResetPasswordViewModel extends AutoDisposeAsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<bool> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    state = const AsyncValue.loading();
    try {
      await AuthService.resetPassword(
        email: email,
        code: code,
        newPassword: newPassword,
      );
      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      final loc = ref.read(localizationProvider);
      handleError(e, loc);
      state = AsyncValue.error(e, st);
      return false;
    }
  }
}

final resetPasswordViewModelProvider = AsyncNotifierProvider.autoDispose<ResetPasswordViewModel, void>(
  ResetPasswordViewModel.new,
);
