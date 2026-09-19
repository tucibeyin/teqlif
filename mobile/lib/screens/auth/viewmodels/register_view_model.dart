import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../../core/network/api_client.dart';
import '../../../../core/logger_service.dart';
import '../../../../services/auth_service.dart';
import '../../../../services/localization_service.dart';
import '../../../../utils/error_helper.dart';

class RegisterViewModel extends AutoDisposeAsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<bool> register({
    required String email,
    required String username,
    required String fullName,
    required String password,
    required String? phone,
    required String? referredBy,
    required bool ageConfirmed,
    required bool crossBorderConsent,
    String? consentLocale,
  }) async {
    state = const AsyncValue.loading();
    try {
      await ref.read(authServiceProvider).register(
        email: email,
        username: username,
        fullName: fullName,
        password: password,
        phone: phone,
        referredBy: referredBy,
        ageConfirmed: ageConfirmed,
        crossBorderConsent: crossBorderConsent,
        consentLocale: consentLocale,
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

  Future<String?> checkUsername(String username) async {
    try {
      final body = await ref.read(apiClientProvider).call(
        () => http.get(
          Uri.parse('${ref.read(apiClientProvider).config.baseUrl}/auth/check-username')
              .replace(queryParameters: {'username': username}),
        ),
      );
      return (body['available'] as bool) ? 'available' : 'taken';
    } catch (e) {
      LoggerService.instance.warning('RegisterViewModel', 'Kullanıcı adı kontrolü başarısız: $e');
      return null;
    }
  }
}

final registerViewModelProvider = AsyncNotifierProvider.autoDispose<RegisterViewModel, void>(
  RegisterViewModel.new,
);
