import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import '../core/logger_service.dart';

class CityService {
  static List<String>? _cache;
  static final Map<String, List<String>> _districtCache = {};

  static Future<List<String>> getCities() async {
    if (_cache != null) return _cache!;
    try {
      final resp = await http.get(Uri.parse('$kBaseUrl/cities'));
      if (resp.statusCode == 200) {
        final list = jsonDecode(resp.body) as List;
        _cache = list.cast<String>();
        return _cache!;
      }
    } catch (e) {
      LoggerService.instance.warning('CityService', 'Şehirler alınamadı: $e');
    }
    return [];
  }

  static Future<List<String>> getDistricts(String province) async {
    if (_districtCache.containsKey(province)) return _districtCache[province]!;
    try {
      final encoded = Uri.encodeComponent(province);
      final resp =
          await http.get(Uri.parse('$kBaseUrl/cities/$encoded/districts'));
      if (resp.statusCode == 200) {
        final list = jsonDecode(resp.body) as List;
        _districtCache[province] = list.cast<String>();
        return _districtCache[province]!;
      }
    } catch (e) {
      LoggerService.instance
          .warning('CityService', 'İlçeler alınamadı [$province]: $e');
    }
    return [];
  }
}
