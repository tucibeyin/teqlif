import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/listing_service.dart';

class ListingInteractionNotifier extends StateNotifier<Map<int, bool>> {
  ListingInteractionNotifier() : super({});

  void setLike(int id, bool isLiked) {
    if (state[id] == isLiked) return;
    state = {...state, id: isLiked};
  }

  bool? getLike(int id) {
    return state[id] ?? ListingService.getCachedLike(id);
  }
}

final listingInteractionCacheProvider = StateNotifierProvider<ListingInteractionNotifier, Map<int, bool>>((ref) {
  final notifier = ListingInteractionNotifier();
  ListingService.interactionNotifier = notifier;
  return notifier;
});
