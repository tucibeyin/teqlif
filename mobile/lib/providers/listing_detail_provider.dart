import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/enums.dart';
import '../services/listing_service.dart';

class ListingDetailState {
  final int id;
  final ListingStatus status;
  final bool isLoading;
  final String? error;

  ListingDetailState({
    required this.id,
    this.status = ListingStatus.active,
    this.isLoading = false,
    this.error,
  });

  ListingDetailState copyWith({
    ListingStatus? status,
    bool? isLoading,
    String? error,
  }) {
    return ListingDetailState(
      id: id,
      status: status ?? this.status,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }

  // İş Mantığı (Business Logic)
  bool get canReceiveOffers => status == ListingStatus.active;
  bool get isPassive => status == ListingStatus.passive;
}

class ListingDetailNotifier extends StateNotifier<ListingDetailState> {
  ListingDetailNotifier(int listingId) : super(ListingDetailState(id: listingId));

  void initFromData(Map<String, dynamic> data) {
    state = state.copyWith(status: ListingStatusExtension.fromJson(data));
  }

  Future<void> refreshStatus() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final data = await ListingService.getListingById(state.id);
      if (data != null) {
        state = state.copyWith(
          status: ListingStatusExtension.fromJson(data),
          isLoading: false,
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
