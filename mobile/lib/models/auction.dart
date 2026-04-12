class AuctionState {
  final String status; // idle, active, paused, ended, buy_it_now_pending, error
  final String? itemName;
  final double? startPrice;
  final double? buyItNowPrice;
  final double? currentBid;
  final String? currentBidder;
  final int bidCount;
  final int? listingId;
  final bool isBoughtItNow;
  final String? buyerUsername;
  final String? pendingBuyerUsername;
  final String? errorMessage;
  final bool winnerAccepted; // true → accept_bid ile bitti (konfeti); false → end ile kesildi

  const AuctionState({
    required this.status,
    this.itemName,
    this.startPrice,
    this.buyItNowPrice,
    this.currentBid,
    this.currentBidder,
    this.bidCount = 0,
    this.listingId,
    this.isBoughtItNow = false,
    this.buyerUsername,
    this.pendingBuyerUsername,
    this.errorMessage,
    this.winnerAccepted = false,
  });

  factory AuctionState.idle() => const AuctionState(status: 'idle');

  factory AuctionState.error(String message) =>
      AuctionState(status: 'error', errorMessage: message);

  factory AuctionState.fromJson(Map<String, dynamic> j) => AuctionState(
        status: j['status'] as String? ?? 'idle',
        itemName: j['item_name'] as String?,
        startPrice: (j['start_price'] as num?)?.toDouble(),
        buyItNowPrice: (j['buy_it_now_price'] as num?)?.toDouble(),
        currentBid: (j['current_bid'] as num?)?.toDouble(),
        currentBidder: j['current_bidder'] as String?,
        bidCount: (j['bid_count'] as num?)?.toInt() ?? 0,
        listingId: (j['listing_id'] as num?)?.toInt(),
        pendingBuyerUsername: j['bin_buyer_username'] as String?,
        winnerAccepted: j['winner_accepted'] as bool? ?? false,
      );

  bool get isActive => status == 'active';
  bool get isPaused => status == 'paused';
  bool get isIdle => status == 'idle';
  bool get isEnded => status == 'ended';
  bool get isPending => status == 'buy_it_now_pending';
  bool get isError => status == 'error';
}
