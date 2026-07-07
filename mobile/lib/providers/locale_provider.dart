import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../core/logger_service.dart';
import '../config/api.dart';
import '../services/storage_service.dart';

/// SharedPreferences anahtarı — kalıcı dil tercihi.
const _kLocaleKey = 'app_locale_language_code';

/// Uygulama dil tercihini yöneten Riverpod notifier.
///
/// Başlangıçta SharedPreferences'tan kayıtlı dil kodunu okur;
/// bulunamazsa varsayılan olarak Türkçe ('tr') kullanılır.
/// [setLocale] çağrıldığında yeni dili hem state'e hem de
/// SharedPreferences'a yazar.
class LocaleNotifier extends StateNotifier<Locale> {
  static const _tag = 'LocaleNotifier';

  LocaleNotifier() : super(const Locale('tr')) {
    _loadSavedLocale();
  }

  Future<void> _loadSavedLocale() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(_kLocaleKey);
      if (code != null && code.isNotEmpty) {
        state = Locale(code);
      }
    } catch (e, st) {
      LoggerService.instance.captureException(
        e,
        stackTrace: st,
        tag: _tag,
        shouldCapture: false, // Yerel depolama hatası Sentry'e gönderilmez
      );
    }
  }

  /// Dili değiştirir, SharedPreferences'a ve backend'e kaydeder.
  Future<void> setLocale(Locale locale) async {
    state = locale;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLocaleKey, locale.languageCode);
    } catch (e, st) {
      LoggerService.instance.captureException(e, stackTrace: st, tag: _tag, shouldCapture: false);
    }
    // Backend sync — fire-and-forget, token yoksa atla
    try {
      final token = await StorageService.getToken();
      if (token != null) {
        http.patch(
          Uri.parse('$kBaseUrl/auth/me'),
          headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
          body: jsonEncode({'locale': locale.languageCode}),
        ).ignore();
      }
    } catch (_) {}
  }
}

/// Uygulama genelinde erişilebilen dil provider'ı.
///
/// Kullanım:
/// ```dart
/// // Okuma
/// final locale = ref.watch(localeProvider);
///
/// // Değiştirme
/// ref.read(localeProvider.notifier).setLocale(const Locale('en'));
/// ```
final localeProvider = StateNotifierProvider<LocaleNotifier, Locale>(
  (ref) => LocaleNotifier(),
);
