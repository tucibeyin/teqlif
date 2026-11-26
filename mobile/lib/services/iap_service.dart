import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' show providerContainer;
import '../core/network/api_client.dart';
import 'storage_service.dart';
import 'wallet_service.dart';
import 'package:http/http.dart' as http;
import '../core/user_tier.dart';

const _kDeviceIdKey = 'teqlif_iap_device_id';

Future<String> _getOrCreateDeviceId() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_kDeviceIdKey);
    if (id == null) {
      final rng = Random.secure();
      id = List.generate(32, (_) => rng.nextInt(16).toRadixString(16)).join();
      await prefs.setString(_kDeviceIdKey, id);
    }
    return id;
  } catch (_) {
    return 'unknown';
  }
}

/// Consumable teqlik paketi ID'leri
const kConsumableIds = {
  'teqlik_pack_100',
  'teqlik_pack_250',
  'teqlik_pack_500',
  'teqlik_pack_1000',
};

/// Tüm abonelik ID'leri — PRO / PRO+ / PREMIUM / PREMIUM+ × 1m/12m
const kSubscriptionIds = {
  'teqlif_pro_1m',          'teqlif_pro_12m',
  'teqlif_pro_plus_1m',     'teqlif_pro_plus_12m',
  'teqlif_premium_1m',      'teqlif_premium_12m',
  'teqlif_premium_plus_1m', 'teqlif_premium_plus_12m',
};

/// IAP ürün ID → abonelik tier eşlemesi
const kProductTierMap = <String, String>{
  'teqlif_pro_1m':          UserTier.tier1,
  'teqlif_pro_12m':         UserTier.tier1,
  'teqlif_pro_plus_1m':     UserTier.tier2,
  'teqlif_pro_plus_12m':    UserTier.tier2,
  'teqlif_premium_1m':      UserTier.tier3,
  'teqlif_premium_12m':     UserTier.tier3,
  'teqlif_premium_plus_1m': UserTier.tier4,
  'teqlif_premium_plus_12m':UserTier.tier4,
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

  // Startup'ta iOS birden fazla pending purchase basabilir.
  // Hepsini 1,5 sn debounce ile birleştirip sırayla işliyoruz — burst engellemek için.
  Timer? _startupDebounce;
  final List<PurchaseDetails> _pendingQueue = [];
  bool _processingQueue = false;

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

  Future<void> _onPurchaseUpdates(List<PurchaseDetails> purchases) async {
    // Startup'ta iOS tüm pending satın alımları aynı anda basabilir.
    // 1,5 sn debounce ile toplayıp tek bir sıralı kuyrukta işliyoruz.
    _pendingQueue.addAll(purchases);
    _startupDebounce?.cancel();
    _startupDebounce = Timer(const Duration(milliseconds: 1500), _drainQueue);
  }

  Future<void> _drainQueue() async {
    if (_processingQueue || _pendingQueue.isEmpty) return;
    _processingQueue = true;
    final toProcess = List<PurchaseDetails>.from(_pendingQueue);
    _pendingQueue.clear();

    for (final purchase in toProcess) {
      await _processSinglePurchase(purchase);
    }
    _processingQueue = false;
  }

  Future<void> _processSinglePurchase(PurchaseDetails purchase) async {
    if (purchase.status == PurchaseStatus.purchased ||
        purchase.status == PurchaseStatus.restored) {
      final ok = await _verifyWithBackend(purchase);
      if (ok) {
        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }
        WalletService.invalidateBalance();
        _purchaseController.add(purchase);
      } else {
        _purchaseController.addError(Exception('IAP_BACKEND_FAILED'));
      }
    } else {
      if (purchase.pendingCompletePurchase &&
          purchase.status != PurchaseStatus.pending) {
        await _iap.completePurchase(purchase);
      }
      if (purchase.status == PurchaseStatus.error) {
        debugPrint('[IAP] purchase error: ${purchase.error}');
      }
      _purchaseController.add(purchase);
    }
  }

  Future<bool> _verifyWithBackend(PurchaseDetails purchase, {int attempt = 1}) async {
    try {
      final token = await StorageService.getToken();
      // Null veya expired (JWT süresi dolmuş) token ile istek atmıyoruz.
      // Backend 401 döndürmesi CrowdSec'in http-generic-401-bf senaryosunu tetikler.
      if (token == null || StorageService.isTokenExpired(token)) return false;

      final payload = purchase.verificationData.serverVerificationData;
      final productId = purchase.productID;
      final platform = defaultTargetPlatform == TargetPlatform.iOS ? 'apple' : 'google';

      final deviceId = await _getOrCreateDeviceId();
      final matchedProduct = products.where((p) => p.id == productId).firstOrNull;
      final tryAmount = matchedProduct?.rawPrice ?? 0.0;

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
          'device_id': deviceId,
          'try_amount': tryAmount,
        }),
      );

      if (resp.statusCode == 200) return true;
      // 409 = replay (zaten işlendi) — başarılı say
      if (resp.statusCode == 409) return true;
      // 429 = velocity limit — backend artık 429 döndürüyor (eski 400 → CrowdSec tetiklerdi)
      // İlk denemede 30 sn bekleyip tekrar dene; ikinci denemede bırak.
      if (resp.statusCode == 429 && attempt == 1) {
        await Future.delayed(const Duration(seconds: 30));
        return _verifyWithBackend(purchase, attempt: 2);
      }
      // 5xx hatası ve ilk deneme — 2 saniye bekle, bir kez daha dene
      if (resp.statusCode >= 500 && attempt == 1) {
        await Future.delayed(const Duration(seconds: 2));
        return _verifyWithBackend(purchase, attempt: 2);
      }
      debugPrint('[IAP] backend verify failed: ${resp.statusCode} ${resp.body}');
      return false;
    } catch (e) {
      // Ağ hatası ve ilk deneme — 2 saniye bekle, bir kez daha dene
      if (attempt == 1) {
        await Future.delayed(const Duration(seconds: 2));
        return _verifyWithBackend(purchase, attempt: 2);
      }
      debugPrint('[IAP] verify error: $e');
      return false;
    }
  }

  void dispose() {
    _startupDebounce?.cancel();
    _pendingQueue.clear();
    _subscription?.cancel();
    _purchaseController.close();
  }
}
