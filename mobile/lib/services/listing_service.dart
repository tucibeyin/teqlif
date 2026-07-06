import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sentry_flutter/sentry_flutter.dart';
import '../config/api.dart';
import '../core/app_exception.dart';
import '../models/listing_offer.dart';
import 'api_service.dart';
import 'storage_service.dart';

class ListingService {
  // Uygulama oturumu boyunca beğeni durumunu tutan merkezi cache.
  // Herhangi bir ekrandan toggleLike / setLikeCache çağrılınca güncellenir;
  // _GridItem.initState önce buraya bakarak en güncel durumu okur.
  static final Map<int, bool> _likeCache = {};

  static bool? getCachedLike(int id) => _likeCache[id];

  static void setLikeCache(int id, bool liked) => _likeCache[id] = liked;

  static Future<Map<String, String>> _headers({bool auth = true}) async {
    final token = auth ? await StorageService.getToken() : null;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// ClickHouse telemetri tabanlı epsilon-greedy kişiselleştirilmiş feed.
  ///
  /// SWR Stream: ilk event Hive cache'ten (anlık), ikinci event API'den (taze).
  /// Giriş yapılmamışsa tek `[]` emit edilir.
  /// [bypassCache]: `true` ise cache okuma atlanır (pull-to-refresh).
  static Stream<List<Map<String, dynamic>>> getPersonalizedFeed({
    int limit = 10,
    bool bypassCache = false,
  }) async* {
    final token = await StorageService.getToken();
    if (token == null) { yield []; return; }

    yield* ApiService.get<List<Map<String, dynamic>>>(
      url: '$kBaseUrl/feed/personalized?limit=$limit',
      cacheKey: 'feed_personalized',
      cacheTtl: const Duration(minutes: 10),
      bypassCache: bypassCache,
      fromJson: (raw) => (raw as List).cast<Map<String, dynamic>>(),
    );
  }

  static Future<Map<String, dynamic>?> getReactivationCost(int listingId) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return null;
      final resp = await http.get(
        Uri.parse('$kBaseUrl/listings/$listingId/reactivation-cost'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) return await compute(jsonDecode, resp.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  static Future<Map<String, dynamic>?> getListingById(int listingId) async {
    try {
      final resp = await http.get(
        Uri.parse('$kBaseUrl/listings/$listingId'),
        headers: await _headers(auth: true),
      );
      if (resp.statusCode == 200) {
        return await compute(jsonDecode, resp.body) as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// İlana ait teklifleri miktara göre büyükten küçüğe döner.
  static Future<List<ListingOffer>> getOffers(int listingId) async {
    try {
      final resp = await http.get(
        Uri.parse('$kBaseUrl/listings/$listingId/offers'),
        headers: await _headers(auth: true),
      );
      if (resp.statusCode == 200) {
        final data = await compute(jsonDecode, resp.body) as List;
        return data
            .cast<Map<String, dynamic>>()
            .map(ListingOffer.fromJson)
            .toList();
      }
      debugPrint('[ListingService] getOffers HTTP ${resp.statusCode}: ${resp.body}');
      return [];
    } catch (e, st) {
      debugPrint('[ListingService] getOffers hatası: $e');
      await Sentry.captureException(e, stackTrace: st);
      return [];
    }
  }

  /// [listingId] ilanı için beğeni toggle eder (beğen / beğeniyi kaldır).
  /// Güncel [likes_count] ve [is_liked] döner.
  static Future<Map<String, dynamic>> toggleLike(int listingId) async {
    try {
      final resp = await http.post(
        Uri.parse('$kBaseUrl/listings/$listingId/like'),
        headers: await _headers(auth: true),
      );
      if (resp.statusCode == 200) {
        final result = await compute(jsonDecode, resp.body) as Map<String, dynamic>;
        _likeCache[listingId] = result['is_liked'] as bool? ?? false;
        return result;
      }
      final body = await compute(jsonDecode, resp.body) as Map<String, dynamic>;
      final errMap = body['error'] as Map?;
      throw AppException(
        errMap?['message'] as String? ?? 'Beğeni gönderilemedi.',
        code: errMap?['code'] as String? ?? 'ERR_${resp.statusCode}',
        statusCode: resp.statusCode,
      );
    } catch (e, st) {
      debugPrint('[ListingService] toggleLike hatası: $e');
      await Sentry.captureException(e, stackTrace: st);
      rethrow;
    }
  }

  /// Verilen [listingId]'ye [amount] tutarında teklif verir.
  /// Başarısız olursa hata mesajını içeren [Exception] fırlatır.
  static Future<ListingOffer> placeOffer(int listingId, double amount) async {
    try {
      final resp = await http.post(
        Uri.parse('$kBaseUrl/listings/$listingId/offers'),
        headers: await _headers(auth: true),
        body: jsonEncode({'amount': amount}),
      );
      if (resp.statusCode == 200) {
        return ListingOffer.fromJson(
          await compute(jsonDecode, resp.body) as Map<String, dynamic>,
        );
      }
      final body = await compute(jsonDecode, resp.body) as Map<String, dynamic>;
      final errMap = body['error'] as Map?;
      throw AppException(
        errMap?['message'] as String? ?? 'Teklif gönderilemedi.',
        code: errMap?['code'] as String? ?? 'ERR_${resp.statusCode}',
        statusCode: resp.statusCode,
      );
    } catch (e, st) {
      debugPrint('[ListingService] placeOffer hatası: $e');
      await Sentry.captureException(e, stackTrace: st);
      rethrow;
    }
  }
}
