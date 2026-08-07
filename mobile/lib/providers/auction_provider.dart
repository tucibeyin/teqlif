import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/auction.dart';
import 'stream_commerce_notifier.dart';

/// Bir [streamId] için açık artırma state'ini yönetir.
/// WS altyapısı [StreamCommerceNotifier] base class'ında; bu sınıf yalnızca
/// auction domain logic'ini içerir.
class AuctionNotifier extends StreamCommerceNotifier<AuctionState> {
  AuctionNotifier(int streamId) : super(streamId, AuctionState.idle());

  @override
  void onCommerceEvent(String type, Map<String, dynamic> json) {
    if (type == 'state') {
      state = AuctionState.fromJson(json);
    } else if (type == 'auction_ended_by_buy_it_now') {
      final buyer = json['buyer'] as Map<String, dynamic>?;
      final buyerUsername = buyer?['username'] as String?;
      state = AuctionState(
        status: 'ended',
        itemName: json['item_name'] as String? ?? state.itemName,
        startPrice: state.startPrice,
        buyItNowPrice: state.buyItNowPrice,
        currentBid: (json['price'] as num?)?.toDouble(),
        currentBidder: buyerUsername,
        bidCount: state.bidCount,
        listingId: state.listingId,
        isBoughtItNow: true,
        buyerUsername: buyerUsername,
      );
    }
    // direct_sale_* ve diğer event tipleri görmezden gelinir
  }

  /// Host aksiyonu (start/pause/resume/end/accept) başarıyla döndüğünde
  /// WS broadcast beklenmeden state'i anında günceller.
  void applyState(AuctionState newState) {
    state = newState;
  }
}

/// Verilen [streamId] için otomatik dispose edilen açık artırma provider'ı.
/// Widget ağacından ayrıldığında WS bağlantısı kapatılır.
final auctionProvider =
    StateNotifierProvider.family.autoDispose<AuctionNotifier, AuctionState, int>(
  (ref, streamId) => AuctionNotifier(streamId),
);
