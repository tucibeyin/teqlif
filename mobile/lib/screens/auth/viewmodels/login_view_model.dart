import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/app_exception.dart';
import '../../../../providers/locale_provider.dart';
import '../../../../services/auth_service.dart';
import '../../../../services/localization_service.dart';
import '../../../../services/push_notification_service.dart';
import '../../../../utils/error_helper.dart';

enum LoginResult {
  success,
  unverified,
  error,
}

class LoginViewModel extends AutoDisposeAsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<LoginResult> login({
    required String identifier,
    required String password,
    required bool userChangedLang,
    required String displayedLang,
  }) async {
    state = const AsyncValue.loading();
    try {
      await AuthService.login(
        identifier: identifier,
        password: password,
      );

      try {
        final user = await AuthService.me();
        if (user.locale != null && user.locale!.isNotEmpty) {
          if (userChangedLang) {
            ref.read(localeProvider.notifier).setLocale(Locale(displayedLang)).ignore();
          } else {
            ref.read(localeProvider.notifier).setLocaleLocally(Locale(user.locale!));
          }
        }
      } catch (_) {
        // me() call failures should not block login success
      }

      await PushNotificationService.initialize();

      state = const AsyncValue.data(null);
      return LoginResult.success;
    } catch (e, st) {
      if (e is AppException && e.code == 'EMAIL_NOT_VERIFIED') {
        final email = e.extra['email']?.toString() ?? identifier;
        try {
          await AuthService.resendCode(email);
        } catch (_) {}
        state = const AsyncValue.data(null);
        return LoginResult.unverified;
      }
      
      final loc = ref.read(localizationProvider);
      handleError(e, loc);
      state = AsyncValue.error(e, st);
      return LoginResult.error;
    }
  }

  Future<bool> changeLanguage(String newLang) async {
    final ok = await ref.read(localizationProvider.notifier).switchLanguage(newLang);
    if (ok) {
      await ref.read(localeProvider.notifier).setLocale(Locale(newLang));
      return true;
    }
    return false;
  }
}

final loginViewModelProvider = AsyncNotifierProvider.autoDispose<LoginViewModel, void>(
  LoginViewModel.new,
);
