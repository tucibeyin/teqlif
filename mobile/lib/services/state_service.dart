import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import '../core/logger_service.dart';

class StateService {
  static List<String>? _cache;
  static final Map<String, List<String>> _districtCache = {};

  static Future<List<String>> getStates() async {
    if (_cache != null) return _cache!;
    try {
      final resp = await http.get(Uri.parse('$kBaseUrl/states'));
      if (resp.statusCode == 200) {
        final list = jsonDecode(resp.body) as List;
        _cache = list.cast<String>();
        return _cache!;
      }
    } catch (e) {
      LoggerService.instance.warning('StateService', 'İller alınamadı: $e');
    }
    return [];
  }

  static Future<List<String>> getDistricts(String province) async {
    if (_districtCache.containsKey(province)) return _districtCache[province]!;
    try {
      final encoded = Uri.encodeComponent(province);
      final resp =
          await http.get(Uri.parse('$kBaseUrl/states/$encoded/districts'));
      if (resp.statusCode == 200) {
        final list = jsonDecode(resp.body) as List;
        _districtCache[province] = list.cast<String>();
        return _districtCache[province]!;
      }
    } catch (e) {
      LoggerService.instance
          .warning('StateService', 'İlçeler alınamadı [$province]: $e');
    }
    return [];
  }
}
