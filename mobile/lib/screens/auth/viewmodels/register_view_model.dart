import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../../config/api.dart';
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
  }) async {
    state = const AsyncValue.loading();
    try {
      await AuthService.register(
        email: email,
        username: username,
        fullName: fullName,
        password: password,
        phone: phone,
        referredBy: referredBy,
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
      final body = await apiCall(
        () => http.get(
          Uri.parse('$kBaseUrl/auth/check-username')
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
