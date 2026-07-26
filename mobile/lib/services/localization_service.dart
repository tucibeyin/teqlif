import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

import '../config/api.dart';
import '../providers/locale_provider.dart';

const _kBoxName = 'i18n_cache';
const _kStaleDurationMs = 24 * 60 * 60 * 1000; // 24h

/// Immutable translation pack returned by [localizationProvider].
/// Widgets watch this; [t] is the translation helper.
class TranslationPack {
  const TranslationPack(this._strings, this.lang);

  final Map<String, String> _strings;
  final String lang;

  /// Returns the localized string for [key].
  /// Supports {param} interpolation via [params].
  /// Falls back to [key] itself if not found.
  String t(String key, [Map<String, String>? params]) {
    var val = _strings[key] ?? key;
    if (params != null) {
      params.forEach((k, v) => val = val.replaceAll('{$k}', v));
    }
    return val;
  }

  /// Like [t] but uses [fallback] instead of the key when not found.
  /// Used for option labels that have a DB-stored display value.
  String tOr(String key, String fallback) => _strings[key] ?? fallback;

  bool get isEmpty => _strings.isEmpty;
}

class LocalizationService extends StateNotifier<TranslationPack> {
  /// [initialPack] verilirse — main()'de Hive'dan senkron okunmuş paket —
  /// provider ilk render anında zaten dolu başlar; key flash olmaz.
  /// Boş gelirse (ilk kurulum, cache yok) normal async fetch tetiklenir.
  LocalizationService(this._ref, {TranslationPack? initialPack})
      : super(initialPack ?? const TranslationPack({}, 'tr')) {
    final lang = _ref.read(localeProvider).languageCode;
    _currentLang = lang;

    final box = _box;
    if (box != null) {
      if (initialPack != null && !initialPack.isEmpty) {
        // Pack hazır — ready'yi hemen tamamla, stale kontrolü arka planda.
        _readyCompleter.complete();
        _checkStale(lang, box).ignore();
      } else {
        // Cache yok (ilk kurulum) — API'den çek, bitince ready'yi tamamla.
        _fetchAndCache(lang, box).then((_) {
          if (!_readyCompleter.isCompleted) _readyCompleter.complete();
        });
      }
    } else {
      _readyCompleter.complete();
    }

    _ref.listen<Locale>(localeProvider, (_, next) {
      if (next.languageCode == _currentLang && !state.isEmpty) return;
      _currentLang = next.languageCode;
      load(next.languageCode);
    });
  }

  /// Hive box'tan senkron okuma — initBox() sonrası güvenle çağrılabilir.
  /// main()'de runApp öncesi ilk pack'i almak için kullanılır.
  static TranslationPack readCacheSync(String lang) {
    final box = _box;
    if (box == null) return TranslationPack({}, lang);
    final json = box.get('pack_$lang');
    if (json == null) return TranslationPack({}, lang);
    try {
      return TranslationPack(
        Map<String, String>.from(jsonDecode(json) as Map), lang);
    } catch (_) {
      return TranslationPack({}, lang);
    }
  }

  final Ref _ref;
  String _currentLang = 'tr';

  /// Completes when the first non-empty pack is ready.
  /// SplashScreen awaits this (with timeout) before removing the native splash,
  /// guaranteeing zero flash of keys even on first install.
  final _readyCompleter = Completer<void>();
  Future<void> get ready => _readyCompleter.future;

  static Box<String>? _box;

  static Future<void> initBox() async {
    _box ??= await Hive.openBox<String>(_kBoxName);
  }

  Future<void> load(String lang) async {
    final box = _box;
    if (box == null) return;

    final cachedJson = box.get('pack_$lang');
    if (cachedJson != null) {
      final strings = Map<String, String>.from(jsonDecode(cachedJson) as Map);
      if (_currentLang == lang) {
        state = TranslationPack(strings, lang);
      }
      _checkStale(lang, box).ignore();
    } else {
      await _fetchAndCache(lang, box);
    }
  }

  Future<void> _checkStale(String lang, Box<String> box) async {
    final cachedAtStr = box.get('cached_at_$lang');
    if (cachedAtStr != null) {
      final age = DateTime.now().millisecondsSinceEpoch - (int.tryParse(cachedAtStr) ?? 0);
      if (age < _kStaleDurationMs) return;
    }
    try {
      final cachedVersion = box.get('version_$lang') ?? '';
      final vResp = await http.get(Uri.parse('$kBaseUrl/i18n/$lang/version'));
      if (vResp.statusCode != 200) return;
      final serverVersion = (jsonDecode(vResp.body) as Map)['version'] as String;
      if (serverVersion != cachedVersion) {
        await _fetchAndCache(lang, box);
      } else {
        await box.put('cached_at_$lang', DateTime.now().millisecondsSinceEpoch.toString());
      }
    } catch (e) {
      debugPrint('[i18n] stale check failed: $e');
    }
  }

  Future<bool> _fetchAndCache(String lang, Box<String> box) async {
    try {
      final resp = await http.get(Uri.parse('$kBaseUrl/i18n/$lang'));
      if (resp.statusCode != 200) return false;
      final strings = Map<String, String>.from(jsonDecode(resp.body) as Map);
      await box.put('pack_$lang', resp.body);
      await box.put('cached_at_$lang', DateTime.now().millisecondsSinceEpoch.toString());
      try {
        final vResp = await http.get(Uri.parse('$kBaseUrl/i18n/$lang/version'));
        if (vResp.statusCode == 200) {
          final ver = (jsonDecode(vResp.body) as Map)['version'] as String;
          await box.put('version_$lang', ver);
        }
      } catch (_) {}
      if (_currentLang == lang) {
        state = TranslationPack(strings, lang);
      }
      return true;
    } catch (e) {
      debugPrint('[i18n] fetch failed for $lang: $e');
      return false;
    }
  }

  /// Loads a language pack and updates state only on success.
  /// Returns true if the pack is now active; false on network/server failure.
  /// Unlike [load], this method is designed for user-initiated language switches:
  /// it does NOT update [_currentLang] on failure, enabling the caller to revert UI.
  Future<bool> switchLanguage(String lang) async {
    if (lang == _currentLang && !state.isEmpty) return true;
    final box = _box;
    if (box == null) return false;

    final cachedJson = box.get('pack_$lang');
    if (cachedJson != null) {
      final strings = Map<String, String>.from(jsonDecode(cachedJson) as Map);
      _currentLang = lang;
      state = TranslationPack(strings, lang);
      _checkStale(lang, box).ignore();
      return true;
    }

    // Not cached — temporarily adopt the lang so _fetchAndCache updates state on success.
    final prevLang = _currentLang;
    _currentLang = lang;
    final ok = await _fetchAndCache(lang, box);
    if (!ok) _currentLang = prevLang;
    return ok;
  }

  Future<void> clearCache() async {
    await _box?.clear();
    state = const TranslationPack({}, 'tr');
  }
}

final localizationProvider =
    StateNotifierProvider<LocalizationService, TranslationPack>(
  (ref) => LocalizationService(ref),
);
