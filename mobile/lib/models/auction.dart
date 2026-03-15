class AuctionState {
  final String status; // idle, active, paused, ended
  final String? itemName;
  final double? startPrice;
  final double? currentBid;
  final String? currentBidder;
  final int bidCount;
  final int? listingId;

  const AuctionState({
    required this.status,
    this.itemName,
    this.startPrice,
    this.currentBid,
    this.currentBidder,
    this.bidCount = 0,
    this.listingId,
  });

  factory AuctionState.idle() => const AuctionState(status: 'idle');

  factory AuctionState.fromJson(Map<String, dynamic> j) => AuctionState(
        status: j['status'] as String? ?? 'idle',
        itemName: j['item_name'] as String?,
        startPrice: (j['start_price'] as num?)?.toDouble(),
        currentBid: (j['current_bid'] as num?)?.toDouble(),
        currentBidder: j['current_bidder'] as String?,
        bidCount: (j['bid_count'] as num?)?.toInt() ?? 0,
        listingId: (j['listing_id'] as num?)?.toInt(),
      );

  bool get isActive => status == 'active';
  bool get isPaused => status == 'paused';
  bool get isIdle => status == 'idle';
  bool get isEnded => status == 'ended';
}
