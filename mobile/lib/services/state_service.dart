import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/api_client.dart';
import '../core/logger_service.dart';

class StateService {
  final ApiClient _api;
  StateService(this._api);

  static List<String>? _cache;
  static final Map<String, List<String>> _districtCache = {};

  Future<List<String>> getStates() async {
    if (_cache != null) return _cache!;
    try {
      final resp = await http.get(Uri.parse('${_api.config.baseUrl}/states'));
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

  Future<List<String>> getDistricts(String province) async {
    if (_districtCache.containsKey(province)) return _districtCache[province]!;
    try {
      final encoded = Uri.encodeComponent(province);
      final resp =
          await http.get(Uri.parse('${_api.config.baseUrl}/states/$encoded/districts'));
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

final stateServiceProvider = Provider<StateService>((ref) =>
    StateService(ref.watch(apiClientProvider)));
