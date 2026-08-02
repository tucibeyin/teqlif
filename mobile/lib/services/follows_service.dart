import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import '../core/app_exception.dart';
import '../services/storage_service.dart';

void _log(String msg) {
  debugPrint('[FOLLOWS][${DateTime.now().toIso8601String()}] $msg');
}

class FollowsService {
  const FollowsService._();

  static Future<Map<String, String>> _authHeaders() async {
    final token = await StorageService.getToken();
    if (token == null) {
      throw AppException('Oturum bilgisi bulunamadı', code: 'NO_TOKEN', statusCode: 401);
    }
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  static Future<List<Map<String, dynamic>>> fetchFollowingForInvite() async {
    try {
      final myId = await StorageService.getCurrentUserId();
      if (myId == null) return [];
      _log('fetchFollowingForInvite | userId=$myId');
      final headers = await _authHeaders();
      final response = await http.get(
        Uri.parse('$kBaseUrl/follows/$myId/following'),
        headers: headers,
      );
      if (response.statusCode != 200) {
        throw Exception('GET /follows/$myId/following failed: ${response.statusCode}');
      }
      final items = jsonDecode(response.body) as List<dynamic>;
      _log('fetchFollowingForInvite | count=${items.length}');
      return items.map((u) => Map<String, dynamic>.from(u as Map)).toList();
    } catch (e) {
      _log('fetchFollowingForInvite ERROR | $e');
      return [];
    }
  }
}
