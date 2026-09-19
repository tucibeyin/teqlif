import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/api_client.dart';
import '../models/direct_sale.dart';
import 'storage_service.dart';

class DirectSaleService {
  final ApiClient _api;
  DirectSaleService(this._api);

  Future<Map<String, String>> _headers() async {
    final token = await StorageService.getToken();
    return _api.buildApiHeaders(token, json: true);
  }

  String _url(String path) => '${_api.config.baseUrl}/direct-sales/$path';

  // ── Host — satışı başlat ────────────────────────────────────────────────────

  /// [listingId] verilirse stok/başlık oradan alınır; verilmezse [title],
  /// [price], [stock] ve opsiyonel [proofImageUrl] gerekli.
  Future<DirectSaleState> startSale(
    int streamId, {
    int? listingId,
    String? title,
    double? price,
    int? stock,
    String? proofImageUrl,
    String? productImageUrl,
  }) async {
    final Map<String, dynamic> payload = {
      'listing_id': ?listingId,
      'title': ?title,
      'price': price!,
      'stock_quantity': stock!,
      'proof_image_url': ?proofImageUrl,
      'product_image_url': ?productImageUrl,
    };
    final body = await _api.call(
      () async => http.post(
        Uri.parse(_url('$streamId/start')),
        headers: await _headers(),
        body: jsonEncode(payload),
      ),
    );
    return DirectSaleState.fromJson(body);
  }

  Future<void> pauseSale(int saleId) async {
    await _api.call(
      () async => http.post(Uri.parse(_url('$saleId/pause')), headers: await _headers()),
    );
  }

  Future<void> resumeSale(int saleId) async {
    await _api.call(
      () async => http.post(Uri.parse(_url('$saleId/resume')), headers: await _headers()),
    );
  }

  Future<void> endSale(int saleId) async {
    await _api.call(
      () async => http.post(Uri.parse(_url('$saleId/end')), headers: await _headers()),
    );
  }

  /// [ordersVoided] true → mevcut siparişler iptal edilir; false → geçerli kalır.
  Future<void> cancelSale(int saleId, {required bool ordersVoided}) async {
    await _api.call(
      () async => http.post(
        Uri.parse(_url('$saleId/cancel')),
        headers: await _headers(),
        body: jsonEncode({'orders_voided': ordersVoided}),
      ),
    );
  }

  // ── Viewer — satın al ──────────────────────────────────────────────────────

  Future<void> purchase(int saleId, {int quantity = 1}) async {
    await _api.call(
      () async => http.post(
        Uri.parse(_url('$saleId/purchase')),
        headers: await _headers(),
        body: jsonEncode({'quantity': quantity}),
      ),
    );
  }

  // ── Ortak sorgu ────────────────────────────────────────────────────────────

  /// Auth gerektirmez — hem host hem viewer hem de anonim izleyici çağırabilir.
  Future<DirectSaleState> getState(int streamId) async {
    final token = await StorageService.getToken();
    final headers = await _api.buildApiHeaders(token); // json:false — GET, body yok
    final body = await _api.call(
      () async => http.get(Uri.parse(_url('$streamId/state')), headers: headers),
    );
    return DirectSaleState.fromJson(body);
  }

  /// Rol bazlı özet — seller veya buyer olarak döner.
  Future<DirectSaleSummary> getSummary(int saleId) async {
    final body = await _api.call(
      () async => http.get(Uri.parse(_url('$saleId/summary')), headers: await _headers()),
    );
    return DirectSaleSummary.fromJson(body);
  }

  /// Start dialog'da listing seçimi için kullanılır.
  /// Hata durumunda boş liste döner (dialog gracefully degrades).
  // _api.call() Map<String,dynamic> döndürdüğü için List endpoint'leri
  // doğrudan http.get + jsonDecode kullanmalı.

  Future<List<Map<String, dynamic>>> fetchListingsForDialog({
    int? hostUserId,
    required int offset,
  }) async {
    final token = await StorageService.getToken();
    if (token == null) return [];
    final uri = hostUserId != null
        ? Uri.parse(
            '${_api.config.baseUrl}/listings?user_id=$hostUserId&active=true&limit=20&offset=$offset',
          )
        : Uri.parse(
            '${_api.config.baseUrl}/listings/my?active=true&limit=20&offset=$offset',
          );
    try {
      final response = await http.get(uri, headers: await _api.buildApiHeaders(token));
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
  Future<List<DirectSaleOrder>> getOrders(int saleId) async {
    final response = await http.get(
      Uri.parse(_url('$saleId/orders')),
      headers: await _headers(),
    );
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded is List) {
        return decoded
            .map((e) => DirectSaleOrder.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    }
    return [];
  }
}

final directSaleServiceProvider = Provider<DirectSaleService>((ref) =>
    DirectSaleService(ref.watch(apiClientProvider)));
