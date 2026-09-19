import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/api_client.dart';
import '../models/auction.dart';
import 'storage_service.dart';
import 'analytics_service.dart';

class AuctionService {
  final ApiClient _api;
  final AnalyticsService _analytics;
  AuctionService(this._api, this._analytics);

  Future<Map<String, String>> _headers() async {
    final token = await StorageService.getToken();
    return _api.buildApiHeaders(token, json: true);
  }

  Future<AuctionState> getState(int streamId) async {
    final body = await _api.call(
      () async => http.get(Uri.parse('${_api.config.baseUrl}/auction/$streamId'), headers: await _headers()),
    );
    return AuctionState.fromJson(body);
  }

  /// İlan seçilerek başlatmak için [listingId] gönderilir;
  /// manuel girildiğinde [itemName] ve [startPrice] gönderilir.
  /// [buyItNowPrice] opsiyonel; belirtilirse Hemen Al özelliği aktif olur.
  Future<AuctionState> startAuction(
    int streamId, {
    String? itemName,
    double? startPrice,
    int? listingId,
    double? buyItNowPrice,
  }) async {
    final Map<String, dynamic> payload = listingId != null
        ? {'listing_id': listingId, 'start_price': startPrice!}
        : {'item_name': itemName!, 'start_price': startPrice!};
    if (buyItNowPrice != null) payload['buy_it_now_price'] = buyItNowPrice;
    final body = await _api.call(
      () async => http.post(
        Uri.parse('${_api.config.baseUrl}/auction/$streamId/start'),
        headers: await _headers(),
        body: jsonEncode(payload),
      ),
    );
    return AuctionState.fromJson(body);
  }

  Future<void> buyItNow(int streamId) async {
    await _api.call(
      () async => http.post(
        Uri.parse('${_api.config.baseUrl}/auction/$streamId/buy-it-now'),
        headers: await _headers(),
      ),
    );
  }

  Future<void> acceptBuyItNow(int streamId, {String? proofImageUrl}) async {
    final bodyStr = proofImageUrl != null ? jsonEncode({'proof_image_url': proofImageUrl}) : null;
    await _api.call(
      () async => http.post(
        Uri.parse('${_api.config.baseUrl}/auction/$streamId/buy-it-now/accept'),
        headers: await _headers(),
        body: bodyStr,
      ),
    );
  }

  Future<void> rejectBuyItNow(int streamId) async {
    await _api.call(
      () async => http.post(
        Uri.parse('${_api.config.baseUrl}/auction/$streamId/buy-it-now/reject'),
        headers: await _headers(),
      ),
    );
  }

  Future<AuctionState> pauseAuction(int streamId) async {
    final body = await _api.call(
      () async => http.post(Uri.parse('${_api.config.baseUrl}/auction/$streamId/pause'), headers: await _headers()),
    );
    return AuctionState.fromJson(body);
  }

  Future<AuctionState> resumeAuction(int streamId) async {
    final body = await _api.call(
      () async => http.post(Uri.parse('${_api.config.baseUrl}/auction/$streamId/resume'), headers: await _headers()),
    );
    return AuctionState.fromJson(body);
  }

  Future<AuctionState> endAuction(int streamId, {String? proofImageUrl}) async {
    final bodyStr = proofImageUrl != null ? jsonEncode({'proof_image_url': proofImageUrl}) : null;
    final body = await _api.call(
      () async => http.post(
        Uri.parse('${_api.config.baseUrl}/auction/$streamId/end'),
        headers: await _headers(),
        body: bodyStr,
      ),
    );
    return AuctionState.fromJson(body);
  }

  Future<AuctionState> placeBid(int streamId, double amount) async {
    _analytics.trackEvent('bid_attempt', {'stream_id': streamId, 'amount': amount});
    final body = await _api.call(
      () async => http.post(
        Uri.parse('${_api.config.baseUrl}/auction/$streamId/bid'),
        headers: await _headers(),
        body: jsonEncode({'amount': amount}),
      ),
    );
    return AuctionState.fromJson(body);
  }

  Future<AuctionState> acceptBid(int streamId, {String? proofImageUrl}) async {
    final bodyStr = proofImageUrl != null ? jsonEncode({'proof_image_url': proofImageUrl}) : null;
    final body = await _api.call(
      () async => http.post(
        Uri.parse('${_api.config.baseUrl}/auction/$streamId/accept'),
        headers: await _headers(),
        body: bodyStr,
      ),
    );
    return AuctionState.fromJson(body);
  }

  /// Teklif geçmişini döner: [{bidder_username, amount, created_at}, ...]
  Future<List<Map<String, dynamic>>> fetchBids(int streamId) async {
    final body = await _api.call(
      () async => http.get(Uri.parse('${_api.config.baseUrl}/auction/$streamId/bids'), headers: await _headers()),
    );
    if (body is List) {
      return List<Map<String, dynamic>>.from(
        (body as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
    }
    return [];
  }
}

final auctionServiceProvider = Provider<AuctionService>((ref) =>
    AuctionService(ref.watch(apiClientProvider), ref.watch(analyticsServiceProvider)));
