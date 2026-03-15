import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api.dart';

class CityService {
  static List<String>? _cache;

  static Future<List<String>> getCities() async {
    if (_cache != null) return _cache!;
    try {
      final resp = await http.get(Uri.parse('$kBaseUrl/cities'));
      if (resp.statusCode == 200) {
        final list = jsonDecode(resp.body) as List;
        _cache = list.cast<String>();
        return _cache!;
      }
    } catch (_) {}
    return [];
  }
}
