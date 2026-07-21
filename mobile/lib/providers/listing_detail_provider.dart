import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/enums.dart';
import '../services/listing_service.dart';

class ListingDetailState {
  final int id;
  final ListingStatus status;
  final bool isLoading;
  final String? error;
  final bool isInitialized;

  ListingDetailState({
    required this.id,
    this.status = ListingStatus.active,
    this.isLoading = false,
    this.error,
    this.isInitialized = false,
  });

  ListingDetailState copyWith({
    ListingStatus? status,
    bool? isLoading,
    String? error,
    bool? isInitialized,
  }) {
    return ListingDetailState(
      id: id,
      status: status ?? this.status,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      isInitialized: isInitialized ?? this.isInitialized,
    );
  }

  // İş Mantığı (Business Logic)
  // isInitialized guard: ilk frame'de default active state ile yanlış karar verilmesini önler
  bool get canReceiveOffers => isInitialized && status == ListingStatus.active;
  bool get isPassive => isInitialized && status == ListingStatus.passive;
}

class ListingDetailNotifier extends StateNotifier<ListingDetailState> {
  ListingDetailNotifier(int listingId) : super(ListingDetailState(id: listingId));

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

  // İlan aktiflik durumunu tetikleme 
  // (Not: Gerçek endpoint toggle çağrısı buraya eklenecek)
  void setStatus(ListingStatus newStatus) {
    state = state.copyWith(status: newStatus);
  }
}

final listingDetailProvider =
    StateNotifierProvider.family.autoDispose<ListingDetailNotifier, ListingDetailState, int>(
  (ref, id) => ListingDetailNotifier(id),
);
