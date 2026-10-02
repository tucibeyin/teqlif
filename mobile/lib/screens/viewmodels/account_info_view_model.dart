import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../core/network/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/storage_service.dart';

// --- Account Info ---

class AccountInfoState {
  final Map<String, dynamic>? user;
  const AccountInfoState({this.user});
}

class AccountInfoViewModel extends AutoDisposeAsyncNotifier<AccountInfoState> {
  @override
  FutureOr<AccountInfoState> build() async {
    final u = await ref.read(authServiceProvider).me();
    return AccountInfoState(user: {
      'id': u.id,
      'email': u.email,
      'username': u.username,
      'full_name': u.fullName,
      'phone': u.phone,
      'phone_verified': u.phoneVerified,
    });
  }

  Future<void> reload({bool silent = false}) async {
    // silent=true → eski veri ekranda kalır, hata olursa rethrow (caller toast gösterir)
    // silent=false (ilk yükleme gibi) → loading + hata ekranı
    final prev = state;
    if (!silent) state = const AsyncValue.loading();
    try {
      final u = await ref.read(authServiceProvider).me();
      state = AsyncValue.data(AccountInfoState(user: {
        'id': u.id,
        'email': u.email,
        'username': u.username,
        'full_name': u.fullName,
        'phone': u.phone,
        'phone_verified': u.phoneVerified,
      }));
    } catch (e, st) {
      if (silent && prev is AsyncData) {
        state = prev; // eski veriyi koru, ekranı değiştirme
      } else {
        state = AsyncValue.error(e, st);
      }
      rethrow;
    }
  }
}

final accountInfoProvider = AsyncNotifierProvider.autoDispose<AccountInfoViewModel, AccountInfoState>(
  () => AccountInfoViewModel(),
);

// --- Email Change ---

class EmailChangeViewModel extends AutoDisposeNotifier<void> {
  @override
  void build() {}

  Future<void> requestCode(String email) async {
    final token = await StorageService.getToken();
    await ref.read(apiClientProvider).call(() => http.post(
      Uri.parse('${ref.read(apiClientProvider).config.baseUrl}/auth/email-change/request'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      body: jsonEncode({'new_email': email}),
    ));
  }

  Future<void> verifyCode(String email, String code) async {
    final token = await StorageService.getToken();
    await ref.read(apiClientProvider).call(() => http.post(
      Uri.parse('${ref.read(apiClientProvider).config.baseUrl}/auth/email-change/verify'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      body: jsonEncode({'new_email': email, 'code': code}),
    ));
  }
}

final emailChangeProvider = NotifierProvider.autoDispose<EmailChangeViewModel, void>(
  () => EmailChangeViewModel(),
);

// --- Phone Change ---

class PhoneChangeViewModel extends AutoDisposeNotifier<void> {
  @override
  void build() {}

  Future<void> requestVerification(String phone) async {
    final token = await StorageService.getToken();
    await ref.read(apiClientProvider).call(() => http.post(
      Uri.parse('${ref.read(apiClientProvider).config.baseUrl}/auth/phone-verify/request'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      body: jsonEncode({'phone': phone}),
    ));
  }
}

final phoneChangeProvider = NotifierProvider.autoDispose<PhoneChangeViewModel, void>(
  () => PhoneChangeViewModel(),
);
