import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/event_bus.dart';
import '../../services/wallet_service.dart';

class WalletConversionState {
  final int minutes;
  final bool isConverting;
  final String? errorCode;

  const WalletConversionState({
    this.minutes = 0,
    this.isConverting = false,
    this.errorCode,
  });

  WalletConversionState copyWith({
    int? minutes,
    bool? isConverting,
    String? errorCode,
    bool clearError = false,
  }) {
    return WalletConversionState(
      minutes: minutes ?? this.minutes,
      isConverting: isConverting ?? this.isConverting,
      errorCode: clearError ? null : (errorCode ?? this.errorCode),
    );
  }

  int costFor(int teqlikPerMinute) => minutes * teqlikPerMinute;
}

class WalletConversionNotifier extends AutoDisposeNotifier<WalletConversionState> {
  @override
  WalletConversionState build() => const WalletConversionState();

  void setMinutes(int value) {
    state = state.copyWith(minutes: value < 0 ? 0 : value, clearError: true);
  }

  /// Dönüşümü gerçekleştirir. Başarıda EventBus üzerinden tüm dinleyicileri uyarır.
  /// [currentBalance]: client-side ön kontrol için kullanılır (negatif UX önler).
  /// Gerçek kontrol backend'de yapılır.
  Future<bool> convert(int currentBalance) async {
    if (state.minutes <= 0) {
      state = state.copyWith(errorCode: 'INVALID_CONVERSION_AMOUNT');
      return false;
    }
    if (state.minutes > currentBalance) {
      state = state.copyWith(errorCode: 'INSUFFICIENT_TEQLIK');
      return false;
    }

    state = state.copyWith(isConverting: true, clearError: true);

    final result = await WalletService.convertToStreamMinutes(state.minutes);

    if (!result['ok']) {
      state = state.copyWith(
        isConverting: false,
        errorCode: result['error_code'] as String? ?? 'UNKNOWN_ERROR',
      );
      return false;
    }

    eventBus.fire(WalletConversionSuccessEvent(
      spentTeqlik: result['spent_teqlik'] as int? ?? state.minutes,
      addedMinutes: result['added_minutes'] as int? ?? state.minutes,
      newBalance: result['new_balance'] as int? ?? (currentBalance - state.minutes),
      newBonusMinutes: result['new_bonus_minutes'] as int? ?? state.minutes,
    ));
    // SubscriptionToolsScreen'in Yayın Süresi satırını anında güncelle
    eventBus.fire(const CreditsChangedEvent());

    await WalletService.invalidateBalance();

    state = state.copyWith(isConverting: false, minutes: 0, clearError: true);
    return true;
  }
}

final walletConversionProvider =
    AutoDisposeNotifierProvider<WalletConversionNotifier, WalletConversionState>(
  WalletConversionNotifier.new,
);
