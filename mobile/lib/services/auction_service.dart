import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import '../models/auction.dart';
import 'storage_service.dart';
import 'analytics_service.dart';

class AuctionService {
  static Future<Map<String, String>> _headers() async {
    final token = await StorageService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<AuctionState> getState(int streamId) async {
    final body = await apiCall(
      () async => http.get(Uri.parse('$kBaseUrl/auction/$streamId'), headers: await _headers()),
    );
    return AuctionState.fromJson(body);
  }

  /// İlan seçilerek başlatmak için [listingId] gönderilir;
  /// manuel girildiğinde [itemName] ve [startPrice] gönderilir.
  /// [buyItNowPrice] opsiyonel; belirtilirse Hemen Al özelliği aktif olur.
  static Future<AuctionState> startAuction(
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
    final body = await apiCall(
      () async => http.post(
        Uri.parse('$kBaseUrl/auction/$streamId/start'),
        headers: await _headers(),
        body: jsonEncode(payload),
      ),
    );
    return AuctionState.fromJson(body);
  }

  static Future<void> buyItNow(int streamId) async {
    await apiCall(
      () async => http.post(
        Uri.parse('$kBaseUrl/auction/$streamId/buy-it-now'),
        headers: await _headers(),
      ),
    );
  }

  static Future<AuctionState> pauseAuction(int streamId) async {
    final body = await apiCall(
      () async => http.post(Uri.parse('$kBaseUrl/auction/$streamId/pause'), headers: await _headers()),
    );
    return AuctionState.fromJson(body);
  }

  static Future<AuctionState> resumeAuction(int streamId) async {
    final body = await apiCall(
      () async => http.post(Uri.parse('$kBaseUrl/auction/$streamId/resume'), headers: await _headers()),
    );
    return AuctionState.fromJson(body);
  }

  static Future<AuctionState> endAuction(int streamId) async {
    final body = await apiCall(
      () async => http.post(Uri.parse('$kBaseUrl/auction/$streamId/end'), headers: await _headers()),
    );
    return AuctionState.fromJson(body);
  }

  static Future<AuctionState> placeBid(int streamId, double amount) async {
    AnalyticsService.trackEvent('bid_attempt', {'stream_id': streamId, 'amount': amount});
    final body = await apiCall(
      () async => http.post(
        Uri.parse('$kBaseUrl/auction/$streamId/bid'),
        headers: await _headers(),
        body: jsonEncode({'amount': amount}),
      ),
    );
    return AuctionState.fromJson(body);
  }

  static Future<AuctionState> acceptBid(int streamId) async {
    final body = await apiCall(
      () async => http.post(Uri.parse('$kBaseUrl/auction/$streamId/accept'), headers: await _headers()),
    );
    return AuctionState.fromJson(body);
  }
}
