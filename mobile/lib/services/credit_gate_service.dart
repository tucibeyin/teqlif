import 'dart:convert';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../core/network/api_client.dart';
import '../models/credit_gate_data.dart';
import '../services/analytics_service.dart';
import '../services/storage_service.dart';

/// Tüm kredili feature'ların iş mantığını tek yerden yönetir.
///
/// Feature başına ne yapılacağı (hangi endpoint, hangi parametreler)
/// bu serviste tanımlıdır. Ekranlar sadece [execute] çağırır.
class CreditGateService {
  final AnalyticsService _analytics;
  final ApiClient _api;

  CreditGateService(this._analytics, this._api);

  // ── Veri çekme ──────────────────────────────────────────────────────────────

  Future<CreditGateData?> fetchData(
    CreditFeature feature, {
    int? listingId,
  }) =>
      _analytics.fetchCreditGateData(feature, listingId: listingId);

  // ── Execution ───────────────────────────────────────────────────────────────

  /// Feature'ı çalıştır ve sonucu döndür.
  ///
  /// [count] — yalnızca blast için kullanılır; diğerleri 1 kabul eder.
  Future<CreditGateResult> execute(
    CreditFeature feature, {
    int? listingId,
    int count = 1,
  }) async {
    switch (feature) {
      case CreditFeature.boost:
        return _executeBoost(listingId!);
      case CreditFeature.blast:
        return _executeBlast(listingId!, count);
      case CreditFeature.reactivation:
        return _executeReactivation(listingId!);
      case CreditFeature.aiDesc:
        // Kasıtlı asimetri: aiDesc execution bu serviste yapılmaz.
        // Kredi düşümü generate endpoint'inde server-side gerçekleşir.
        // generate çağrısı aiDescProvider state machine'i (streaming, typing animasyonu)
        // tarafından yönetildiği için ekranda `result.success` sonrasında tetiklenir.
        // Diğer feature'lardan farkı: gate yalnızca kullanıcı onayını toplar.
        return CreditGateResult.success();
    }
  }

  // ── Özel execution'lar ──────────────────────────────────────────────────────

  Future<CreditGateResult> _executeBoost(int listingId) async {
    final token = await StorageService.getToken();
    if (token == null) return CreditGateResult.failure('errorGeneric');
    try {
      final resp = await http.post(
        Uri.parse('${_api.config.baseUrl}/ads/campaigns'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'listing_id': listingId,
          'total_budget': 50,
          'cpc_bid': 1,
        }),
      );
      if (resp.statusCode == 201) {
        final data = await compute(jsonDecode, resp.body) as Map<String, dynamic>;
        return CreditGateResult.success({
          'id': data['id'],
          'is_free': data['is_free'] == true,
        });
      }
      final body = await compute(jsonDecode, resp.body) as Map<String, dynamic>;
      final detail = body['detail'] as String?;
      if (detail != null) {
        return CreditGateResult.failureWithPayload({'detail': detail});
      }
      return CreditGateResult.failure('boostErrorDefault');
    } catch (_) {
      return CreditGateResult.failure('boostErrorConnection');
    }
  }

  Future<CreditGateResult> _executeBlast(int listingId, int count) async {
    final result = await _analytics.sendMassNotificationForListing(
      listingId: listingId,
      estimatedCost: count * 10,
      recipientCount: count,
    );
    if (result == null) return CreditGateResult.failure('audienceMassSendError');
    if (result['cooldown'] == true) {
      return CreditGateResult.failureWithPayload({
        'cooldown': true,
        'seconds_remaining':
            (result['seconds_remaining'] as num?)?.toInt() ?? 86400,
      });
    }
    if (result.containsKey('error')) {
      return CreditGateResult.failureWithPayload({'detail': result['error']});
    }
    return CreditGateResult.success(result);
  }

  Future<CreditGateResult> _executeReactivation(int listingId) async {
    final token = await StorageService.getToken();
    if (token == null) return CreditGateResult.failure('errorGeneric');
    try {
      final resp = await http.patch(
        Uri.parse('${_api.config.baseUrl}/listings/$listingId/toggle'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) return CreditGateResult.success();
      if (resp.statusCode == 402) {
        return CreditGateResult.failure('listingReactivateInsufficientBalance');
      }
      return CreditGateResult.failure('errorGeneric');
    } catch (_) {
      return CreditGateResult.failure('errorGeneric');
    }
  }
}

final creditGateServiceProvider = Provider<CreditGateService>((ref) {
  return CreditGateService(
    ref.watch(analyticsServiceProvider),
    ref.watch(apiClientProvider),
  );
});
