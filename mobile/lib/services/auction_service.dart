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

  static void _checkError(http.Response res) {
    if (res.statusCode >= 400) {
      final body = jsonDecode(res.body);
      throw Exception(body['detail'] ?? 'Bir hata oluştu');
    }
  }

  static Future<AuctionState> getState(int streamId) async {
    final res = await http.get(
      Uri.parse('$kBaseUrl/auction/$streamId'),
      headers: await _headers(),
    );
    _checkError(res);
    return AuctionState.fromJson(jsonDecode(res.body));
  }

  /// İlan seçilerek başlatmak için [listingId] gönderilir;
  /// manuel girildiğinde [itemName] ve [startPrice] gönderilir.
  static Future<AuctionState> startAuction(
    int streamId, {
    String? itemName,
    double? startPrice,
    int? listingId,
  }) async {
    final Map<String, dynamic> body = listingId != null
        ? {'listing_id': listingId, 'start_price': startPrice!}
        : {'item_name': itemName!, 'start_price': startPrice!};
    final res = await http.post(
      Uri.parse('$kBaseUrl/auction/$streamId/start'),
      headers: await _headers(),
      body: jsonEncode(body),
    );
    _checkError(res);
    return AuctionState.fromJson(jsonDecode(res.body));
  }

  static Future<AuctionState> pauseAuction(int streamId) async {
    final res = await http.post(
      Uri.parse('$kBaseUrl/auction/$streamId/pause'),
      headers: await _headers(),
    );
    _checkError(res);
    return AuctionState.fromJson(jsonDecode(res.body));
  }

  static Future<AuctionState> resumeAuction(int streamId) async {
    final res = await http.post(
      Uri.parse('$kBaseUrl/auction/$streamId/resume'),
      headers: await _headers(),
    );
    _checkError(res);
    return AuctionState.fromJson(jsonDecode(res.body));
  }

  static Future<AuctionState> endAuction(int streamId) async {
    final res = await http.post(
      Uri.parse('$kBaseUrl/auction/$streamId/end'),
      headers: await _headers(),
    );
    _checkError(res);
    return AuctionState.fromJson(jsonDecode(res.body));
  }

  static Future<AuctionState> placeBid(int streamId, double amount) async {
    AnalyticsService.trackEvent('bid_attempt', {'stream_id': streamId, 'amount': amount});
    
    final res = await http.post(
      Uri.parse('$kBaseUrl/auction/$streamId/bid'),
      headers: await _headers(),
      body: jsonEncode({'amount': amount}),
    );
    _checkError(res);
    return AuctionState.fromJson(jsonDecode(res.body));
  }

  static Future<AuctionState> acceptBid(int streamId) async {
    final res = await http.post(
      Uri.parse('$kBaseUrl/auction/$streamId/accept'),
      headers: await _headers(),
    );
    _checkError(res);
    return AuctionState.fromJson(jsonDecode(res.body));
  }
}
