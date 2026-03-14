import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import '../models/user.dart';
import 'storage_service.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

class AuthService {
  static Future<Map<String, String>> _headers({bool auth = false}) async {
    final headers = {'Content-Type': 'application/json'};
    if (auth) {
      final token = await StorageService.getToken();
      if (token != null) headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  static void _checkError(http.Response response) {
    if (response.statusCode >= 400) {
      final body = jsonDecode(response.body);
      throw ApiException(body['detail'] ?? 'Bir hata oluştu');
    }
  }

  static Future<String> register({
    required String email,
    required String username,
    required String fullName,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$kBaseUrl/auth/register'),
      headers: await _headers(),
      body: jsonEncode({
        'email': email,
        'username': username,
        'full_name': fullName,
        'password': password,
      }),
    );
    _checkError(response);
    final body = jsonDecode(response.body);
    return body['message'] as String;
  }

  static Future<User> verify({
    required String email,
    required String code,
  }) async {
    final response = await http.post(
      Uri.parse('$kBaseUrl/auth/verify'),
      headers: await _headers(),
      body: jsonEncode({'email': email, 'code': code}),
    );
    _checkError(response);
    final body = jsonDecode(response.body);
    await StorageService.saveToken(body['access_token']);
    final user = User.fromJson(body['user']);
    await StorageService.saveUserInfo(
      id: user.id,
      email: user.email,
      username: user.username,
      fullName: user.fullName,
    );
    return user;
  }

  static Future<String> resendCode(String email) async {
    final response = await http.post(
      Uri.parse('$kBaseUrl/auth/resend-code'),
      headers: await _headers(),
      body: jsonEncode({'email': email}),
    );
    _checkError(response);
    final body = jsonDecode(response.body);
    return body['message'] as String;
  }

  static Future<User> login({
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$kBaseUrl/auth/login'),
      headers: await _headers(),
      body: jsonEncode({'email': email, 'password': password}),
    );
    _checkError(response);
    final body = jsonDecode(response.body);
    await StorageService.saveToken(body['access_token']);
    final user = User.fromJson(body['user']);
    await StorageService.saveUserInfo(
      id: user.id,
      email: user.email,
      username: user.username,
      fullName: user.fullName,
    );
    return user;
  }

  static Future<User> me() async {
    final response = await http.get(
      Uri.parse('$kBaseUrl/auth/me'),
      headers: await _headers(auth: true),
    );
    _checkError(response);
    return User.fromJson(jsonDecode(response.body));
  }

  static Future<void> deleteAccount(String password) async {
    final response = await http.delete(
      Uri.parse('$kBaseUrl/auth/delete-account'),
      headers: await _headers(auth: true),
      body: jsonEncode({'password': password}),
    );
    _checkError(response);
    await StorageService.clear();
  }

  static Future<void> saveFcmToken(String token) async {
    final response = await http.post(
      Uri.parse('$kBaseUrl/auth/fcm-token'),
      headers: await _headers(auth: true),
      body: jsonEncode({'token': token}),
    );
    _checkError(response);
  }

  static Future<void> logout() async {
    await StorageService.clear();
  }
}
