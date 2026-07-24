import 'dart:convert';

import 'package:flutter/foundation.dart';
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

  bool get isEmpty => _strings.isEmpty;
}

class LocalizationService extends StateNotifier<TranslationPack> {
  LocalizationService(this._ref) : super(const TranslationPack({}, 'tr')) {
    final lang = _ref.read(localeProvider).languageCode;
    _currentLang = lang;
    load(lang);

    _ref.listen<Locale>(localeProvider, (_, next) {
      _currentLang = next.languageCode;
      load(next.languageCode);
    });
  }

  final Ref _ref;
  String _currentLang = 'tr';

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

  Future<void> _fetchAndCache(String lang, Box<String> box) async {
    try {
      final resp = await http.get(Uri.parse('$kBaseUrl/i18n/$lang'));
      if (resp.statusCode != 200) return;
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
    } catch (e) {
      debugPrint('[i18n] fetch failed for $lang: $e');
    }
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
