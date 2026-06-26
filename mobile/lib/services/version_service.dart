import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

// App Store'daki bundle ID — iTunes Lookup API bu değerle sorgulanır.
const _kIosBundleId = 'teqlif';

class VersionService {
  // iTunes lookup'tan dinamik olarak alınan App Store URL'si.
  // ForceUpdateScreen bu değeri kullanır.
  static String _iosStoreUrl = 'https://apps.apple.com/app/teqlif';

  static String get iosStoreUrl => _iosStoreUrl;

  /// App Store'daki güncel versiyon mevcut versiyondan yüksekse true döner.
  /// Ağ hatası / timeout → false (fail-open: güncelleme zorlanmaz).
  static Future<bool> isIosUpdateRequired() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final resp = await http
          .get(Uri.parse(
            'https://itunes.apple.com/lookup?bundleId=$_kIosBundleId&country=tr',
          ))
          .timeout(const Duration(seconds: 5));

      if (resp.statusCode != 200) return false;

      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final results = body['results'] as List?;
      if (results == null || results.isEmpty) return false;

      final entry = results[0] as Map<String, dynamic>;
      final storeVersion = entry['version'] as String?;
      if (storeVersion == null) return false;

      // trackId'den dinamik App Store linki oluştur
      final trackId = entry['trackId'];
      if (trackId != null) {
        _iosStoreUrl = 'https://apps.apple.com/app/id$trackId';
      }

      return _isLessThan(_parse(info.version), _parse(storeVersion));
    } catch (_) {
      return false;
    }
  }

  static List<int> _parse(String v) {
    final parts = v.split('.');
    return List.generate(
      3,
      (i) => int.tryParse(parts.elementAtOrNull(i) ?? '0') ?? 0,
    );
  }

  static bool _isLessThan(List<int> a, List<int> b) {
    for (int i = 0; i < 3; i++) {
      if (a[i] < b[i]) return true;
      if (a[i] > b[i]) return false;
    }
    return false;
  }
}
