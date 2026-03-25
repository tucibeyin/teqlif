import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sentry_flutter/sentry_flutter.dart';
import '../config/api.dart';
import '../models/listing_offer.dart';
import 'storage_service.dart';

class ListingService {
  static Future<Map<String, String>> _headers({bool auth = true}) async {
    final token = auth ? await StorageService.getToken() : null;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// İlana ait teklifleri miktara göre büyükten küçüğe döner.
  static Future<List<ListingOffer>> getOffers(int listingId) async {
    try {
      final resp = await http.get(
        Uri.parse('$kBaseUrl/listings/$listingId/offers'),
        headers: await _headers(auth: true),
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as List;
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
          jsonDecode(resp.body) as Map<String, dynamic>,
        );
      }
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final msg = (body['error'] as Map?)?['message'] as String? ??
          body['detail'] as String? ??
          'Teklif gönderilemedi.';
      throw Exception(msg);
    } catch (e, st) {
      debugPrint('[ListingService] placeOffer hatası: $e');
      await Sentry.captureException(e, stackTrace: st);
      rethrow;
    }
  }
}
