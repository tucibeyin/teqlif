/// Kayıt durumu — backend state machine ile eşleşir.
enum RecordingStatus {
  recording,
  encoding,
  encoded,
  transferring,
  available,
  expired,
  archived,
  failed;

  static RecordingStatus fromString(String s) =>
      RecordingStatus.values.firstWhere(
        (e) => e.name == s,
        orElse: () => RecordingStatus.failed,
      );

  bool get isProcessing =>
      this == recording || this == encoding || this == encoded || this == transferring;

  bool get canWatch => this == available;

  bool get isOver => this == expired || this == archived;
}

// ── GET /recordings/my ───────────────────────────────────────────────────────

class RecordingItem {
  final int recordingId;
  final int streamId;
  final String streamTitle;
  final RecordingStatus status;
  final int? durationSecs;
  final int? encodedSizeBytes;
  final DateTime? availableAt;
  final DateTime? expiresAt;
  final DateTime? recordingStartedAt;

  const RecordingItem({
    required this.recordingId,
    required this.streamId,
    required this.streamTitle,
    required this.status,
    this.durationSecs,
    this.encodedSizeBytes,
    this.availableAt,
    this.expiresAt,
    this.recordingStartedAt,
  });

  factory RecordingItem.fromJson(Map<String, dynamic> j) => RecordingItem(
        recordingId: j['recording_id'] as int,
        streamId: j['stream_id'] as int,
        streamTitle: j['stream_title'] as String? ?? '',
        status: RecordingStatus.fromString(j['status'] as String? ?? 'failed'),
        durationSecs: j['duration_secs'] as int?,
        encodedSizeBytes: j['encoded_size_bytes'] as int?,
        availableAt: _dt(j['available_at']),
        expiresAt: _dt(j['expires_at']),
        recordingStartedAt: _dt(j['recording_started_at']),
      );

  Map<String, dynamic> toJson() => {
        'recording_id': recordingId,
        'stream_id': streamId,
        'stream_title': streamTitle,
        'status': status.name,
        'duration_secs': durationSecs,
        'encoded_size_bytes': encodedSizeBytes,
        'available_at': availableAt?.toIso8601String(),
        'expires_at': expiresAt?.toIso8601String(),
        'recording_started_at': recordingStartedAt?.toIso8601String(),
      };
}

// ── GET /streams/{id}/recording ─────────────────────────────────────────────

class RecordingUrlData {
  final int recordingId;
  final String url;
  final DateTime? availableAt;
  final DateTime? expiresAt;

  const RecordingUrlData({
    required this.recordingId,
    required this.url,
    this.availableAt,
    this.expiresAt,
  });

  factory RecordingUrlData.fromJson(Map<String, dynamic> j) => RecordingUrlData(
        recordingId: j['recording_id'] as int,
        url: j['url'] as String,
        availableAt: _dt(j['available_at']),
        expiresAt: _dt(j['expires_at']),
      );

  Map<String, dynamic> toJson() => {
        'recording_id': recordingId,
        'url': url,
        'available_at': availableAt?.toIso8601String(),
        'expires_at': expiresAt?.toIso8601String(),
      };
}

// ── GET /streams/{id}/recording-summary ─────────────────────────────────────

class RecordingDetail {
  final RecordingStreamMeta stream;
  final RecordingMetrics metrics;
  final List<RecordingAuction> auctions;
  final List<RecordingDirectSale> directSales;
  final RecordingGifts gifts;

  const RecordingDetail({
    required this.stream,
    required this.metrics,
    required this.auctions,
    required this.directSales,
    required this.gifts,
  });

  factory RecordingDetail.fromJson(Map<String, dynamic> j) => RecordingDetail(
        stream: RecordingStreamMeta.fromJson(j['stream'] as Map<String, dynamic>),
        metrics: RecordingMetrics.fromJson(j['metrics'] as Map<String, dynamic>),
        auctions: (j['auctions'] as List? ?? [])
            .cast<Map<String, dynamic>>()
            .map(RecordingAuction.fromJson)
            .toList(),
        directSales: (j['direct_sales'] as List? ?? [])
            .cast<Map<String, dynamic>>()
            .map(RecordingDirectSale.fromJson)
            .toList(),
        gifts: RecordingGifts.fromJson(j['gifts'] as Map<String, dynamic>? ?? {}),
      );

  Map<String, dynamic> toJson() => {
        'stream': stream.toJson(),
        'metrics': metrics.toJson(),
        'auctions': auctions.map((e) => e.toJson()).toList(),
        'direct_sales': directSales.map((e) => e.toJson()).toList(),
        'gifts': gifts.toJson(),
      };
}

class RecordingStreamMeta {
  final int id;
  final String title;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final int? peakViewerCount;
  final String? thumbnailUrl;

  const RecordingStreamMeta({
    required this.id,
    required this.title,
    this.startedAt,
    this.endedAt,
    this.peakViewerCount,
    this.thumbnailUrl,
  });

  factory RecordingStreamMeta.fromJson(Map<String, dynamic> j) =>
      RecordingStreamMeta(
        id: j['id'] as int,
        title: j['title'] as String? ?? '',
        startedAt: _dt(j['started_at']),
        endedAt: _dt(j['ended_at']),
        peakViewerCount: j['peak_viewer_count'] as int?,
        thumbnailUrl: j['thumbnail_url'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'started_at': startedAt?.toIso8601String(),
        'ended_at': endedAt?.toIso8601String(),
        'peak_viewer_count': peakViewerCount,
        'thumbnail_url': thumbnailUrl,
      };
}

class RecordingMetrics {
  final double totalRevenue;
  final int totalBids;
  final int totalSales;

  const RecordingMetrics({
    required this.totalRevenue,
    required this.totalBids,
    required this.totalSales,
  });

  factory RecordingMetrics.fromJson(Map<String, dynamic> j) => RecordingMetrics(
        totalRevenue: (j['total_revenue'] as num?)?.toDouble() ?? 0.0,
        totalBids: j['total_bids'] as int? ?? 0,
        totalSales: j['total_sales'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'total_revenue': totalRevenue,
        'total_bids': totalBids,
        'total_sales': totalSales,
      };
}

class RecordingParticipant {
  final int userId;
  final String username;
  final String? avatarUrl;

  const RecordingParticipant({
    required this.userId,
    required this.username,
    this.avatarUrl,
  });

  factory RecordingParticipant.fromJson(Map<String, dynamic> j) =>
      RecordingParticipant(
        userId: j['user_id'] as int,
        username: j['username'] as String? ?? '',
        avatarUrl: j['avatar_url'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'username': username,
        'avatar_url': avatarUrl,
      };
}

class RecordingBid {
  final int userId;
  final String username;
  final String? avatarUrl;
  final double amount;
  final DateTime? createdAt;

  const RecordingBid({
    required this.userId,
    required this.username,
    this.avatarUrl,
    required this.amount,
    this.createdAt,
  });

  factory RecordingBid.fromJson(Map<String, dynamic> j) => RecordingBid(
        userId: j['user_id'] as int,
        username: j['username'] as String? ?? '',
        avatarUrl: j['avatar_url'] as String?,
        amount: (j['amount'] as num).toDouble(),
        createdAt: _dt(j['created_at']),
      );

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'username': username,
        'avatar_url': avatarUrl,
        'amount': amount,
        'created_at': createdAt?.toIso8601String(),
      };
}

class RecordingAuction {
  final int auctionId;
  final String itemName;
  final String? proofImageUrl;
  final double? startPrice;
  final double? finalPrice;
  final double? buyItNowPrice;
  final bool isBoughtItNow;
  final int bidCount;
  final int? durationMinutes;
  final bool sold;
  final RecordingParticipant? winner;
  final List<RecordingBid> bids;

  const RecordingAuction({
    required this.auctionId,
    required this.itemName,
    this.proofImageUrl,
    this.startPrice,
    this.finalPrice,
    this.buyItNowPrice,
    required this.isBoughtItNow,
    required this.bidCount,
    this.durationMinutes,
    required this.sold,
    this.winner,
    required this.bids,
  });

  factory RecordingAuction.fromJson(Map<String, dynamic> j) => RecordingAuction(
        auctionId: j['auction_id'] as int,
        itemName: j['item_name'] as String? ?? '',
        proofImageUrl: j['proof_image_url'] as String?,
        startPrice: (j['start_price'] as num?)?.toDouble(),
        finalPrice: (j['final_price'] as num?)?.toDouble(),
        buyItNowPrice: (j['buy_it_now_price'] as num?)?.toDouble(),
        isBoughtItNow: j['is_bought_it_now'] as bool? ?? false,
        bidCount: j['bid_count'] as int? ?? 0,
        durationMinutes: j['duration_minutes'] as int?,
        sold: j['sold'] as bool? ?? false,
        winner: j['winner'] != null
            ? RecordingParticipant.fromJson(j['winner'] as Map<String, dynamic>)
            : null,
        bids: (j['bids'] as List? ?? [])
            .cast<Map<String, dynamic>>()
            .map(RecordingBid.fromJson)
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'auction_id': auctionId,
        'item_name': itemName,
        'proof_image_url': proofImageUrl,
        'start_price': startPrice,
        'final_price': finalPrice,
        'buy_it_now_price': buyItNowPrice,
        'is_bought_it_now': isBoughtItNow,
        'bid_count': bidCount,
        'duration_minutes': durationMinutes,
        'sold': sold,
        'winner': winner?.toJson(),
        'bids': bids.map((e) => e.toJson()).toList(),
      };
}

class RecordingOrder {
  final int userId;
  final String username;
  final String? avatarUrl;
  final int quantity;
  final double unitPrice;
  final DateTime? createdAt;

  const RecordingOrder({
    required this.userId,
    required this.username,
    this.avatarUrl,
    required this.quantity,
    required this.unitPrice,
    this.createdAt,
  });

  factory RecordingOrder.fromJson(Map<String, dynamic> j) => RecordingOrder(
        userId: j['user_id'] as int,
        username: j['username'] as String? ?? '',
        avatarUrl: j['avatar_url'] as String?,
        quantity: j['quantity'] as int,
        unitPrice: (j['unit_price'] as num).toDouble(),
        createdAt: _dt(j['created_at']),
      );

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'username': username,
        'avatar_url': avatarUrl,
        'quantity': quantity,
        'unit_price': unitPrice,
        'created_at': createdAt?.toIso8601String(),
      };
}

class RecordingDirectSale {
  final int saleId;
  final String title;
  final String? productImageUrl;
  final double? price;
  final int? totalStock;
  final int soldCount;
  final int? viewerCountAtStart;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final List<RecordingOrder> orders;

  const RecordingDirectSale({
    required this.saleId,
    required this.title,
    this.productImageUrl,
    this.price,
    this.totalStock,
    required this.soldCount,
    this.viewerCountAtStart,
    this.startedAt,
    this.endedAt,
    required this.orders,
  });

  factory RecordingDirectSale.fromJson(Map<String, dynamic> j) =>
      RecordingDirectSale(
        saleId: j['sale_id'] as int,
        title: j['title'] as String? ?? '',
        productImageUrl: j['product_image_url'] as String?,
        price: (j['price'] as num?)?.toDouble(),
        totalStock: j['total_stock'] as int?,
        soldCount: j['sold_count'] as int? ?? 0,
        viewerCountAtStart: j['viewer_count_at_start'] as int?,
        startedAt: _dt(j['started_at']),
        endedAt: _dt(j['ended_at']),
        orders: (j['orders'] as List? ?? [])
            .cast<Map<String, dynamic>>()
            .map(RecordingOrder.fromJson)
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'sale_id': saleId,
        'title': title,
        'product_image_url': productImageUrl,
        'price': price,
        'total_stock': totalStock,
        'sold_count': soldCount,
        'viewer_count_at_start': viewerCountAtStart,
        'started_at': startedAt?.toIso8601String(),
        'ended_at': endedAt?.toIso8601String(),
        'orders': orders.map((e) => e.toJson()).toList(),
      };
}

class RecordingGiftEvent {
  final int userId;
  final String username;
  final String? avatarUrl;
  final String giftName;
  final int costTeqlik;
  final DateTime? sentAt;

  const RecordingGiftEvent({
    required this.userId,
    required this.username,
    this.avatarUrl,
    required this.giftName,
    required this.costTeqlik,
    this.sentAt,
  });

  factory RecordingGiftEvent.fromJson(Map<String, dynamic> j) =>
      RecordingGiftEvent(
        userId: j['user_id'] as int,
        username: j['username'] as String? ?? '',
        avatarUrl: j['avatar_url'] as String?,
        giftName: j['gift_name'] as String? ?? '',
        costTeqlik: j['cost_teqlik'] as int? ?? 0,
        sentAt: _dt(j['sent_at']),
      );

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'username': username,
        'avatar_url': avatarUrl,
        'gift_name': giftName,
        'cost_teqlik': costTeqlik,
        'sent_at': sentAt?.toIso8601String(),
      };
}

class RecordingGifts {
  final int totalTeqlik;
  final int totalHostShare;
  final int senderCount;
  final List<RecordingGiftEvent> events;

  const RecordingGifts({
    required this.totalTeqlik,
    required this.totalHostShare,
    required this.senderCount,
    required this.events,
  });

  factory RecordingGifts.fromJson(Map<String, dynamic> j) => RecordingGifts(
        totalTeqlik: j['total_teqlik'] as int? ?? 0,
        totalHostShare: j['total_host_share'] as int? ?? 0,
        senderCount: j['sender_count'] as int? ?? 0,
        events: (j['events'] as List? ?? [])
            .cast<Map<String, dynamic>>()
            .map(RecordingGiftEvent.fromJson)
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'total_teqlik': totalTeqlik,
        'total_host_share': totalHostShare,
        'sender_count': senderCount,
        'events': events.map((e) => e.toJson()).toList(),
      };
}

// ── Helpers ──────────────────────────────────────────────────────────────────

DateTime? _dt(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  try {
    return DateTime.parse(v.toString()).toLocal();
  } catch (_) {
    return null;
  }
}
