import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/auth_service.dart';
import '../../../../services/localization_service.dart';
import '../../../../utils/error_helper.dart';

class ForgotPasswordViewModel extends AutoDisposeAsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<bool> requestReset(String email) async {
    state = const AsyncValue.loading();
    try {
      final lang = ref.read(localizationProvider).lang;
      await AuthService.requestPasswordReset(email, lang: lang);
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

final forgotPasswordViewModelProvider = AsyncNotifierProvider.autoDispose<ForgotPasswordViewModel, void>(
  ForgotPasswordViewModel.new,
);
