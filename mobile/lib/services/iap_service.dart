import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../main.dart' show providerContainer;
import '../core/network/api_client.dart';
import 'storage_service.dart';
import 'package:http/http.dart' as http;

/// Consumable teqlik paketi ID'leri
const kConsumableIds = {
  'teqlik_pack_100',
  'teqlik_pack_250',
  'teqlik_pack_500',
  'teqlik_pack_1000',
};

/// PRO abonelik ID'leri
const kSubscriptionIds = {
  'teqlif_pro_1m',
  'teqlif_pro_3m',
  'teqlif_pro_6m',
  'teqlif_pro_12m',
};

final _allIds = {...kConsumableIds, ...kSubscriptionIds};

class IAPService {
  static final IAPService _instance = IAPService._();
  factory IAPService() => _instance;
  IAPService._();

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  final _purchaseController = StreamController<PurchaseDetails>.broadcast();

  /// Broadcast stream — widget'lar dinleyebilir
  Stream<PurchaseDetails> get purchaseStream => _purchaseController.stream;

  /// Store ürünleri — loadProducts() sonrası dolu
  List<ProductDetails> products = [];

  Future<void> init() async {
    final available = await _iap.isAvailable();
    if (!available) return;

    _subscription = _iap.purchaseStream.listen(
      _onPurchaseUpdates,
      onError: (e) => debugPrint('[IAP] stream error: $e'),
    );

    await loadProducts();
  }

  Future<void> loadProducts() async {
    final response = await _iap.queryProductDetails(_allIds);
    if (response.error != null) {
      debugPrint('[IAP] queryProductDetails error: ${response.error}');
      return;
    }
    products = response.productDetails;
  }

  Future<void> buy(ProductDetails product) async {
    final isConsumable = kConsumableIds.contains(product.id);
    final params = PurchaseParam(productDetails: product);
    if (isConsumable) {
      await _iap.buyConsumable(purchaseParam: params);
    } else {
      await _iap.buyNonConsumable(purchaseParam: params);
    }
  }

  Future<void> restorePurchases() async {
    await _iap.restorePurchases();
  }

  void _onPurchaseUpdates(List<PurchaseDetails> purchases) {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        _verifyWithBackend(purchase);
      } else if (purchase.status == PurchaseStatus.error) {
        debugPrint('[IAP] purchase error: ${purchase.error}');
        _purchaseController.add(purchase);
      }
      if (purchase.pendingCompletePurchase) {
        _iap.completePurchase(purchase);
      }
    }
  }

  Future<void> _verifyWithBackend(PurchaseDetails purchase) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return;

      final payload = purchase.verificationData.serverVerificationData;
      final productId = purchase.productID;
      final platform = defaultTargetPlatform == TargetPlatform.iOS ? 'apple' : 'google';

      final resp = await http.post(
        Uri.parse('${providerContainer.read(apiClientProvider).config.baseUrl}/wallet/purchase/verify'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'platform': platform,
          'payload': payload,
          'product_id': productId,
          'device_id': null,
          'try_amount': 0.0,
        }),
      );

      if (resp.statusCode == 200) {
        _purchaseController.add(purchase);
      } else {
        debugPrint('[IAP] backend verify failed: ${resp.statusCode} ${resp.body}');
        // Yine de tamamla — Apple pending purchase cezası uygular
        _purchaseController.add(purchase);
      }
    } catch (e) {
      debugPrint('[IAP] verify error: $e');
      _purchaseController.add(purchase);
    }
  }

  void dispose() {
    _subscription?.cancel();
    _purchaseController.close();
  }
}
