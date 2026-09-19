import 'package:flutter/foundation.dart' show compute;
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/api_client.dart';
import '../core/app_exception.dart';
import '../models/pro_insights_data.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

class AiInsufficientTuciException implements Exception {
  final String detail;
  const AiInsufficientTuciException(this.detail);
}

class AnalyticsService {
  final ApiClient _api;
  AnalyticsService(this._api);
  late final _apiService = ApiService(_api);

  // Static session state — app-wide, single instance
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

  Future<void> init() async {
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

  Future<bool?> getConsentStatus() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('teqlif_tracking_consent');
  }

  Future<void> setConsent(bool accepted) async {
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
  Future<Map<String, dynamic>?> getAudienceSize({
    required String title,
    String category = '',
    String subcategory = '',
  }) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      final uri = Uri.parse('${_api.config.baseUrl}/leads/audience-size').replace(
        queryParameters: {
          'title': title,
          if (category.isNotEmpty) 'category': category,
          if (subcategory.isNotEmpty) 'subcategory': subcategory,
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
  Future<Map<String, dynamic>?> sendLeadBlast({
    required String title,
    required String category,
    String subcategory = '',
    required int estimatedCost,
    int? listingId,
    int? streamId,
    int? recipientCount,
  }) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      final resp = await http.post(
        Uri.parse('${_api.config.baseUrl}/leads/send-blast'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'title': title,
          'category': category,
          'subcategory': subcategory,
          'estimated_cost': estimatedCost,
          'listing_id': ?listingId,
          'stream_id': ?streamId,
          'recipient_count': ?recipientCount,
        }),
      );
      if (resp.statusCode == 202) {
        return await compute(jsonDecode, resp.body) as Map<String, dynamic>;
      }
      try {
        final body = await compute(jsonDecode, resp.body) as Map<String, dynamic>;
        final errMap = body['error'] as Map?;
        final msg = errMap?['message'] as String? ?? body['detail'] as String? ?? 'Duyuru gönderilemedi.';
        return {'error': msg};
      } catch (_) {}
      return {'error': 'Duyuru gönderilemedi.'};
    } catch (_) {}
    return null;
  }

  /// Yapay Zeka fiyatlama tahmini → `POST /api/analytics/price-estimate`
  /// Throws [AiInsufficientTuciException] on HTTP 402 (INSUFFICIENT_FUNDS).
  /// Returns null on other errors.
  Future<Map<String, dynamic>?> getPriceEstimate({
    required String title,
    required String description,
    required String category,
    String subcategory = '',
    String city = '',
    String condition = '',
    Map<String, dynamic>? extraFields,
    int? excludeListingId,
  }) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      final headers = await _api.buildApiHeaders(token, json: true);
      return await _api.call(
        () => http.post(
          Uri.parse('${_api.config.baseUrl}/analytics/price-estimate'),
          headers: headers,
          body: jsonEncode({
            'title': title,
            'description': description,
            'category': category,
            if (subcategory.isNotEmpty) 'subcategory': subcategory,
            'city': city,
            if (condition.isNotEmpty) 'condition': condition,
            if (extraFields != null && extraFields.isNotEmpty)
              'extra_fields': extraFields,
            if (excludeListingId != null && excludeListingId > 0)
              'exclude_listing_id': excludeListingId,
          }),
        ),
      );
    } on AppException catch (e) {
      if (e.code == 'INSUFFICIENT_FUNDS') {
        throw AiInsufficientTuciException(e.message);
      }
      debugPrint('[AnalyticsService] getPriceEstimate hata: ${e.message}');
    }
    return null;
  }

  /// Pro satıcı kapsamlı analitik — SWR stream (cache → network).
  /// Önce Hive cache'den anlık emit, sonra `/api/analytics/pro-insights`'tan taze veri.
  Stream<ProInsightsData> getProInsights({
    String? startDate,
    String? endDate,
    bool bypassCache = false,
  }) {
    var url = '${_api.config.baseUrl}/analytics/pro-insights';
    final params = <String>[];
    if (startDate != null) params.add('start_date=$startDate');
    if (endDate != null) params.add('end_date=$endDate');
    if (params.isNotEmpty) url += '?${params.join('&')}';
    return _apiService.get<ProInsightsData>(
      url: url,
      cacheKey: 'pro_insights_${startDate ?? ''}_${endDate ?? ''}',
      fromJson: (raw) => ProInsightsData.fromJson(raw as Map<String, dynamic>),
      bypassCache: bypassCache,
      cacheTtl: const Duration(minutes: 10),
      timeout: const Duration(seconds: 20),
    );
  }

  /// PRO gelişmiş metrikler — SWR stream (cache → network).
  Stream<ProMetrics> getProMetrics({bool bypassCache = false}) =>
      _apiService.get<ProMetrics>(
        url: '${_api.config.baseUrl}/analytics/pro/metrics',
        cacheKey: 'pro_metrics',
        fromJson: (raw) => ProMetrics.fromJson(raw as Map<String, dynamic>),
        bypassCache: bypassCache,
        cacheTtl: const Duration(minutes: 10),
        timeout: const Duration(seconds: 20),
      );

  /// Sektörel pazar trendleri → `GET /api/analytics/market-trends`
  Future<Map<String, dynamic>?> getMarketTrends() async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      final resp = await http.get(
        Uri.parse('${_api.config.baseUrl}/analytics/market-trends'),
        headers: await _api.buildApiHeaders(token, json: true),
      );
      if (resp.statusCode == 200) {
        return await compute(jsonDecode, resp.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  /// Aylık blast kredi durumu → `GET /api/leads/blast-credits`
  Future<Map<String, dynamic>?> getBlastCredits() async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      final resp = await http.get(
        Uri.parse('${_api.config.baseUrl}/leads/blast-credits'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) return await compute(jsonDecode, resp.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> getBoostCredits() async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      final resp = await http.get(
        Uri.parse('${_api.config.baseUrl}/ads/boost-credits'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) return await compute(jsonDecode, resp.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> getAiPriceCredits() async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      final resp = await http.get(
        Uri.parse('${_api.config.baseUrl}/analytics/ai-price-credits'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) return await compute(jsonDecode, resp.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> getAiDescCredits() async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      final resp = await http.get(
        Uri.parse('${_api.config.baseUrl}/listings/ai-desc-credits'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) return await compute(jsonDecode, resp.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> getReactivationCredits() async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      final resp = await http.get(
        Uri.parse('${_api.config.baseUrl}/analytics/reactivation-credits'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) return await compute(jsonDecode, resp.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  /// Feed istatistikleri → `GET /api/analytics/my-feed-stats?days=7|30`
  Future<Map<String, dynamic>?> getFeedStats({int days = 7}) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      final resp = await http.get(
        Uri.parse('${_api.config.baseUrl}/analytics/my-feed-stats?days=$days'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) return await compute(jsonDecode, resp.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  /// Yayın sonu satıcı raporu → `GET /api/analytics/seller-report/{streamId}`
  Future<Map<String, dynamic>?> getSellerReport(int streamId) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      final resp = await http.get(
        Uri.parse('${_api.config.baseUrl}/analytics/seller-report/$streamId'),
        headers: await _api.buildApiHeaders(token, json: true),
      );
      if (resp.statusCode == 200) {
        return await compute(jsonDecode, resp.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  /// Mobil etkileşim sinyali → `/api/analytics/interaction`. Fire-and-forget.
  Future<void> logInteraction({
    required int itemId,
    required String itemType,
    required String interactionType,
    int? ownerId,
    double? durationSeconds,
    double? pricePoint,
    String subcategory = '',
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
      final mergedMeta = <String, dynamic>{
        if (metadata != null) ...metadata,
        if (subcategory.isNotEmpty) 'subcategory': subcategory,
      };
      final body = <String, dynamic>{
        'item_id': itemId,
        'item_type': itemType,
        'interaction_type': interactionType,
        'duration_seconds': ?durationSeconds,
        'price_point': ?pricePoint,
        if (mergedMeta.isNotEmpty) 'metadata': mergedMeta,
        // JWT expire olsa bile user_id kaybolmasın diye body'ye de yaz
        'user_id': ?myUserId,
      };
      http
          .post(Uri.parse('${_api.config.baseUrl}/analytics/interaction'),
              headers: headers, body: jsonEncode(body))
          .catchError((_) => http.Response('', 500));
    } catch (_) {}
  }

  /// Keşfet bölümü yüklendiğinde görünen ilanları toplu impression olarak loglar.
  /// Fire-and-forget; ağ hatası sessizce görmezden gelinir.
  Future<void> logListingImpressions({
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
        'user_id': ?myUserId,
      }).toList();
      for (final body in events) {
        http
            .post(Uri.parse('${_api.config.baseUrl}/analytics/interaction'),
                headers: headers, body: jsonEncode(body))
            .catchError((_) => http.Response('', 500));
      }
    } catch (_) {}
  }

  /// Arama sorgusu → `/api/analytics/track-search`. Fire-and-forget.
  Future<void> trackSearch({
    required String query,
    String category = '',
    String subcategory = '',
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
            Uri.parse('${_api.config.baseUrl}/analytics/track-search'),
            headers: headers,
            body: jsonEncode({
              'query': query,
              'category': category,
              'subcategory': subcategory,
              'result_count': resultCount,
            }),
          )
          .catchError((_) => http.Response('', 500));
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> getCampaignReport(int campaignId) async {
    try {
      final token = await StorageService.getToken();
      final resp = await http.get(
        Uri.parse('${_api.config.baseUrl}/ads/campaigns/$campaignId/report'),
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

  Future<void> trackAdClick(int campaignId) async {
    try {
      final token = await StorageService.getToken();
      http
          .post(
            Uri.parse('${_api.config.baseUrl}/ads/click/$campaignId'),
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
          )
          .catchError((_) => http.Response('', 500));
    } catch (_) {}
  }

  Future<void> trackAdImpression(int campaignId) async {
    if (_impressedCampaigns.contains(campaignId)) return;
    _impressedCampaigns.add(campaignId);
    try {
      final token = await StorageService.getToken();
      http
          .post(
            Uri.parse('${_api.config.baseUrl}/ads/impression/$campaignId'),
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
          )
          .catchError((_) => http.Response('', 500));
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> getVideoRoi({String? startDate, String? endDate, String? category, String? subcategory}) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      var url = '${_api.config.baseUrl}/analytics/video-roi';
      final params = <String>[];
      if (startDate != null) params.add('start_date=$startDate');
      if (endDate != null) params.add('end_date=$endDate');
      if (category != null && category.isNotEmpty) params.add('category=$category');
      if (subcategory != null && subcategory.isNotEmpty) params.add('subcategory=$subcategory');
      if (params.isNotEmpty) url += '?${params.join('&')}';
      final resp = await http.get(Uri.parse(url), headers: await _api.buildApiHeaders(token));
      if (resp.statusCode == 200) return await compute(jsonDecode, resp.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> getGalleryStats({String? startDate, String? endDate, String? category, String? subcategory}) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      var url = '${_api.config.baseUrl}/analytics/gallery-stats';
      final params = <String>[];
      if (startDate != null) params.add('start_date=$startDate');
      if (endDate != null) params.add('end_date=$endDate');
      if (category != null && category.isNotEmpty) params.add('category=$category');
      if (subcategory != null && subcategory.isNotEmpty) params.add('subcategory=$subcategory');
      if (params.isNotEmpty) url += '?${params.join('&')}';
      final resp = await http.get(Uri.parse(url), headers: await _api.buildApiHeaders(token));
      if (resp.statusCode == 200) return await compute(jsonDecode, resp.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> getVideoPerformance({String? startDate, String? endDate, String? category, String? subcategory}) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      var url = '${_api.config.baseUrl}/analytics/video-performance';
      final params = <String>[];
      if (startDate != null) params.add('start_date=$startDate');
      if (endDate != null) params.add('end_date=$endDate');
      if (category != null && category.isNotEmpty) params.add('category=$category');
      if (subcategory != null && subcategory.isNotEmpty) params.add('subcategory=$subcategory');
      if (params.isNotEmpty) url += '?${params.join('&')}';
      final resp = await http.get(Uri.parse(url), headers: await _api.buildApiHeaders(token));
      if (resp.statusCode == 200) return await compute(jsonDecode, resp.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> getDemandRadar({int days = 7}) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      final resp = await http.get(
        Uri.parse('${_api.config.baseUrl}/analytics/demand-radar?days=$days'),
        headers: await _api.buildApiHeaders(token),
      );
      if (resp.statusCode == 200) return await compute(jsonDecode, resp.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  Future<void> trackEvent(String eventType, [Map<String, dynamic>? metadata]) async {
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

      final uri = Uri.parse('${_api.config.baseUrl}/analytics/track');

      // Fire and forget
      http.post(uri, headers: headers, body: jsonEncode(payload)).catchError((_) => http.Response('', 500));
    } catch (_) {
      debugPrint('[ANALYTICS] Error tracking event: $eventType');
    }
  }

  /// Rakip Fiyat Radarı → `/api/analytics/competitor-radar/{listing_id}`
  Future<Map<String, dynamic>?> competitorRadar(int listingId) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      final resp = await http.get(
        Uri.parse('${_api.config.baseUrl}/analytics/competitor-radar/$listingId'),
        headers: await _api.buildApiHeaders(token),
      );
      if (resp.statusCode == 200) return await compute(jsonDecode, resp.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  /// Satış Hızı → `/api/analytics/category-velocity`
  Future<Map<String, dynamic>?> categoryVelocity(String category, {int? listingId}) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      var url = '${_api.config.baseUrl}/analytics/category-velocity?category=${Uri.encodeComponent(category)}';
      if (listingId != null) url += '&listing_id=$listingId';
      final resp = await http.get(Uri.parse(url), headers: await _api.buildApiHeaders(token));
      if (resp.statusCode == 200) return await compute(jsonDecode, resp.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  /// Retargeting kitlesi → `GET /api/leads/retargeting-audience/{listing_id}`
  Future<Map<String, dynamic>?> retargetingAudience(int listingId) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      final resp = await http.get(
        Uri.parse('${_api.config.baseUrl}/leads/retargeting-audience/$listingId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) return await compute(jsonDecode, resp.body) as Map<String, dynamic>;
      if (resp.statusCode == 403) return {'error': 'pro_required'};
    } catch (_) {}
    return null;
  }

  /// Retargeting blast gönder → `POST /api/leads/send-retargeting`
  Future<Map<String, dynamic>?> sendRetargeting({
    required int listingId,
    required int estimatedAudience,
    required int estimatedCost,
    int? recipientCount,
  }) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      final resp = await http.post(
        Uri.parse('${_api.config.baseUrl}/leads/send-retargeting'),
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
        final errMap = body['error'] as Map?;
        final msg = errMap?['message'] as String? ?? body['detail'] as String? ?? 'Blast gönderilemedi.';
        return {'error': msg};
      } catch (_) {}
      return {'error': 'Blast gönderilemedi.'};
    } catch (_) {}
    return null;
  }

  /// İlanlar için kitle büyüklüğü tahmini → `GET /api/listings/{listingId}/audience-estimate`
  Future<Map<String, dynamic>?> estimateAudienceForListing(int listingId) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      final uri = Uri.parse('${_api.config.baseUrl}/listings/$listingId/audience-estimate');
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
  Future<int> getNotificationCooldown(int listingId) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return 0;
      final resp = await http.get(
        Uri.parse('${_api.config.baseUrl}/listings/$listingId/notification-cooldown'),
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
  Future<Map<String, dynamic>?> sendMassNotificationForListing({
    required int listingId,
    required int estimatedCost,
    int? recipientCount,
  }) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      final resp = await http.post(
        Uri.parse('${_api.config.baseUrl}/listings/$listingId/send-mass-notification'),
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
        final errMap = body['error'] as Map?;
        if (resp.statusCode == 429 && errMap?['code'] == 'COOLDOWN') {
          return {
            'cooldown': true,
            'seconds_remaining': errMap?['seconds_remaining'] ?? 86400,
          };
        }
        final msg = errMap?['message'] as String? ?? body['detail'] as String? ?? 'Bildirim gönderilemedi.';
        return {'error': msg};
      } catch (_) {}
      return {'error': 'Bildirim gönderilemedi.'};
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>> getMassNotificationReport({int? listingId}) async {
    final token = await StorageService.getToken();
    if (token == null) throw const AppException('Oturumunuz sona ermiş.', code: 'UNAUTHORIZED', statusCode: 401);

    final uri = listingId != null
        ? Uri.parse('${_api.config.baseUrl}/leads/mass-notification-report?listing_id=$listingId')
        : Uri.parse('${_api.config.baseUrl}/leads/mass-notification-report');

    return _api.call(() => http.get(uri, headers: {'Authorization': 'Bearer $token'}));
  }

  Future<void> trackCampaignClick(int campaignId) async {
    final token = await StorageService.getToken();
    if (token == null) return;

    try {
      await http.post(
        Uri.parse('${_api.config.baseUrl}/leads/campaign/$campaignId/click'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );
    } catch (e) {
      debugPrint('Click tracking failed: $e');
    }
  }

  Future<Map<String, dynamic>?> demandTrends({int weeks = 8, String? category, String? subcategory}) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      var url = '${_api.config.baseUrl}/analytics/demand-trends?weeks=$weeks';
      if (category != null && category.isNotEmpty) url += '&category=${Uri.encodeComponent(category)}';
      if (subcategory != null && subcategory.isNotEmpty) url += '&subcategory=${Uri.encodeComponent(subcategory)}';
      final resp = await http.get(
        Uri.parse(url),
        headers: await _api.buildApiHeaders(token),
      );
      if (resp.statusCode == 200) {
        return await compute(jsonDecode, resp.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }
}

final analyticsServiceProvider = Provider<AnalyticsService>((ref) =>
    AnalyticsService(ref.watch(apiClientProvider)));

// --- Screen Tracking Observer ---
class AnalyticsRouteObserver extends RouteObserver<PageRoute<dynamic>> {
  final AnalyticsService _service;
  AnalyticsRouteObserver(this._service);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (route is PageRoute) {
      _service.trackEvent('screen_view', {'screen_name': route.settings.name ?? 'unknown'});
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute is PageRoute) {
      _service.trackEvent('screen_view', {'screen_name': newRoute.settings.name ?? 'unknown'});
    }
  }
}

// --- App Time Spent Tracking Observer ---
class AnalyticsLifecycleObserver extends WidgetsBindingObserver {
  final AnalyticsService _service;
  AnalyticsLifecycleObserver(this._service);

  DateTime? _appStartTime;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _appStartTime = DateTime.now();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      if (_appStartTime != null) {
        final timeSpent = DateTime.now().difference(_appStartTime!).inSeconds;
        if (timeSpent > 2) {
          _service.trackEvent('time_spent', {'seconds': timeSpent});
        }
        _appStartTime = null;
      }
    }
  }
}
