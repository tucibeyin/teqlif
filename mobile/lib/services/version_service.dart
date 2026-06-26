import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import '../config/api.dart';

class VersionService {
  /// Mevcut uygulama versiyonu backend'in min version'ından düşükse
  /// true döner → force-update ekranı gösterilmeli.
  ///
  /// Ağ hatası / timeout → false (fail-open: güncelleme zorlanmaz).
  static Future<bool> isUpdateRequired() async {
    try {
      final response = await http
          .get(Uri.parse('$kBaseHost/api/version'))
          .timeout(const Duration(seconds: 4));

      if (response.statusCode != 200) return false;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final minVersionStr = Platform.isIOS
          ? body['min_ios_version'] as String? ?? '0.0.0'
          : body['min_android_version'] as String? ?? '0.0.0';

      final info = await PackageInfo.fromPlatform();
      final current = _parseVersion(info.version);
      final minimum = _parseVersion(minVersionStr);

      return _isLessThan(current, minimum);
    } catch (_) {
      // Ağ hatası veya parse hatası → güncelleme zorlamasını atla
      return false;
    }
  }

  static List<int> _parseVersion(String v) {
    final parts = v.split('.');
    return List.generate(3, (i) => int.tryParse(parts.elementAtOrNull(i) ?? '0') ?? 0);
  }

  static bool _isLessThan(List<int> a, List<int> b) {
    for (int i = 0; i < 3; i++) {
      if (a[i] < b[i]) return true;
      if (a[i] > b[i]) return false;
    }
    return false; // eşit → güncelleme gerekmez
  }
}
