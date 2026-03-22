import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api.dart';
import '../services/storage_service.dart';

class AnalyticsService {
  static String? _sessionId;
  static bool? _consentAccepted;

  static String _generateUUID() {
    final random = Random();
    String hex(int count) {
      String str = '';
      for (int i = 0; i < count; i++) {
        str += random.nextInt(16).toRadixString(16);
      }
      return str;
    }
    return '${hex(8)}-${hex(4)}-4${hex(3)}-a${hex(3)}-${hex(12)}';
  }

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    
    _consentAccepted = prefs.getBool('teqlif_tracking_consent');
    if (_consentAccepted == true) {
      _sessionId = prefs.getString('teqlif_session_id');
      if (_sessionId == null) {
        _sessionId = _generateUUID();
        await prefs.setString('teqlif_session_id', _sessionId!);
      }
      trackEvent('app_open');
    }
  }

  static Future<bool?> getConsentStatus() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('teqlif_tracking_consent');
  }

  static Future<void> setConsent(bool accepted) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('teqlif_tracking_consent', accepted);
    _consentAccepted = accepted;
    
    if (accepted) {
      _sessionId = prefs.getString('teqlif_session_id');
      if (_sessionId == null) {
        _sessionId = _generateUUID();
        await prefs.setString('teqlif_session_id', _sessionId!);
      }
      trackEvent('app_open');
    }
  }

  static Future<void> trackEvent(String eventType, [Map<String, dynamic>? metadata]) async {
    if (_consentAccepted != true || _sessionId == null) return;

    try {
      final token = await StorageService.getToken();
      final headers = {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

      final payload = {
        'session_id': _sessionId,
        'event_type': eventType,
        'device_type': 'mobile',
        'os': Platform.isIOS ? 'iOS' : (Platform.isAndroid ? 'Android' : 'Other'),
        'event_metadata': metadata ?? {},
      };

      final uri = Uri.parse('$kBaseUrl/analytics/track');
      
      // Fire and forget
      http.post(uri, headers: headers, body: jsonEncode(payload)).catchError((_) => http.Response('', 500));
    } catch (_) {
      debugPrint('[ANALYTICS] Error tracking event: $eventType');
    }
  }
}
