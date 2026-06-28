import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import '../config/api.dart';

enum VersionStatus { upToDate, softUpdate, forceUpdate }

class VersionService {
  static String _iosStoreUrl = 'https://apps.apple.com/app/teqlif';
  static String _androidStoreUrl = 'https://play.google.com/store/apps/details?id=com.teqlif.app';

  static String get iosStoreUrl => _iosStoreUrl;
  static String get androidStoreUrl => _androidStoreUrl;

  static Future<VersionStatus> checkVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final resp = await http
          .get(Uri.parse('$kBaseUrl/config/version'))
          .timeout(const Duration(seconds: 5));

      if (resp.statusCode != 200) return VersionStatus.upToDate;

      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final platformKey = Platform.isIOS ? 'ios' : 'android';
      final config = body[platformKey] as Map<String, dynamic>?;

      if (config == null) return VersionStatus.upToDate;

      final minVersion = config['min_version'] as String?;
      final latestVersion = config['latest_version'] as String?;
      final storeUrl = config['store_url'] as String?;

      if (storeUrl != null && storeUrl.isNotEmpty) {
        if (Platform.isIOS) {
          _iosStoreUrl = storeUrl;
        } else {
          _androidStoreUrl = storeUrl;
        }
      }

      final appV = _parse(info.version);

      if (minVersion != null && _isLessThan(appV, _parse(minVersion))) {
        return VersionStatus.forceUpdate;
      }

      if (latestVersion != null && _isLessThan(appV, _parse(latestVersion))) {
        return VersionStatus.softUpdate;
      }

      return VersionStatus.upToDate;
    } catch (_) {
      return VersionStatus.upToDate; // Fail open
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
