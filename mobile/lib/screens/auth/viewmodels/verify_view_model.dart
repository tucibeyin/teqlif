import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/app_exception.dart';
import '../../../../services/auth_service.dart';
import '../../../../services/localization_service.dart';
import '../../../../services/push_notification_service.dart';
import '../../../../utils/error_helper.dart';

sealed class ResendResult {}

class ResendSent extends ResendResult {
  final String message;
  ResendSent(this.message);
}

class ResendCooldown extends ResendResult {
  final int seconds;
  ResendCooldown(this.seconds);
}

class ResendError extends ResendResult {}

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
      await PushNotificationService.initialize();
      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      final loc = ref.read(localizationProvider);
      handleError(e, loc);
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  Future<ResendResult> resend(String email) async {
    // UI handles its own `_resending` bool for the resend button.
    try {
      final lang = ref.read(localizationProvider).lang;
      final msg = await AuthService.resendCode(email, lang: lang);
      return ResendSent(msg ?? '');
    } catch (e) {
      if (e is AppException && e.code == 'CODE_ALREADY_SENT') {
        final secs = (e.extra['seconds_remaining'] as num?)?.toInt() ?? 600;
        return ResendCooldown(secs);
      }
      final loc = ref.read(localizationProvider);
      handleError(e, loc);
      return ResendError();
    }
  }
}

final verifyViewModelProvider = AsyncNotifierProvider.autoDispose<VerifyViewModel, void>(
  VerifyViewModel.new,
);
