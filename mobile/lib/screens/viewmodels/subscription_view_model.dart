import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../../services/iap_service.dart';

class SubscriptionState {
  final List<ProductDetails> products;
  final bool isPurchasing;
  final PurchaseDetails? lastPurchase;
  final String? error;

  const SubscriptionState({
    this.products = const [],
    this.isPurchasing = false,
    this.lastPurchase,
    this.error,
  });

  SubscriptionState copyWith({
    List<ProductDetails>? products,
    bool? isPurchasing,
    PurchaseDetails? lastPurchase,
    String? error,
    bool clearLastPurchase = false,
  }) {
    return SubscriptionState(
      products: products ?? this.products,
      isPurchasing: isPurchasing ?? this.isPurchasing,
      lastPurchase: clearLastPurchase ? null : (lastPurchase ?? this.lastPurchase),
      error: error ?? this.error,
    );
  }
}

class SubscriptionViewModel extends AutoDisposeNotifier<SubscriptionState> {
  StreamSubscription<PurchaseDetails>? _purchaseSub;

  @override
  SubscriptionState build() {
    final iap = IAPService();
    _purchaseSub = iap.purchaseStream.listen(
      _onPurchase,
      onError: (_) {
        state = state.copyWith(isPurchasing: false, error: 'IAP_BACKEND_FAILED');
      },
    );
    ref.onDispose(() => _purchaseSub?.cancel());
    final initial = SubscriptionState(products: iap.products);
    if (iap.products.isEmpty) {
      Future.microtask(loadProducts);
    }
    return initial;
  }

  void _onPurchase(PurchaseDetails purchase) {
    if (purchase.status == PurchaseStatus.pending) {
      state = state.copyWith(lastPurchase: purchase);
      return;
    }
    state = state.copyWith(
      isPurchasing: false,
      lastPurchase: purchase,
      error: null,
    );
  }

  Future<void> loadProducts() async {
    await IAPService().loadProducts();
    state = state.copyWith(products: IAPService().products);
  }

  Future<void> buy(ProductDetails product) async {
    state = state.copyWith(isPurchasing: true, error: null);
    try {
      await IAPService().buy(product);
    } catch (e) {
      state = state.copyWith(isPurchasing: false, error: e.toString());
    }
  }

  Future<void> restorePurchases() async {
    state = state.copyWith(isPurchasing: true, error: null);
    try {
      await IAPService().restorePurchases();
    } catch (e) {
      state = state.copyWith(isPurchasing: false, error: e.toString());
    }
  }
}

final subscriptionViewModelProvider =
    NotifierProvider.autoDispose<SubscriptionViewModel, SubscriptionState>(
  SubscriptionViewModel.new,
);
