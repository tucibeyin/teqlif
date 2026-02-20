import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import '../models/user.dart';
import '../api/api_client.dart';
import '../api/endpoints.dart';

class AuthState {
  final bool isLoading;
  final UserModel? user;
  final String? error;

  const AuthState({
    this.isLoading = true,
    this.user,
    this.error,
  });

  bool get isAuthenticated => user != null;

  AuthState copyWith({
    bool? isLoading,
    UserModel? user,
    String? error,
  }) =>
      AuthState(
        isLoading: isLoading ?? this.isLoading,
        user: user,
        error: error,
      );
}

class AuthNotifier extends StateNotifier<AuthState> {
  final _storage = const FlutterSecureStorage();
  final _api = ApiClient();

  AuthNotifier() : super(const AuthState()) {
    _init();
  }

  Future<void> _init() async {
    final token = await _storage.read(key: 'jwt_token');
    final userJson = await _storage.read(key: 'user_data');
    if (token != null && userJson != null) {
      try {
        final user =
            UserModel.fromJson(json.decode(userJson) as Map<String, dynamic>);
        state = AuthState(isLoading: false, user: user);
      } catch (_) {
        state = const AuthState(isLoading: false);
      }
    } else {
      state = const AuthState(isLoading: false);
    }
  }

  Future<bool> login(String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _api.post(Endpoints.login,
          data: {'email': email, 'password': password});

      final token = response.data['token'] as String;
      final user =
          UserModel.fromJson(response.data['user'] as Map<String, dynamic>);

      await _api.setToken(token);
      await _storage.write(key: 'user_data', value: json.encode(user.toJson()));

      state = AuthState(isLoading: false, user: user);
      return true;
    } catch (e) {
      String message = 'Giriş başarısız.';
      state = state.copyWith(isLoading: false, error: message);
      return false;
    }
  }

  Future<bool> register(String name, String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _api.post(Endpoints.register,
          data: {'name': name, 'email': email, 'password': password});
      return await login(email, password);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Kayıt başarısız.');
      return false;
    }
  }

  Future<void> logout() async {
    await _api.clearToken();
    await _storage.delete(key: 'user_data');
    state = const AuthState(isLoading: false);
  }

  String? get currentUserId => state.user?.id;
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(),
);
