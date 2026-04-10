import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import '../core/logger_service.dart';
import '../models/user.dart';
import 'storage_service.dart';

final _log = LoggerService.instance;

class AuthService {
  static Future<Map<String, String>> _headers({bool auth = false}) async {
    final headers = {'Content-Type': 'application/json'};
    if (auth) {
      final token = await StorageService.getToken();
      if (token != null) headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  static Future<String> register({
    required String email,
    required String username,
    required String fullName,
    required String password,
    String? phone,
  }) async {
    final payload = {
      'email': email,
      'username': username,
      'full_name': fullName,
      'password': password,
      if (phone != null) 'phone': phone,
    };
    final body = await apiCall(
      () => http.post(
        Uri.parse('$kBaseUrl/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ),
    );
    return body['message'] as String;
  }

  static Future<User> verify({
    required String email,
    required String code,
  }) async {
    final body = await apiCall(
      () => http.post(
        Uri.parse('$kBaseUrl/auth/verify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'code': code}),
      ),
    );
    await Future.wait([
      StorageService.saveToken(body['access_token'] as String),
      if (body['refresh_token'] != null)
        StorageService.saveRefreshToken(body['refresh_token'] as String),
    ]);
    final user = User.fromJson(body['user'] as Map<String, dynamic>);
    await StorageService.saveUserInfo(
      id: user.id,
      email: user.email,
      username: user.username,
      fullName: user.fullName,
    );
    return user;
  }

  static Future<String> resendCode(String email) async {
    final body = await apiCall(
      () => http.post(
        Uri.parse('$kBaseUrl/auth/resend-code'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      ),
    );
    return body['message'] as String;
  }

  static Future<User> login({
    required String email,
    required String password,
  }) async {
    final body = await apiCall(
      () => http.post(
        Uri.parse('$kBaseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      ),
    );
    await Future.wait([
      StorageService.saveToken(body['access_token'] as String),
      if (body['refresh_token'] != null)
        StorageService.saveRefreshToken(body['refresh_token'] as String),
    ]);
    final user = User.fromJson(body['user'] as Map<String, dynamic>);
    await StorageService.saveUserInfo(
      id: user.id,
      email: user.email,
      username: user.username,
      fullName: user.fullName,
    );
    return user;
  }

  /// Access token süresi dolduğunda yeni token çifti alır.
  /// Başarısız olursa false döner (logout gerekli).
  static Future<bool> tryRefresh() async {
    final rt = await StorageService.getRefreshToken();
    if (rt == null) return false;
    try {
      final resp = await http.post(
        Uri.parse('$kBaseUrl/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': rt}),
      );
      if (resp.statusCode != 200) return false;
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      await Future.wait([
        StorageService.saveToken(body['access_token'] as String),
        StorageService.saveRefreshToken(body['refresh_token'] as String),
      ]);
      return true;
    } catch (e, st) {
      _log.captureException(e, stackTrace: st, tag: 'AuthService.tryRefresh');
      return false;
    }
  }

  static Future<User> me() async {
    final body = await apiCall(
      () async => http.get(
        Uri.parse('$kBaseUrl/auth/me'),
        headers: await _headers(auth: true),
      ),
    );
    return User.fromJson(body);
  }

  static Future<void> deleteAccount(String password) async {
    await apiCall(
      () async => http.delete(
        Uri.parse('$kBaseUrl/auth/delete-account'),
        headers: await _headers(auth: true),
        body: jsonEncode({'password': password}),
      ),
    );
    await StorageService.clear();
  }

  static Future<void> saveFcmToken(String token) async {
    await apiCall(
      () async => http.post(
        Uri.parse('$kBaseUrl/auth/fcm-token'),
        headers: await _headers(auth: true),
        body: jsonEncode({'token': token}),
      ),
    );
  }

  static Future<void> logout() async {
    await StorageService.clear();
  }
}
