import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const _tokenKey = 'teqlif_token';
  static const _userEmailKey = 'teqlif_user_email';
  static const _userNameKey = 'teqlif_user_name';
  static const _userFullNameKey = 'teqlif_user_fullname';
  static const _userIdKey = 'teqlif_user_id';

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  static Future<void> saveUserInfo({
    required int id,
    required String email,
    required String username,
    required String fullName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_userIdKey, id);
    await prefs.setString(_userEmailKey, email);
    await prefs.setString(_userNameKey, username);
    await prefs.setString(_userFullNameKey, fullName);
  }

  static Future<Map<String, dynamic>?> getUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt(_userIdKey);
    if (id == null) return null;
    return {
      'id': id,
      'email': prefs.getString(_userEmailKey) ?? '',
      'username': prefs.getString(_userNameKey) ?? '',
      'full_name': prefs.getString(_userFullNameKey) ?? '',
    };
  }

  static const _biometricKey = 'teqlif_biometric_enabled';

  static Future<bool> isBiometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_biometricKey) ?? false;
  }

  static Future<void> setBiometricEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_biometricKey, value);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  static const _darkModeKey = 'teqlif_dark_mode';

  static Future<bool> isDarkModeEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_darkModeKey) ?? false;
  }

  static Future<void> setDarkModeEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_darkModeKey, value);
  }
}
