import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../config/api.dart';
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
    final u = await AuthService.me();
    return AccountInfoState(user: {
      'id': u.id,
      'email': u.email,
      'username': u.username,
      'full_name': u.fullName,
      'phone': u.phone,
      'phone_verified': u.phoneVerified,
    });
  }

  Future<void> reload() async {
    state = const AsyncValue.loading();
    try {
      final u = await AuthService.me();
      state = AsyncValue.data(AccountInfoState(user: {
        'id': u.id,
        'email': u.email,
        'username': u.username,
        'full_name': u.fullName,
        'phone': u.phone,
        'phone_verified': u.phoneVerified,
      }));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
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
    await apiCall(() => http.post(
      Uri.parse('$kBaseUrl/auth/email-change/request'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      body: jsonEncode({'new_email': email}),
    ));
  }

  Future<void> verifyCode(String email, String code) async {
    final token = await StorageService.getToken();
    await apiCall(() => http.post(
      Uri.parse('$kBaseUrl/auth/email-change/verify'),
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
    await apiCall(() => http.post(
      Uri.parse('$kBaseUrl/auth/phone-verify/request'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      body: jsonEncode({'phone': phone}),
    ));
  }
}

final phoneChangeProvider = NotifierProvider.autoDispose<PhoneChangeViewModel, void>(
  () => PhoneChangeViewModel(),
);
