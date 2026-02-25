import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; // Yeni import
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
    await checkAuth();
  }

  /// Uygulama açılışında oturumu kontrol eder ve varsa Push Token'ı günceller
  Future<void> checkAuth() async {
    final token = await _storage.read(key: 'jwt_token');
    final userJson = await _storage.read(key: 'user_data');
    if (token != null && userJson != null) {
      try {
        final user =
            UserModel.fromJson(json.decode(userJson) as Map<String, dynamic>);
        state = AuthState(isLoading: false, user: user);
        
        // Oturum varsa FCM Token'ı alıp sunucuya gönderelim
        _refreshPushToken();
      } catch (_) {
        state = const AuthState(isLoading: false);
      }
    } else {
      state = const AuthState(isLoading: false);
    }
  }

  /// Firebase'den token alıp sunucuya kaydeder
  Future<void> _refreshPushToken() async {
    try {
      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken != null) {
        await updatePushToken(fcmToken);
      }
    } catch (e) {
      debugPrint('[FCM GET TOKEN ERROR] $e');
    }
  }

  /// Belirli bir token'ı sunucuya POST eder
  Future<void> updatePushToken(String? fcmToken) async {
    if (fcmToken == null || !state.isAuthenticated) return;
    
    try {
      await _api.post(Endpoints.pushRegister, data: {
        'fcmToken': fcmToken,
      });
      debugPrint('[PUSH] Token sunucuya başarıyla kaydedildi.');
    } catch (e) {
      debugPrint('[PUSH ERROR] Token kaydedilemedi: $e');
    }
  }

  Future<bool> login(String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _api
          .post(Endpoints.login, data: {'email': email, 'password': password});

      final token = response.data['token'] as String;
      final user =
          UserModel.fromJson(response.data['user'] as Map<String, dynamic>);

      await _api.setToken(token);
      await _storage.write(key: 'user_data', value: json.encode(user.toJson()));

      state = AuthState(isLoading: false, user: user);
      
      // Giriş başarılı olduktan hemen sonra token'ı kaydet
      _refreshPushToken();
      
      return true;
    } catch (e) {
      debugPrint('[LOGIN ERROR] $e');
      String message = 'Giriş başarısız.';
      if (e is DioException) {
        final data = e.response?.data;
        if (data is Map) {
          message = (data['message'] ?? data['error'] ?? message).toString();
        }
      }
      state = state.copyWith(isLoading: false, error: message);
      return false;
    }
  }

  Future<String> register(String name, String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _api.post(Endpoints.register,
          data: {'name': name, 'email': email, 'password': password});
      
      state = const AuthState(isLoading: false);
      return 'pending_verification';
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Kayıt başarısız.');
      return 'error';
    }
  }

  Future<bool> verifyEmail(String email, String code) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _api.post(Endpoints.verifyEmail,
          data: {'email': email, 'code': code});
      state = const AuthState(isLoading: false);
      return true;
    } catch (e) {
      String message = 'Doğrulama başarısız.';
      if (e is DioException) {
        final data = e.response?.data;
        if (data is Map) {
          message = (data['message'] ?? data['error'] ?? message).toString();
        }
      }
      state = state.copyWith(isLoading: false, error: message);
      return false;
    }
  }

  Future<bool> requestPasswordReset(String email) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _api.post(Endpoints.forgotPassword, data: {'email': email});
      state = const AuthState(isLoading: false);
      return true;
    } catch (e) {
      String message = 'İşlem başarısız.';
      if (e is DioException) {
        final data = e.response?.data;
        if (data is Map) {
          message = (data['message'] ?? data['error'] ?? message).toString();
        }
      }
      state = state.copyWith(isLoading: false, error: message);
      return false;
    }
  }

  Future<bool> resetPassword(String email, String code, String newPassword) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _api.post(Endpoints.resetPassword,
          data: {'email': email, 'code': code, 'newPassword': newPassword});
      state = const AuthState(isLoading: false);
      return true;
    } catch (e) {
      String message = 'Şifre sıfırlama başarısız.';
      if (e is DioException) {
        final data = e.response?.data;
        if (data is Map) {
          message = (data['message'] ?? data['error'] ?? message).toString();
        }
      }
      state = state.copyWith(isLoading: false, error: message);
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