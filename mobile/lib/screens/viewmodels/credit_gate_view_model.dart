import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/credit_gate_data.dart';
import '../../services/credit_gate_service.dart';

/// Kredi kapısı UI + iş durumu.
class CreditGateState {
  /// İlk veri yükleme (fetchData) devam ediyor mu.
  final bool isLoadingData;

  /// Yükleme hatası — null ise hata yok.
  final String? loadError;

  /// Yüklenen gate verisi.
  final CreditGateData? data;

  /// Onay aksiyonu (execute) devam ediyor mu.
  final bool isConfirming;

  /// Blast için seçilen kişi sayısı; diğer feature'larda 1.
  final int selectedCount;

  const CreditGateState({
    this.isLoadingData = true,
    this.loadError,
    this.data,
    this.isConfirming = false,
    this.selectedCount = 1,
  });

  CreditGateState copyWith({
    bool? isLoadingData,
    String? loadError,
    CreditGateData? data,
    bool? isConfirming,
    int? selectedCount,
    bool clearError = false,
  }) =>
      CreditGateState(
        isLoadingData: isLoadingData ?? this.isLoadingData,
        loadError: clearError ? null : (loadError ?? this.loadError),
        data: data ?? this.data,
        isConfirming: isConfirming ?? this.isConfirming,
        selectedCount: selectedCount ?? this.selectedCount,
      );

  // ── Blast maliyet hesabı ─────────────────────────────────────────────────────

  int freeUsed(int freeRemaining) =>
      selectedCount < freeRemaining ? selectedCount : freeRemaining;

  int paidCount(int freeRemaining) => selectedCount - freeUsed(freeRemaining);

  int teqlikCost(int freeRemaining, int costPerUnit) =>
      paidCount(freeRemaining) * costPerUnit;
}

/// Kredi kapısı ViewModel.
///
/// Sheet bu notifier'ı kullanır; ekranlar sadece [creditGateProvider]'ı okur.
class CreditGateNotifier extends AutoDisposeNotifier<CreditGateState> {
  @override
  CreditGateState build() => const CreditGateState();

  /// Feature verilerini çek; tamamlanınca state'e yaz.
  Future<void> loadData(
    CreditFeature feature,
    int? listingId,
    CreditGateService service,
  ) async {
    state = const CreditGateState(isLoadingData: true);
    final loaded = await service.fetchData(feature, listingId: listingId);
    if (loaded == null) {
      state = state.copyWith(isLoadingData: false, loadError: 'errorGeneric');
      return;
    }
    // Blast'ta kitle sıfırsa devam etmenin anlamı yok.
    if (feature == CreditFeature.blast && loaded.audienceSize == 0) {
      state = state.copyWith(isLoadingData: false, loadError: 'blastNoAudience');
      return;
    }
    final defaultCount = feature == CreditFeature.blast
        ? (loaded.audienceSize < loaded.perOpCap
            ? loaded.audienceSize
            : loaded.perOpCap)
        : 1;
    state = state.copyWith(
      isLoadingData: false,
      data: loaded,
      selectedCount: defaultCount,
      clearError: true,
    );
  }

  void setCount(int count) {
    if (count < 1) return;
    state = state.copyWith(selectedCount: count);
  }

  /// Aksiyonu sarar; loading ve hata durumlarını yönetir.
  Future<CreditGateResult> confirm(
    Future<CreditGateResult> Function(CreditGateState s) action,
  ) async {
    if (state.isConfirming) return CreditGateResult.cancelled();
    state = state.copyWith(isConfirming: true);
    try {
      final result = await action(state);
      state = state.copyWith(isConfirming: false);
      return result;
    } catch (_) {
      state = state.copyWith(isConfirming: false);
      return CreditGateResult.failure('errorGeneric');
    }
  }
}

final creditGateProvider =
    NotifierProvider.autoDispose<CreditGateNotifier, CreditGateState>(
  CreditGateNotifier.new,
);
