import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import '../core/logger_service.dart';
import '../models/user.dart';
import 'storage_service.dart';

final _log = LoggerService.instance;

/// Describes WHY a token refresh attempt failed.
///
/// - [succeeded]     — new tokens saved, caller can retry the original request
/// - [noToken]       — no refresh token in storage; user was never logged in
///                     or was already explicitly logged out → do NOT signal logout
/// - [networkError]  — transient failure (no connectivity, server 5xx, timeout)
///                     → do NOT signal logout; the session may still be valid
/// - [revoked]       — backend returned 401 on the refresh endpoint; the
///                     refresh token is genuinely invalid → signal logout
enum RefreshOutcome { succeeded, noToken, networkError, revoked }

class AuthService {
  // Her iki token da geçersizleştiğinde login ekranına yönlendirme sinyali
  static final StreamController<void> authFailedStream =
      StreamController<void>.broadcast();

  // Aynı anda birden fazla refresh isteği olmasın (race condition önlemi)
  static Completer<RefreshOutcome>? _refreshInProgress;
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
    await StorageService.saveToken(body['access_token'] as String);
    if (body['refresh_token'] != null) {
      await StorageService.saveRefreshToken(body['refresh_token'] as String);
    }
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
      isPrivate: user.isPrivate,
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
    await StorageService.saveToken(body['access_token'] as String);
    if (body['refresh_token'] != null) {
      await StorageService.saveRefreshToken(body['refresh_token'] as String);
    }
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
      isPrivate: user.isPrivate,
    );
    return user;
  }

  /// Access token süresi dolduğunda yeni token çifti almayı dener.
  /// Aynı anda birden fazla çağrı olursa ilk çağrının sonucunu beklerler (mutex).
  /// Dönüş değeri [RefreshOutcome] — caller neden başarısız olduğunu bilir ve
  /// yalnızca gerçek bir revoke durumunda logout sinyali verir.
  static Future<RefreshOutcome> tryRefresh() async {
    // Halihazırda refresh yapılıyorsa sonucunu bekle
    if (_refreshInProgress != null) {
      return _refreshInProgress!.future;
    }

    final rt = await StorageService.getRefreshToken();
    // Refresh token yoksa kullanıcı zaten logout — logout sinyali gerekmez
    if (rt == null) return RefreshOutcome.noToken;

    _refreshInProgress = Completer<RefreshOutcome>();
    try {
      final resp = await http.post(
        Uri.parse('$kBaseUrl/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': rt}),
      );
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        await StorageService.saveToken(body['access_token'] as String);
        await StorageService.saveRefreshToken(body['refresh_token'] as String);
        _refreshInProgress!.complete(RefreshOutcome.succeeded);
        _refreshInProgress = null;
        return RefreshOutcome.succeeded;
      }
      // 401 = backend refresh token'ı açıkça reddetti → gerçek revoke
      // Diğer kodlar (500, 503, vb.) geçici sorun → logout tetikleme
      final outcome = resp.statusCode == 401
          ? RefreshOutcome.revoked
          : RefreshOutcome.networkError;
      _refreshInProgress!.complete(outcome);
      _refreshInProgress = null;
      return outcome;
    } catch (e, st) {
      _log.captureException(e, stackTrace: st, tag: 'AuthService.tryRefresh');
      _refreshInProgress!.complete(RefreshOutcome.networkError);
      _refreshInProgress = null;
      return RefreshOutcome.networkError;
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

  /// FCM ve/veya VoIP token'ı backend'e kaydeder.
  /// En az biri non-null olmalıdır; ikisi de null ise istek atılmaz.
  static Future<void> saveDeviceTokens({String? fcmToken, String? voipToken}) async {
    final body = <String, dynamic>{};
    if (fcmToken != null) body['token'] = fcmToken;
    if (voipToken != null) body['voip_token'] = voipToken;

    if (body.isEmpty) return; // Gönderilebilecek bir şey yok

    await apiCall(
      () async => http.post(
        Uri.parse('$kBaseUrl/auth/device-tokens'),
        headers: await _headers(auth: true),
        body: jsonEncode(body),
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
