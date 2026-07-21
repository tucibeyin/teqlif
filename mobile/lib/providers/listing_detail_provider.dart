import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/enums.dart';
import '../models/mass_notif_eligibility.dart';
import '../services/listing_service.dart';

class ListingDetailState {
  final int id;
  final ListingStatus status;
  final bool isLoading;
  final String? error;
  final bool isInitialized;
  final int cooldownSeconds;
  final bool isMassNotifSending;

  ListingDetailState({
    required this.id,
    this.status = ListingStatus.active,
    this.isLoading = false,
    this.error,
    this.isInitialized = false,
    this.cooldownSeconds = 0,
    this.isMassNotifSending = false,
  });

  ListingDetailState copyWith({
    ListingStatus? status,
    bool? isLoading,
    String? error,
    bool? isInitialized,
    int? cooldownSeconds,
    bool? isMassNotifSending,
  }) {
    return ListingDetailState(
      id: id,
      status: status ?? this.status,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      isInitialized: isInitialized ?? this.isInitialized,
      cooldownSeconds: cooldownSeconds ?? this.cooldownSeconds,
      isMassNotifSending: isMassNotifSending ?? this.isMassNotifSending,
    );
  }

  // isInitialized guard: ilk frame'de default active state ile yanlış karar verilmesini önler
  bool get canReceiveOffers => isInitialized && status == ListingStatus.active;
  bool get isPassive => isInitialized && status == ListingStatus.passive;

  MassNotifEligibility get massNotifEligibility {
    if (!isInitialized || status != ListingStatus.active) {
      return const MassNotifUnavailable(MassNotifUnavailableReason.listingNotActive);
    }
    if (cooldownSeconds > 0) {
      return MassNotifCooldownActive(cooldownSeconds);
    }
    return const MassNotifAvailable();
  }
}

class ListingDetailNotifier extends StateNotifier<ListingDetailState> {
  ListingDetailNotifier(int listingId) : super(ListingDetailState(id: listingId));

  Timer? _cooldownTimer;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void initFromData(Map<String, dynamic> data) {
    state = state.copyWith(
      status: ListingStatusExtension.fromJson(data),
      isInitialized: true,
    );
  }

  Future<void> refreshStatus() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final data = await ListingService.getListingById(state.id);
      if (data != null) {
        state = state.copyWith(
          status: ListingStatusExtension.fromJson(data),
          isLoading: false,
          isInitialized: true,
        );
      } else {
        state = state.copyWith(isLoading: false, error: "Listing not found");
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void setStatus(ListingStatus newStatus) {
    state = state.copyWith(status: newStatus);
  }

  void setSending(bool sending) {
    state = state.copyWith(isMassNotifSending: sending);
  }

  /// Cooldown'u başlatır ve her saniye state'i günceller.
  void startCooldown(int seconds) {
    _cooldownTimer?.cancel();
    state = state.copyWith(cooldownSeconds: seconds, isMassNotifSending: false);
    if (seconds <= 0) return;
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final remaining = state.cooldownSeconds - 1;
      if (remaining <= 0) {
        _cooldownTimer?.cancel();
        state = state.copyWith(cooldownSeconds: 0);
      } else {
        state = state.copyWith(cooldownSeconds: remaining);
      }
    });
  }

  void clearCooldown() {
    _cooldownTimer?.cancel();
    state = state.copyWith(cooldownSeconds: 0);
  }
}

final listingDetailProvider =
    StateNotifierProvider.family.autoDispose<ListingDetailNotifier, ListingDetailState, int>(
  (ref, id) => ListingDetailNotifier(id),
);
