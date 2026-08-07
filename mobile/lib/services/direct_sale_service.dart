import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import '../models/direct_sale.dart';
import 'storage_service.dart';

class DirectSaleService {
  static Future<Map<String, String>> _headers() async {
    final token = await StorageService.getToken();
    return buildApiHeaders(token, json: true);
  }

  static String _url(String path) => '$kBaseUrl/direct-sales/$path';

  // ── Host — satışı başlat ────────────────────────────────────────────────────

  /// [listingId] verilirse stok/başlık oradan alınır; verilmezse [title],
  /// [price], [stock] ve opsiyonel [proofImageUrl] gerekli.
  static Future<DirectSaleState> startSale(
    int streamId, {
    int? listingId,
    String? title,
    double? price,
    int? stock,
    String? proofImageUrl,
    String? productImageUrl,
  }) async {
    final Map<String, dynamic> payload = listingId != null
        ? {'listing_id': listingId}
        : {'title': title!, 'price': price!, 'stock_quantity': stock!};
    if (proofImageUrl != null) payload['proof_image_url'] = proofImageUrl;
    if (productImageUrl != null) payload['product_image_url'] = productImageUrl;
    final body = await apiCall(
      () async => http.post(
        Uri.parse(_url('$streamId/start')),
        headers: await _headers(),
        body: jsonEncode(payload),
      ),
    );
    return DirectSaleState.fromJson(body as Map<String, dynamic>);
  }

  static Future<DirectSaleState> pauseSale(int saleId) async {
    final body = await apiCall(
      () async => http.post(Uri.parse(_url('$saleId/pause')), headers: await _headers()),
    );
    return DirectSaleState.fromJson(body as Map<String, dynamic>);
  }

  static Future<DirectSaleState> resumeSale(int saleId) async {
    final body = await apiCall(
      () async => http.post(Uri.parse(_url('$saleId/resume')), headers: await _headers()),
    );
    return DirectSaleState.fromJson(body as Map<String, dynamic>);
  }

  static Future<DirectSaleState> endSale(int saleId) async {
    final body = await apiCall(
      () async => http.post(Uri.parse(_url('$saleId/end')), headers: await _headers()),
    );
    return DirectSaleState.fromJson(body as Map<String, dynamic>);
  }

  /// [ordersVoided] true → mevcut siparişler iptal edilir; false → geçerli kalır.
  static Future<void> cancelSale(int saleId, {required bool ordersVoided}) async {
    await apiCall(
      () async => http.post(
        Uri.parse(_url('$saleId/cancel')),
        headers: await _headers(),
        body: jsonEncode({'orders_voided': ordersVoided}),
      ),
    );
  }

  // ── Viewer — satın al ──────────────────────────────────────────────────────

  static Future<void> purchase(int saleId, {int quantity = 1}) async {
    await apiCall(
      () async => http.post(
        Uri.parse(_url('$saleId/purchase')),
        headers: await _headers(),
        body: jsonEncode({'quantity': quantity}),
      ),
    );
  }

  // ── Ortak sorgu ────────────────────────────────────────────────────────────

  /// Auth gerektirmez — hem host hem viewer hem de anonim izleyici çağırabilir.
  static Future<DirectSaleState> getState(int streamId) async {
    final token = await StorageService.getToken();
    final headers = await buildApiHeaders(token); // json:false — GET, body yok
    final body = await apiCall(
      () async => http.get(Uri.parse(_url('$streamId/state')), headers: headers),
    );
    return DirectSaleState.fromJson(body as Map<String, dynamic>);
  }

  /// Rol bazlı özet — seller veya buyer olarak döner.
  static Future<DirectSaleSummary> getSummary(int saleId) async {
    final body = await apiCall(
      () async => http.get(Uri.parse(_url('$saleId/summary')), headers: await _headers()),
    );
    return DirectSaleSummary.fromJson(body as Map<String, dynamic>);
  }

  /// Start dialog'da listing seçimi için kullanılır.
  /// Hata durumunda boş liste döner (dialog gracefully degrades).
  // apiCall() Map<String,dynamic> döndürdüğü için List endpoint'leri
  // doğrudan http.get + jsonDecode kullanmalı.

  static Future<List<Map<String, dynamic>>> fetchListingsForDialog({
    int? hostUserId,
    required int offset,
  }) async {
    final token = await StorageService.getToken();
    if (token == null) return [];
    final uri = hostUserId != null
        ? Uri.parse(
            '$kBaseUrl/listings?user_id=$hostUserId&active=true&limit=20&offset=$offset',
          )
        : Uri.parse(
            '$kBaseUrl/listings/my?active=true&limit=20&offset=$offset',
          );
    try {
      final response = await http.get(uri, headers: await buildApiHeaders(token));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is List) {
          return decoded
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }
      }
    } catch (_) {}
    return [];
  }

  /// Sadece host erişebilir.
  static Future<List<DirectSaleOrder>> getOrders(int saleId) async {
    final response = await http.get(
      Uri.parse(_url('$saleId/orders')),
      headers: await _headers(),
    );
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded is List) {
        return (decoded as List<dynamic>)
            .map((e) => DirectSaleOrder.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    }
    return [];
  }

  // ── Faz 6 — Fiyat önerisi + Talep tahmini ─────────────────────────────────

  static Future<DirectSaleSuggestion> getSuggestions({int? listingId}) async {
    final query = listingId != null ? '?listing_id=$listingId' : '';
    final body = await apiCall(
      () async => http.get(
        Uri.parse(_url('suggestions$query')),
        headers: await _headers(),
      ),
    );
    return DirectSaleSuggestion.fromJson(body as Map<String, dynamic>);
  }
}
