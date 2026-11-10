import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../core/app_exception.dart';
import '../core/event_bus.dart';
import '../core/network/api_client.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../services/storage_service.dart';

class WalletRepository {
  final ApiClient _client;
  final ApiService _api;
  final CacheService _cache;

  WalletRepository(this._client, this._api, this._cache);

  Future<Map<String, dynamic>?> getSummary() async {
    try {
      final token = await StorageService.getToken();
      final headers = await _client.buildApiHeaders(token);
      return await _client.call(
        () => http.get(
          Uri.parse('${_client.config.baseUrl}/wallet/summary'),
          headers: headers,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> convertToTeqlik(int teqlikAmount) async {
    final token = await StorageService.getToken();
    if (token == null) return {'ok': false, 'error': 'Oturum bulunamadı.'};
    final headers = await _client.buildApiHeaders(token, json: true);
    try {
      final result = await _client.call(
        () => http.post(
          Uri.parse('${_client.config.baseUrl}/wallet/convert-to-teqlik'),
          headers: headers,
          body: jsonEncode({'teqlik_amount': teqlikAmount}),
        ),
      );
      return {'ok': true, ...result};
    } on AppException catch (e) {
      return {'ok': false, 'error': e.message, 'status_code': e.statusCode};
    } catch (_) {
      return {'ok': false, 'error': 'Bağlantı hatası.'};
    }
  }

  Future<Map<String, dynamic>> requestWithdrawal({
    required int teqlikAmount,
    required String iban,
    required String accountHolderName,
    String currency = 'TRY',
  }) async {
    final token = await StorageService.getToken();
    if (token == null) return {'ok': false, 'error': 'Oturum bulunamadı.'};
    final headers = await _client.buildApiHeaders(token, json: true);
    try {
      final result = await _client.call(
        () => http.post(
          Uri.parse('${_client.config.baseUrl}/wallet/withdraw'),
          headers: headers,
          body: jsonEncode({
            'teqlik_amount': teqlikAmount,
            'currency': currency,
            'iban': iban,
            'account_holder_name': accountHolderName,
          }),
        ),
      );
      return {'ok': true, ...result};
    } on AppException catch (e) {
      return {'ok': false, 'error': e.message, 'status_code': e.statusCode};
    } catch (_) {
      return {'ok': false, 'error': 'Bağlantı hatası.'};
    }
  }

  Future<bool> cancelWithdrawal(int requestId) async {
    try {
      final token = await StorageService.getToken();
      final headers = await _client.buildApiHeaders(token);
      await _client.call(
        () => http.delete(
          Uri.parse('${_client.config.baseUrl}/wallet/withdraw/$requestId'),
          headers: headers,
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> sendGift({
    required int streamId,
    required String receiverUsername,
    required String giftName,
    required int cost,
  }) async {
    final token = await StorageService.getToken();
    if (token == null) return {'ok': false, 'error': 'Oturum bulunamadı.'};
    final headers = await _client.buildApiHeaders(token, json: true);
    try {
      final result = await _client.call(
        () => http.post(
          Uri.parse('${_client.config.baseUrl}/wallet/send-gift'),
          headers: headers,
          body: jsonEncode({
            'stream_id': streamId,
            'receiver_username': receiverUsername,
            'gift_name': giftName,
            'cost': cost,
          }),
        ),
      );
      return {'ok': true, ...result};
    } on AppException catch (e) {
      return {'ok': false, 'error': e.message, 'status_code': e.statusCode};
    } catch (_) {
      return {'ok': false, 'error': 'Bağlantı hatası.'};
    }
  }

  Future<Map<String, dynamic>?> syncSubscription() async {
    try {
      final token = await StorageService.getToken();
      final headers = await _client.buildApiHeaders(token);
      return await _client.call(
        () => http.post(
          Uri.parse('${_client.config.baseUrl}/wallet/subscription/sync'),
          headers: headers,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> getBalance({int limit = 5}) async {
    try {
      final token = await StorageService.getToken();
      final headers = await _client.buildApiHeaders(token);
      return await _client.call(
        () => http.get(
          Uri.parse('${_client.config.baseUrl}/wallet/balance?limit=$limit'),
          headers: headers,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> getTransactionDetail(int txnId) async {
    try {
      final token = await StorageService.getToken();
      final headers = await _client.buildApiHeaders(token);
      return await _client.call(
        () => http.get(
          Uri.parse('${_client.config.baseUrl}/wallet/transaction/$txnId'),
          headers: headers,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Stream<Map<String, dynamic>> getBalanceStream({
    int limit = 5,
    bool bypassCache = false,
  }) =>
      _api.get<Map<String, dynamic>>(
        url: '${_client.config.baseUrl}/wallet/balance?limit=$limit',
        cacheKey: StorageService.cacheWalletData,
        cacheTtl: const Duration(minutes: 2),
        bypassCache: bypassCache,
        fromJson: (raw) => raw as Map<String, dynamic>,
      );

  Future<void> invalidateBalance({bool fireEvent = true}) async {
    await _cache.clearData(StorageService.cacheWalletData);
    if (fireEvent) eventBus.fire(const CreditsChangedEvent());
  }
}

final walletRepositoryProvider = Provider<WalletRepository>((ref) => WalletRepository(
      ref.watch(apiClientProvider),
      ref.watch(apiServiceProvider),
      ref.watch(cacheServiceProvider),
    ));
