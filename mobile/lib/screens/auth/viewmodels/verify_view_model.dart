import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/auth_service.dart';
import '../../../../services/localization_service.dart';
import '../../../../services/push_notification_service.dart';
import '../../../../utils/error_helper.dart';

class VerifyViewModel extends AutoDisposeAsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<bool> verify({
    required String email,
    required String code,
  }) async {
    state = const AsyncValue.loading();
    try {
      await AuthService.verify(
        email: email,
        code: code,
      );
      PushNotificationService.initialize();
      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      final loc = ref.read(localizationProvider);
      handleError(e, loc);
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  Future<String?> resend(String email) async {
    // We don't set loading state for resend here to not overlap with verify loading state.
    // The UI handles its own `_resending` bool for the resend button specifically.
    try {
      final lang = ref.read(localizationProvider).lang;
      final msg = await AuthService.resendCode(email, lang: lang);
      return msg;
    } catch (e) {
      final loc = ref.read(localizationProvider);
      handleError(e, loc);
      return null;
    }
  }
}

final verifyViewModelProvider = AsyncNotifierProvider.autoDispose<VerifyViewModel, void>(
  VerifyViewModel.new,
);
