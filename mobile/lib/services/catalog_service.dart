import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

import '../config/api.dart';
import '../models/catalog.dart';
import '../utils/listing_fields.dart';

const _kBoxName = 'catalog_cache';
const _kStaleDurationMs = 24 * 60 * 60 * 1000; // 24h

class CatalogService {
  static Box<String>? _box;
  static List<CatalogCategory>? _categories;

  static bool get isReady => _categories != null;

  // ── Public getters ──────────────────────────────────────────────────────────

  static List<CatalogCategory> get categories => _categories ?? [];

  /// Returns `[(key, labelKey)]` for subcategories of the given category.
  /// `labelKey = 'subcat_' + key` — caller resolves to display text via `t()`.
  /// Falls back to kSubcategories if catalog is not ready.
  static List<(String, String)> subcategoriesFor(String categoryKey) {
    if (_categories != null) {
      final cat = _categories!.where((c) => c.key == categoryKey).firstOrNull;
      if (cat != null) {
        return cat.subcategories.map((s) => (s.key, s.labelKey)).toList();
      }
      return [];
    }
    return kSubcategories[categoryKey] ?? [];
  }

  /// Returns the [CatalogSubcategory] for the given key, or null.
  static CatalogSubcategory? subcategoryByKey(String key) {
    if (_categories == null) return null;
    for (final cat in _categories!) {
      for (final sub in cat.subcategories) {
        if (sub.key == key) return sub;
      }
    }
    return null;
  }

  /// Returns catalog fields for the given subcategory.
  /// Returns null when catalog is not ready — caller falls back to FieldConfigService.
  static List<CatalogField>? fieldsFor(String subcategoryKey) {
    return subcategoryByKey(subcategoryKey)?.fields;
  }

  // ── Initialisation ──────────────────────────────────────────────────────────

  static Future<void> initBox() async {
    _box ??= await Hive.openBox<String>(_kBoxName);
  }

  /// Synchronously populates [_categories] from Hive cache.
  /// Call after [initBox] and before runApp.
  static void readCacheSync() {
    final box = _box;
    if (box == null) return;
    final json = box.get('catalog_data');
    if (json == null) return;
    try {
      _categories = _parse(json);
    } catch (e) {
      debugPrint('[catalog] readCacheSync error: $e');
    }
  }

  /// Background stale check — call after runApp, does not block UI.
  static Future<void> checkAndRefresh() async {
    final box = _box;
    if (box == null) return;

    // If no cache at all, fetch immediately.
    if (box.get('catalog_data') == null) {
      await _fetchAndCache(box);
      return;
    }

    // Check staleness.
    final cachedAtStr = box.get('cached_at');
    if (cachedAtStr != null) {
      final age = DateTime.now().millisecondsSinceEpoch - (int.tryParse(cachedAtStr) ?? 0);
      if (age < _kStaleDurationMs) return;
    }

    // Stale — compare version before full download.
    try {
      final cachedVersion = box.get('catalog_version') ?? '';
      final vResp = await http.get(Uri.parse('$kBaseUrl/catalog/version'));
      if (vResp.statusCode != 200) return;
      final serverVersion = (jsonDecode(vResp.body) as Map)['version'] as String;
      if (serverVersion != cachedVersion) {
        await _fetchAndCache(box);
      } else {
        await box.put('cached_at', DateTime.now().millisecondsSinceEpoch.toString());
      }
    } catch (e) {
      debugPrint('[catalog] stale check failed: $e');
    }
  }

  // ── Internals ───────────────────────────────────────────────────────────────

  static Future<void> _fetchAndCache(Box<String> box) async {
    try {
      final resp = await http.get(Uri.parse('$kBaseUrl/catalog'));
      if (resp.statusCode != 200) return;
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final version = decoded['version'] as String? ?? '';
      await box.put('catalog_data', resp.body);
      await box.put('catalog_version', version);
      await box.put('cached_at', DateTime.now().millisecondsSinceEpoch.toString());
      _categories = _parse(resp.body);
      debugPrint('[catalog] fetched and cached (version: $version)');
    } catch (e) {
      debugPrint('[catalog] fetch failed: $e');
    }
  }

  static List<CatalogCategory> _parse(String json) {
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    final cats = decoded['categories'] as List<dynamic>? ?? [];
    return cats.map((c) => CatalogCategory.fromJson(c as Map<String, dynamic>)).toList();
  }
}
