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
const _kLocaleUpdatedAtKey = 'app_locale_updated_at';

/// Uygulama dil tercihini yöneten Riverpod notifier.
///
/// Başlangıçta SharedPreferences'tan kayıtlı dil kodunu okur;
/// bulunamazsa varsayılan olarak Türkçe ('tr') kullanılır.
/// [setLocale] çağrıldığında yeni dili hem state'e hem de
/// SharedPreferences'a yazar.
class LocaleNotifier extends StateNotifier<Locale> {
  static const _tag = 'LocaleNotifier';

  /// [initial] verilirse SharedPreferences async yükleme atlanır (main'de
  /// önceden okunan değer kullanılır → provider ilk render'dan önce doğru).
  LocaleNotifier({Locale? initial}) : super(initial ?? const Locale('tr')) {
    if (initial == null) _loadSavedLocale();
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

  /// Dili değiştirir, SharedPreferences'a ve backend'e güvenilir şekilde kaydeder.
  Future<void> setLocale(Locale locale) async {
    state = locale;
    final nowUtcStr = DateTime.now().toUtc().toIso8601String();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLocaleKey, locale.languageCode);
      await prefs.setString(_kLocaleUpdatedAtKey, nowUtcStr);
    } catch (e, st) {
      LoggerService.instance.captureException(e, stackTrace: st, tag: _tag, shouldCapture: false);
    }
    // Backend sync — güvenilir retry mekanizması (üstel geri çekilme)
    _syncToBackendWithRetry(locale.languageCode, nowUtcStr);
  }

  Future<void> _syncToBackendWithRetry(String langCode, String updatedAtStr) async {
    const delays = [1, 2, 4];
    for (int i = 0; i <= delays.length; i++) {
      try {
        final token = await StorageService.getToken();
        if (token == null) return;
        await apiCall(
          () async => http.patch(
            Uri.parse('$kBaseUrl/auth/me'),
            headers: await buildApiHeaders(token, json: true),
            body: jsonEncode({
              'locale': langCode,
              'locale_updated_at': updatedAtStr,
            }),
          ),
        );
        return; // Başarılı
      } catch (e) {
        if (i < delays.length) {
          await Future.delayed(Duration(seconds: delays[i]));
        } else {
          debugPrint('[$_tag] _syncToBackendWithRetry başarısız oldu, açılışta senkronize edilecek: $e');
        }
      }
    }
  }

  /// Açılışta sunucudan gelen dil ile cihazdaki dil zaman damgalarını karşılaştırarak akıllı senkronize eder.
  Future<void> syncWithServer(String serverLocale, String? serverUpdatedAt) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final localUpdatedAtStr = prefs.getString(_kLocaleUpdatedAtKey);
      
      DateTime? localDt;
      if (localUpdatedAtStr != null) localDt = DateTime.tryParse(localUpdatedAtStr)?.toUtc();
      DateTime? serverDt;
      if (serverUpdatedAt != null) serverDt = DateTime.tryParse(serverUpdatedAt)?.toUtc();

      // Cihazdaki dil tercihi sunucudakinden daha yeniyse (veya sunucudaki zaman damgası eksikse ama cihazda varsa)
      if (localDt != null && (serverDt == null || localDt.isAfter(serverDt))) {
        debugPrint('[$_tag] Cihaz zaman damgası ($localDt) > Sunucu ($serverDt) -> Sunucu güncelleniyor (${state.languageCode})');
        _syncToBackendWithRetry(state.languageCode, localUpdatedAtStr!);
        return;
      }

      // Aksine sunucu daha yeni (veya eşit / ilk kurulum) ise sunucudaki dili yerel belleğe yaz
      if (serverLocale != state.languageCode || localUpdatedAtStr != serverUpdatedAt) {
        debugPrint('[$_tag] Sunucu dili ($serverLocale) yerel ile eşitlendi.');
        await setLocaleLocally(Locale(serverLocale), updatedAtStr: serverUpdatedAt);
      }
    } catch (e, st) {
      LoggerService.instance.captureException(e, stackTrace: st, tag: _tag, shouldCapture: false);
    }
  }

  /// Dili sadece yerel state ve SharedPreferences üzerinde değiştirir (backend çağrısı yapmaz).
  Future<void> setLocaleLocally(Locale locale, {String? updatedAtStr}) async {
    state = locale;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLocaleKey, locale.languageCode);
      if (updatedAtStr != null) {
        await prefs.setString(_kLocaleUpdatedAtKey, updatedAtStr);
      }
    } catch (e, st) {
      LoggerService.instance.captureException(e, stackTrace: st, tag: _tag, shouldCapture: false);
    }
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
