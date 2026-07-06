import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import '../core/logger_service.dart';
import '../models/user.dart';
import 'storage_service.dart';

final _log = LoggerService.instance;

class AuthService {
  // Her iki token da geçersizleştiğinde login ekranına yönlendirme sinyali
  static final StreamController<void> authFailedStream =
      StreamController<void>.broadcast();

  // Aynı anda birden fazla refresh isteği olmasın (race condition önlemi)
  static Completer<bool>? _refreshInProgress;
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
    String? referredBy,
    String lang = "tr",
  }) async {
    final payload = {
      'email': email,
      'username': username,
      'full_name': fullName,
      'password': password,
      'phone': phone,
      'lang': lang,
      if (referredBy != null && referredBy.isNotEmpty) 'referred_by': referredBy,
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
      isPremium: user.isPremium,
      onboardingCompleted: user.onboardingCompleted,
      isVerified: user.isVerified,
      phoneVerified: user.phoneVerified,
    );
    return user;
  }

  static Future<String> resendCode(String email, {String lang = "tr"}) async {
    final body = await apiCall(
      () => http.post(
        Uri.parse('$kBaseUrl/auth/resend-code'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'lang': lang}),
      ),
    );
    return body['message'] as String;
  }

  static Future<User> login({
    required String identifier,
    required String password,
  }) async {
    final body = await apiCall(
      () => http.post(
        Uri.parse('$kBaseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'login_identifier': identifier, 'password': password}),
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
      isPremium: user.isPremium,
      onboardingCompleted: user.onboardingCompleted,
      isVerified: user.isVerified,
      phoneVerified: user.phoneVerified,
    );
    return user;
  }

  /// Access token süresi dolduğunda yeni token çifti alır.
  /// Aynı anda birden fazla çağrı olursa ilk çağrının sonucunu beklerler (mutex).
  /// Başarısız olursa false döner (logout gerekli).
  static Future<bool> tryRefresh() async {
    // Halihazırda refresh yapılıyorsa sonucunu bekle
    if (_refreshInProgress != null) {
      return _refreshInProgress!.future;
    }

    final rt = await StorageService.getRefreshToken();
    if (rt == null) return false;

    _refreshInProgress = Completer<bool>();
    try {
      final resp = await http.post(
        Uri.parse('$kBaseUrl/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': rt}),
      );
      if (resp.statusCode != 200) {
        _refreshInProgress!.complete(false);
        _refreshInProgress = null;
        return false;
      }
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      await Future.wait([
        StorageService.saveToken(body['access_token'] as String),
        StorageService.saveRefreshToken(body['refresh_token'] as String),
      ]);
      _refreshInProgress!.complete(true);
      _refreshInProgress = null;
      return true;
    } catch (e, st) {
      _log.captureException(e, stackTrace: st, tag: 'AuthService.tryRefresh');
      _refreshInProgress!.complete(false);
      _refreshInProgress = null;
      return false;
    }
  }
  
  static Future<void> requestPasswordReset(String email, {String lang = "tr"}) async {
    await apiCall(
      () => http.post(
        Uri.parse('$kBaseUrl/auth/forgot-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'lang': lang}),
      ),
    );
  }

  static Future<void> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    await apiCall(
      () => http.post(
        Uri.parse('$kBaseUrl/auth/reset-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'code': code,
          'new_password': newPassword,
        }),
      ),
    );
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

  static Future<void> seedOnboardingInterests(List<String> categories) async {
    await apiCall(
      () async => http.post(
        Uri.parse('$kBaseUrl/onboarding/interests'),
        headers: await _headers(auth: true),
        body: jsonEncode({'categories': categories}),
      ),
    );
  }

  static Future<List<Map<String, dynamic>>> getMyPurchases() async {
    final body = await apiCallList(
      () async => http.get(
        Uri.parse('$kBaseUrl/auth/me/purchases'),
        headers: await _headers(auth: true),
      ),
    );
    return List<Map<String, dynamic>>.from(body);
  }

  static Future<List<Map<String, dynamic>>> getMySales() async {
    final body = await apiCallList(
      () async => http.get(
        Uri.parse('$kBaseUrl/auth/me/sales'),
        headers: await _headers(auth: true),
      ),
    );
    return List<Map<String, dynamic>>.from(body);
  }
}
