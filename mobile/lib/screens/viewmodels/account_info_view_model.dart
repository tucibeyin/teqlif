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

  Future<String?> requestCode(String email) async {
    try {
      final token = await StorageService.getToken();
      final resp = await http.post(
        Uri.parse('$kBaseUrl/auth/email-change/request'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'new_email': email}),
      );
      if (resp.statusCode == 202) {
        return null; // success
      } else {
        return (jsonDecode(resp.body) as Map<String, dynamic>)['detail'] as String? ?? 'Error';
      }
    } catch (_) {
      return 'network_error';
    }
  }

  Future<String?> verifyCode(String email, String code) async {
    try {
      final token = await StorageService.getToken();
      final resp = await http.post(
        Uri.parse('$kBaseUrl/auth/email-change/verify'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'new_email': email, 'code': code}),
      );
      if (resp.statusCode == 200) {
        return null; // success
      } else {
        return (jsonDecode(resp.body) as Map<String, dynamic>)['detail'] as String? ?? 'Error';
      }
    } catch (_) {
      return 'network_error';
    }
  }
}

final emailChangeProvider = NotifierProvider.autoDispose<EmailChangeViewModel, void>(
  () => EmailChangeViewModel(),
);

// --- Phone Change ---

class PhoneChangeViewModel extends AutoDisposeNotifier<void> {
  @override
  void build() {}

  Future<String?> requestVerification(String phone) async {
    try {
      final token = await StorageService.getToken();
      final resp = await http.post(
        Uri.parse('$kBaseUrl/auth/phone-verify/request'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'phone': phone}),
      );
      if (resp.statusCode == 202) {
        return null;
      } else {
        return (jsonDecode(resp.body) as Map<String, dynamic>)['detail'] as String? ?? 'Error';
      }
    } catch (_) {
      return 'network_error';
    }
  }
}

final phoneChangeProvider = NotifierProvider.autoDispose<PhoneChangeViewModel, void>(
  () => PhoneChangeViewModel(),
);
