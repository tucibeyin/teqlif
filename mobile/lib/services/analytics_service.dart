import 'package:flutter/foundation.dart' show compute;
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api.dart';
import '../services/storage_service.dart';

class AiInsufficientTuciException implements Exception {
  final String detail;
  const AiInsufficientTuciException(this.detail);
}

class AnalyticsService {
  static String? _sessionId;
  static bool? _consentAccepted;
  static final Set<int> _impressedCampaigns = {};

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

  static Future<String> _lang() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('app_locale_language_code') ?? 'tr';
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

  /// Kitle büyüklüğü tahmini → `GET /api/leads/audience-size`
  static Future<Map<String, dynamic>?> getAudienceSize({
    required String title,
    String category = '',
  }) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      final uri = Uri.parse('$kBaseUrl/leads/audience-size').replace(
        queryParameters: {
          'title': title,
          if (category.isNotEmpty) 'category': category,
        },
      );
      final resp = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) {
        return await compute(jsonDecode, resp.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  /// Lead blast gönder → `POST /api/leads/send-blast`
  static Future<Map<String, dynamic>?> sendLeadBlast({
    required String title,
    required String category,
    required int estimatedCost,
    int? listingId,
    int? streamId,
    int? recipientCount,
  }) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      final resp = await http.post(
        Uri.parse('$kBaseUrl/leads/send-blast'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'title': title,
          'category': category,
          'estimated_cost': estimatedCost,
          'listing_id': ?listingId,
          'stream_id': ?streamId,
          'recipient_count': ?recipientCount,
        }),
      );
      if (resp.statusCode == 202) {
        return await compute(jsonDecode, resp.body) as Map<String, dynamic>;
      }
      // Yetersiz bütçe veya başka hata — mesajı döndür
      try {
        final body = await compute(jsonDecode, resp.body) as Map<String, dynamic>;
        return {'error': body['detail'] ?? 'Duyuru gönderilemedi.'};
      } catch (_) {}
      return {'error': 'Duyuru gönderilemedi.'};
    } catch (_) {}
    return null;
  }

  /// Yapay Zeka fiyatlama tahmini → `POST /api/analytics/price-estimate`
  /// Throws [AiInsufficientTuciException] on HTTP 402 (insufficient TUCi).
  /// Returns null on other errors.
  static Future<Map<String, dynamic>?> getPriceEstimate({
    required String title,
    required String description,
    required String category,
    String city = '',
    int? excludeListingId,
  }) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      final prefs = await SharedPreferences.getInstance();
      final lang = prefs.getString('app_locale_language_code') ?? 'tr';
      final resp = await http.post(
        Uri.parse('$kBaseUrl/analytics/price-estimate'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'Accept-Language': lang,
        },
        body: jsonEncode({
          'title': title,
          'description': description,
          'category': category,
          'city': city,
          if (excludeListingId != null && excludeListingId > 0)
            'exclude_listing_id': excludeListingId,
        }),
      );
      if (resp.statusCode == 200) {
        return await compute(jsonDecode, resp.body) as Map<String, dynamic>;
      }
      if (resp.statusCode == 402) {
        final detail = (await compute(jsonDecode, resp.body) as Map<String, dynamic>)['detail'] as String? ?? '';
        throw AiInsufficientTuciException(detail);
      }
    } on AiInsufficientTuciException {
      rethrow;
    } catch (_) {}
    return null;
  }

  /// Pro satıcı kapsamlı analitik → `GET /api/analytics/pro-insights`
  static Future<Map<String, dynamic>?> getProInsights({String? startDate, String? endDate}) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      final prefs = await SharedPreferences.getInstance();
      final lang = prefs.getString('app_locale_language_code') ?? 'tr';
      var url = '$kBaseUrl/analytics/pro-insights';
      final params = <String>[];
      if (startDate != null) params.add('start_date=$startDate');
      if (endDate != null) params.add('end_date=$endDate');
      if (params.isNotEmpty) url += '?${params.join('&')}';
      final resp = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept-Language': lang,
        },
      );
      if (resp.statusCode == 200) {
        return await compute(jsonDecode, resp.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  /// PRO gelişmiş metrikler → `GET /api/analytics/pro/metrics`
  static Future<Map<String, dynamic>?> getProMetrics() async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      final lang = await _lang();
      final resp = await http.get(
        Uri.parse('$kBaseUrl/analytics/pro/metrics'),
        headers: {'Authorization': 'Bearer $token', 'Accept-Language': lang},
      );
      if (resp.statusCode == 200) {
        return await compute(jsonDecode, resp.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  /// Sektörel pazar trendleri → `GET /api/analytics/market-trends`
  static Future<Map<String, dynamic>?> getMarketTrends() async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      final lang = await _lang();
      final resp = await http.get(
        Uri.parse('$kBaseUrl/analytics/market-trends'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'Accept-Language': lang,
        },
      );
      if (resp.statusCode == 200) {
        return await compute(jsonDecode, resp.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  /// Aylık blast kredi durumu → `GET /api/leads/blast-credits`
  static Future<Map<String, dynamic>?> getBlastCredits() async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      final resp = await http.get(
        Uri.parse('$kBaseUrl/leads/blast-credits'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) return await compute(jsonDecode, resp.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  static Future<Map<String, dynamic>?> getBoostCredits() async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      final resp = await http.get(
        Uri.parse('$kBaseUrl/ads/boost-credits'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) return await compute(jsonDecode, resp.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  static Future<Map<String, dynamic>?> getAiPriceCredits() async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      final resp = await http.get(
        Uri.parse('$kBaseUrl/analytics/ai-price-credits'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) return await compute(jsonDecode, resp.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  static Future<Map<String, dynamic>?> getAiDescCredits() async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      final resp = await http.get(
        Uri.parse('$kBaseUrl/listings/ai-desc-credits'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) return await compute(jsonDecode, resp.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  static Future<Map<String, dynamic>?> getReactivationCredits() async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      final resp = await http.get(
        Uri.parse('$kBaseUrl/analytics/reactivation-credits'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) return await compute(jsonDecode, resp.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  /// Feed istatistikleri → `GET /api/analytics/my-feed-stats?days=7|30`
  static Future<Map<String, dynamic>?> getFeedStats({int days = 7}) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      final resp = await http.get(
        Uri.parse('$kBaseUrl/analytics/my-feed-stats?days=$days'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) return await compute(jsonDecode, resp.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  /// Yayın sonu satıcı raporu → `GET /api/analytics/seller-report/{streamId}`
  static Future<Map<String, dynamic>?> getSellerReport(int streamId) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      final lang = await _lang();
      final resp = await http.get(
        Uri.parse('$kBaseUrl/analytics/seller-report/$streamId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'Accept-Language': lang,
        },
      );
      if (resp.statusCode == 200) {
        return await compute(jsonDecode, resp.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  /// Mobil etkileşim sinyali → `/api/analytics/interaction`. Fire-and-forget.
  static Future<void> logInteraction({
    required int itemId,
    required String itemType,
    required String interactionType,
    int? ownerId,
    double? durationSeconds,
    double? pricePoint,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final myUserId = await StorageService.getCurrentUserId();
      if (ownerId != null && myUserId == ownerId) return; // Kendi içeriği, analitik atla

      final token = await StorageService.getToken();
      final headers = {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };
      final body = <String, dynamic>{
        'item_id': itemId,
        'item_type': itemType,
        'interaction_type': interactionType,
        'duration_seconds': ?durationSeconds,
        'price_point': ?pricePoint,
        'metadata': ?metadata,
        // JWT expire olsa bile user_id kaybolmasın diye body'ye de yaz
        'user_id': ?myUserId,
      };
      http
          .post(Uri.parse('$kBaseUrl/analytics/interaction'),
              headers: headers, body: jsonEncode(body))
          .catchError((_) => http.Response('', 500));
    } catch (_) {}
  }

  /// Keşfet bölümü yüklendiğinde görünen ilanları toplu impression olarak loglar.
  /// Fire-and-forget; ağ hatası sessizce görmezden gelinir.
  static Future<void> logListingImpressions({
    required List<int> listingIds,
    required String section,
  }) async {
    if (listingIds.isEmpty) return;
    try {
      final myUserId = await StorageService.getCurrentUserId();
      final token = await StorageService.getToken();
      if (token == null) return;
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };
      final events = listingIds.map((id) => {
        'item_id': id,
        'item_type': 'listing',
        'interaction_type': 'listing_impression',
        'metadata': {'section': section},
        if (myUserId != null) 'user_id': myUserId,
      }).toList();
      for (final body in events) {
        http
            .post(Uri.parse('$kBaseUrl/analytics/interaction'),
                headers: headers, body: jsonEncode(body))
            .catchError((_) => http.Response('', 500));
      }
    } catch (_) {}
  }

  /// Arama sorgusu → `/api/analytics/track-search`. Fire-and-forget.
  static Future<void> trackSearch({
    required String query,
    String category = '',
    int resultCount = 0,
  }) async {
    try {
      final token = await StorageService.getToken();
      final headers = {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };
      http
          .post(
            Uri.parse('$kBaseUrl/analytics/track-search'),
            headers: headers,
            body: jsonEncode({
              'query': query,
              'category': category,
              'result_count': resultCount,
            }),
          )
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
        return await compute(jsonDecode, resp.body) as Map<String, dynamic>;
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

  static Future<void> trackAdImpression(int campaignId) async {
    if (_impressedCampaigns.contains(campaignId)) return;
    _impressedCampaigns.add(campaignId);
    try {
      final token = await StorageService.getToken();
      http
          .post(
            Uri.parse('$kBaseUrl/ads/impression/$campaignId'),
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
          )
          .catchError((_) => http.Response('', 500));
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> getVideoRoi({String? startDate, String? endDate, String? category}) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      final lang = await _lang();
      var url = '$kBaseUrl/analytics/video-roi';
      final params = <String>[];
      if (startDate != null) params.add('start_date=$startDate');
      if (endDate != null) params.add('end_date=$endDate');
      if (category != null && category.isNotEmpty) params.add('category=$category');
      if (params.isNotEmpty) url += '?${params.join('&')}';
      final resp = await http.get(Uri.parse(url), headers: {'Authorization': 'Bearer $token', 'Accept-Language': lang});
      if (resp.statusCode == 200) return await compute(jsonDecode, resp.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  static Future<Map<String, dynamic>?> getGalleryStats({String? startDate, String? endDate, String? category}) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      final lang = await _lang();
      var url = '$kBaseUrl/analytics/gallery-stats';
      final params = <String>[];
      if (startDate != null) params.add('start_date=$startDate');
      if (endDate != null) params.add('end_date=$endDate');
      if (category != null && category.isNotEmpty) params.add('category=$category');
      if (params.isNotEmpty) url += '?${params.join('&')}';
      final resp = await http.get(Uri.parse(url), headers: {'Authorization': 'Bearer $token', 'Accept-Language': lang});
      if (resp.statusCode == 200) return await compute(jsonDecode, resp.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  static Future<Map<String, dynamic>?> getVideoPerformance({String? startDate, String? endDate, String? category}) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      final lang = await _lang();
      var url = '$kBaseUrl/analytics/video-performance';
      final params = <String>[];
      if (startDate != null) params.add('start_date=$startDate');
      if (endDate != null) params.add('end_date=$endDate');
      if (category != null && category.isNotEmpty) params.add('category=$category');
      if (params.isNotEmpty) url += '?${params.join('&')}';
      final resp = await http.get(Uri.parse(url), headers: {'Authorization': 'Bearer $token', 'Accept-Language': lang});
      if (resp.statusCode == 200) return await compute(jsonDecode, resp.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  static Future<Map<String, dynamic>?> getDemandRadar({int days = 7}) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      final lang = await _lang();
      final resp = await http.get(
        Uri.parse('$kBaseUrl/analytics/demand-radar?days=$days'),
        headers: {'Authorization': 'Bearer $token', 'Accept-Language': lang},
      );
      if (resp.statusCode == 200) return await compute(jsonDecode, resp.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
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

  /// Rakip Fiyat Radarı → `/api/analytics/competitor-radar/{listing_id}`
  static Future<Map<String, dynamic>?> competitorRadar(int listingId) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      final lang = await _lang();
      final resp = await http.get(
        Uri.parse('$kBaseUrl/analytics/competitor-radar/$listingId'),
        headers: {'Authorization': 'Bearer $token', 'Accept-Language': lang},
      );
      if (resp.statusCode == 200) return await compute(jsonDecode, resp.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  /// Satış Hızı → `/api/analytics/category-velocity`
  static Future<Map<String, dynamic>?> categoryVelocity(String category, {int? listingId}) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      final lang = await _lang();
      var url = '$kBaseUrl/analytics/category-velocity?category=${Uri.encodeComponent(category)}';
      if (listingId != null) url += '&listing_id=$listingId';
      final resp = await http.get(Uri.parse(url), headers: {'Authorization': 'Bearer $token', 'Accept-Language': lang});
      if (resp.statusCode == 200) return await compute(jsonDecode, resp.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  /// Retargeting kitlesi → `GET /api/leads/retargeting-audience/{listing_id}`
  static Future<Map<String, dynamic>?> retargetingAudience(int listingId) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      final resp = await http.get(
        Uri.parse('$kBaseUrl/leads/retargeting-audience/$listingId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) return await compute(jsonDecode, resp.body) as Map<String, dynamic>;
      if (resp.statusCode == 403) return {'error': 'pro_required'};
    } catch (_) {}
    return null;
  }

  /// Retargeting blast gönder → `POST /api/leads/send-retargeting`
  static Future<Map<String, dynamic>?> sendRetargeting({
    required int listingId,
    required int estimatedAudience,
    required int estimatedCost,
    int? recipientCount,
  }) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      final resp = await http.post(
        Uri.parse('$kBaseUrl/leads/send-retargeting'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'listing_id': listingId,
          'estimated_audience': estimatedAudience,
          'estimated_cost': estimatedCost,
          'recipient_count': ?recipientCount,
        }),
      );
      if (resp.statusCode == 200 || resp.statusCode == 202) {
        return await compute(jsonDecode, resp.body) as Map<String, dynamic>;
      }
      try {
        final body = await compute(jsonDecode, resp.body) as Map<String, dynamic>;
        return {'error': body['detail'] ?? 'Blast gönderilemedi.'};
      } catch (_) {}
      return {'error': 'Blast gönderilemedi.'};
    } catch (_) {}
    return null;
  }

  /// İlanlar için kitle büyüklüğü tahmini → `GET /api/listings/{listingId}/audience-estimate`
  static Future<Map<String, dynamic>?> estimateAudienceForListing(int listingId) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      final uri = Uri.parse('$kBaseUrl/listings/$listingId/audience-estimate');
      final resp = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) {
        return await compute(jsonDecode, resp.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  /// İlan başına 24h bildirim cooldown süresi (saniye). 0 = gönderim yapılabilir.
  static Future<int> getNotificationCooldown(int listingId) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return 0;
      final resp = await http.get(
        Uri.parse('$kBaseUrl/listings/$listingId/notification-cooldown'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        return (data['seconds_remaining'] as num?)?.toInt() ?? 0;
      }
    } catch (_) {}
    return 0;
  }

  /// İlanlar için toplu kitle bildirimi gönder → `POST /api/listings/{listingId}/send-mass-notification`
  /// Dönen map: success → blast result; cooldown → {'cooldown': true, 'seconds_remaining': N}; error → {'error': msg}
  static Future<Map<String, dynamic>?> sendMassNotificationForListing({
    required int listingId,
    required int estimatedCost,
    int? recipientCount,
  }) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      final resp = await http.post(
        Uri.parse('$kBaseUrl/listings/$listingId/send-mass-notification'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'estimated_cost': estimatedCost,
          'recipient_count': recipientCount,
        }),
      );
      if (resp.statusCode == 200 || resp.statusCode == 202) {
        return await compute(jsonDecode, resp.body) as Map<String, dynamic>;
      }
      try {
        final body = await compute(jsonDecode, resp.body) as Map<String, dynamic>;
        if (resp.statusCode == 429) {
          final detail = body['detail'];
          if (detail is Map && detail['code'] == 'cooldown') {
            return {'cooldown': true, 'seconds_remaining': detail['seconds_remaining'] ?? 86400};
          }
        }
        return {'error': body['detail'] ?? 'Bildirim gönderilemedi.'};
      } catch (_) {}
      return {'error': 'Bildirim gönderilemedi.'};
    } catch (_) {}
    return null;
  }

  static Future<Map<String, dynamic>> getMassNotificationReport({int? listingId}) async {
    final token = await StorageService.getToken();
    if (token == null) throw Exception('Yetkilendirme hatası' /* AppLocalizations handled in UI */);

    final uri = listingId != null
        ? Uri.parse('$kBaseUrl/leads/mass-notification-report?listing_id=$listingId')
        : Uri.parse('$kBaseUrl/leads/mass-notification-report');

    final response = await http.get(uri, headers: {'Authorization': 'Bearer $token'});

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Rapor alınamadı: ${response.body}');
    }
  }
  
  static Future<void> trackCampaignClick(int campaignId) async {
    final token = await StorageService.getToken();
    if (token == null) return;

    try {
      await http.post(
        Uri.parse('$kBaseUrl/leads/campaign/$campaignId/click'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );
    } catch (e) {
      debugPrint('Click tracking failed: $e');
    }
  }

  static Future<Map<String, dynamic>?> demandTrends({int weeks = 8}) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      final lang = await _lang();
      final resp = await http.get(
        Uri.parse('$kBaseUrl/analytics/demand-trends?weeks=$weeks'),
        headers: {'Authorization': 'Bearer $token', 'Accept-Language': lang},
      );
      if (resp.statusCode == 200) {
        return await compute(jsonDecode, resp.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
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
      AnalyticsService.trackEvent('screen_view', {'screen_name': newRoute.settings.name ?? 'unknown'});
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

