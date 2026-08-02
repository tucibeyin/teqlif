import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../services/auth_service.dart';
import '../../../../services/localization_service.dart';
import '../../../../services/storage_service.dart';
import '../../../../utils/error_helper.dart';

class CategoryOnboardingViewModel extends AutoDisposeAsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<bool> submitCategories(List<String> selected) async {
    state = const AsyncValue.loading();
    try {
      await AuthService.seedOnboardingInterests(selected);
      try {
        final user = await AuthService.me();
        await StorageService.saveUserInfo(
          id: user.id,
          email: user.email,
          username: user.username,
          fullName: user.fullName,
          isPremium: user.isPremium,
          onboardingCompleted: true,
          isVerified: user.isVerified,
          phoneVerified: user.phoneVerified,
        );
      } catch (_) {
        final oldInfo = await StorageService.getUserInfo();
        if (oldInfo != null) {
          await StorageService.saveUserInfo(
            id: oldInfo['id'] as int,
            email: oldInfo['email'] as String,
            username: oldInfo['username'] as String,
            fullName: oldInfo['full_name'] as String,
            isPremium: oldInfo['is_premium'] as bool? ?? false,
            onboardingCompleted: true,
          );
        }
      }
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('onboarding_done', true);

      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      final loc = ref.read(localizationProvider);
      handleError(e, loc);
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  Future<void> skip() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_skipped', true);
  }
}

final categoryOnboardingViewModelProvider = AsyncNotifierProvider.autoDispose<CategoryOnboardingViewModel, void>(
  CategoryOnboardingViewModel.new,
);
