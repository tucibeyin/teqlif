import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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

  /// Yapay Zeka fiyatlama tahmini → `POST /api/analytics/price-estimate`
  static Future<Map<String, dynamic>?> getPriceEstimate({
    required String title,
    required String description,
    required String category,
  }) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      final resp = await http.post(
        Uri.parse('$kBaseUrl/analytics/price-estimate'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'title': title,
          'description': description,
          'category': category,
        }),
      );
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  /// Yayın sonu satıcı raporu → `GET /api/analytics/seller-report/{streamId}`
  static Future<Map<String, dynamic>?> getSellerReport(int streamId) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      final resp = await http.get(
        Uri.parse('$kBaseUrl/analytics/seller-report/$streamId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  /// Mobil etkileşim sinyali → `/api/analytics/interaction`. Fire-and-forget.
  static Future<void> logInteraction({
    required int itemId,
    required String itemType,
    required String interactionType,
    double? durationSeconds,
    double? pricePoint,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final token = await StorageService.getToken();
      final headers = {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };
      final body = <String, dynamic>{
        'item_id': itemId,
        'item_type': itemType,
        'interaction_type': interactionType,
        if (durationSeconds != null) 'duration_seconds': durationSeconds,
        if (pricePoint != null) 'price_point': pricePoint,
        if (metadata != null) 'metadata': metadata,
      };
      http
          .post(Uri.parse('$kBaseUrl/analytics/interaction'),
              headers: headers, body: jsonEncode(body))
          .catchError((_) => http.Response('', 500));
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> getCampaignReport(int campaignId) async {
    try {
      final token = await StorageService.getToken();
      final resp = await http.get(
        Uri.parse('$kBaseUrl/ads/campaigns/$campaignId/report'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> trackAdClick(int campaignId) async {
    try {
      final token = await StorageService.getToken();
      http
          .post(
            Uri.parse('$kBaseUrl/ads/click/$campaignId'),
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
          )
          .catchError((_) => http.Response('', 500));
    } catch (_) {}
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

// --- Screen Tracking Observer ---
class AnalyticsRouteObserver extends RouteObserver<PageRoute<dynamic>> {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (route is PageRoute) {
      AnalyticsService.trackEvent('screen_view', {'screen_name': route.settings.name ?? 'unknown'});
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute is PageRoute) {
      AnalyticsService.trackEvent('screen_view', {'screen_name': newRoute?.settings.name ?? 'unknown'});
    }
  }
}

// --- App Time Spent Tracking Observer ---
class AnalyticsLifecycleObserver extends WidgetsBindingObserver {
  DateTime? _appStartTime;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _appStartTime = DateTime.now();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      if (_appStartTime != null) {
        final timeSpent = DateTime.now().difference(_appStartTime!).inSeconds;
        if (timeSpent > 2) {
          AnalyticsService.trackEvent('time_spent', {'seconds': timeSpent});
        }
        _appStartTime = null;
      }
    }
  }
}

