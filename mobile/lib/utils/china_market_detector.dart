import 'dart:io';
import 'package:flutter/services.dart';

/// Apple Guideline 5: MIIT, Çin App Store'undaki uygulamalarda CallKit kullanımını yasakladı.
/// Bu sınıf iOS Storefront API üzerinden Çin pazarını tespit eder.
/// Android'de her zaman false döner.
class ChinaMarketDetector {
  ChinaMarketDetector._();

  static const _channel = MethodChannel('com.teqlif/region');
  static bool? _cached;

  /// İlk çağrıda iOS native Storefront API'yi sorgular, sonucu önbelleğe alır.
  static Future<bool> isChina() async {
    if (_cached != null) return _cached!;
    if (!Platform.isIOS) {
      _cached = false;
      return false;
    }
    try {
      _cached = await _channel.invokeMethod<bool>('isChina') ?? false;
    } catch (_) {
      _cached = false;
    }
    return _cached!;
  }

  /// Background isolate'ler MethodChannel kullanamaz; locale fallback kullanır.
  static bool isChinaSync() {
    if (!Platform.isIOS) return false;
    // ignore: deprecated_member_use
    final locale = Platform.localeName; // e.g. "zh_CN"
    return locale.contains('_CN') || locale.startsWith('zh');
  }
}
