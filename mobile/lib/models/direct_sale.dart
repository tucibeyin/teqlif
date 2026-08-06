// Direkt satış state'i — GET /direct-sales/{stream_id}/state + WS event'lerinden beslenir.
class DirectSaleState {
  final String status; // idle, active, paused, sold_out, ended, cancelled
  final int saleId;
  final String title;
  final double price;
  final int totalStock;
  final int remainingStock;
  final String? productImageUrl;
  final String? proofImageUrl;
  final String? endReason; // sold_out | host_ended | stream_closed

  const DirectSaleState({
    required this.status,
    required this.saleId,
    required this.title,
    required this.price,
    required this.totalStock,
    required this.remainingStock,
    this.productImageUrl,
    this.proofImageUrl,
    this.endReason,
  });

  factory DirectSaleState.idle() => const DirectSaleState(
        status: 'idle',
        saleId: 0,
        title: '',
        price: 0,
        totalStock: 0,
        remainingStock: 0,
      );

  factory DirectSaleState.fromJson(Map<String, dynamic> j) => DirectSaleState(
        status: j['status'] as String? ?? 'idle',
        saleId: (j['sale_id'] as num?)?.toInt() ?? 0,
        title: j['title'] as String? ?? '',
        price: (j['price'] as num?)?.toDouble() ?? 0,
        totalStock: (j['total_stock'] as num?)?.toInt() ?? 0,
        remainingStock: (j['remaining_stock'] as num?)?.toInt() ?? 0,
        productImageUrl: j['product_image_url'] as String?,
        proofImageUrl: j['proof_image_url'] as String?,
        endReason: j['end_reason'] as String?,
      );

  DirectSaleState copyWith({
    String? status,
    int? saleId,
    String? title,
    double? price,
    int? totalStock,
    int? remainingStock,
    String? productImageUrl,
    String? proofImageUrl,
    String? endReason,
  }) =>
      DirectSaleState(
        status: status ?? this.status,
        saleId: saleId ?? this.saleId,
        title: title ?? this.title,
        price: price ?? this.price,
        totalStock: totalStock ?? this.totalStock,
        remainingStock: remainingStock ?? this.remainingStock,
        productImageUrl: productImageUrl ?? this.productImageUrl,
        proofImageUrl: proofImageUrl ?? this.proofImageUrl,
        endReason: endReason ?? this.endReason,
      );

  bool get isIdle => status == 'idle';
  bool get isActive => status == 'active';
  bool get isPaused => status == 'paused';
  bool get isSoldOut => status == 'sold_out';
  bool get isEnded => status == 'ended';
  bool get isCancelled => status == 'cancelled';
  bool get isTerminal => isEnded || isCancelled;

  // Viewer satın alabilir mi?
  bool get canPurchase => isActive && remainingStock > 0;

  // Viewer'a gösterilecek görsel önceliği: proof → product → null
  String? get displayImageUrl => proofImageUrl ?? productImageUrl;
}

// ── Satın alma siparişi (GET /direct-sales/{id}/orders) ──────────────────────

class DirectSaleOrder {
  final int id;
  final String buyerUsername;
  final int quantity;
  final double unitPrice;
  final double totalPrice;
  final String status; // completed | cancelled
  final DateTime createdAt;

  const DirectSaleOrder({
    required this.id,
    required this.buyerUsername,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
    required this.status,
    required this.createdAt,
  });

  factory DirectSaleOrder.fromJson(Map<String, dynamic> j) => DirectSaleOrder(
        id: (j['id'] as num).toInt(),
        buyerUsername: j['buyer_username'] as String,
        quantity: (j['quantity'] as num).toInt(),
        unitPrice: (j['unit_price'] as num).toDouble(),
        totalPrice: (j['total_price'] as num).toDouble(),
        status: j['status'] as String,
        createdAt: DateTime.parse(j['created_at'] as String),
      );

  bool get isCancelled => status == 'cancelled';
}

// ── Satış özeti (GET /direct-sales/{id}/summary) ─────────────────────────────

class DirectSaleSummary {
  final String role; // buyer | seller
  final int saleId;
  final String itemName;
  final String? proofImageUrl;
  final String? imageUrl;
  final String status;
  final String? endReason;
  final DateTime? endedAt;

  // Satıcı alanları
  final double? totalRevenue;
  final int? totalQuantitySold;
  final int? orderCount;

  // Alıcı alanları
  final String? sellerUsername;
  final int? buyerQuantity;
  final double? buyerUnitPrice;
  final double? buyerTotal;
  final String? buyerOrderStatus;

  const DirectSaleSummary({
    required this.role,
    required this.saleId,
    required this.itemName,
    required this.status,
    this.proofImageUrl,
    this.imageUrl,
    this.endReason,
    this.endedAt,
    this.totalRevenue,
    this.totalQuantitySold,
    this.orderCount,
    this.sellerUsername,
    this.buyerQuantity,
    this.buyerUnitPrice,
    this.buyerTotal,
    this.buyerOrderStatus,
  });

  factory DirectSaleSummary.fromJson(Map<String, dynamic> j) =>
      DirectSaleSummary(
        role: j['role'] as String,
        saleId: (j['sale_id'] as num).toInt(),
        itemName: j['item_name'] as String,
        status: j['status'] as String,
        proofImageUrl: j['proof_image_url'] as String?,
        imageUrl: j['image_url'] as String?,
        endReason: j['end_reason'] as String?,
        endedAt: j['ended_at'] != null
            ? DateTime.parse(j['ended_at'] as String)
            : null,
        totalRevenue: (j['total_revenue'] as num?)?.toDouble(),
        totalQuantitySold: (j['total_quantity_sold'] as num?)?.toInt(),
        orderCount: (j['order_count'] as num?)?.toInt(),
        sellerUsername: j['seller_username'] as String?,
        buyerQuantity: (j['buyer_quantity'] as num?)?.toInt(),
        buyerUnitPrice: (j['buyer_unit_price'] as num?)?.toDouble(),
        buyerTotal: (j['buyer_total'] as num?)?.toDouble(),
        buyerOrderStatus: j['buyer_order_status'] as String?,
      );

  bool get isSeller => role == 'seller';
  bool get isBuyer => role == 'buyer';
  String? get displayImageUrl => proofImageUrl ?? imageUrl;
}

// ── Unified Commerce modelleri (§10.3) — /me/commerce/* için ─────────────────

enum CommerceType { auction, directSale }

class CommercePurchase {
  final CommerceType type;
  final int id; // order_id (direct) | auction_id (auction)
  final int? saleId; // direct_sale.id; null → auction
  final String itemName;
  final double finalPrice;
  final double? unitPrice; // null → auction
  final int? quantity; // null → auction
  final String? sellerUsername;
  final String? imageUrl;
  final String? proofImageUrl;
  final String orderStatus; // completed | cancelled
  final bool? isBoughtItNow; // null → direct
  final DateTime createdAt;

  const CommercePurchase({
    required this.type,
    required this.id,
    required this.itemName,
    required this.finalPrice,
    required this.orderStatus,
    required this.createdAt,
    this.saleId,
    this.unitPrice,
    this.quantity,
    this.sellerUsername,
    this.imageUrl,
    this.proofImageUrl,
    this.isBoughtItNow,
  });

  factory CommercePurchase.fromJson(Map<String, dynamic> j) {
    final typeStr = j['type'] as String;
    return CommercePurchase(
      type: typeStr == 'direct' ? CommerceType.directSale : CommerceType.auction,
      id: (j['id'] as num).toInt(),
      saleId: (j['sale_id'] as num?)?.toInt(),
      itemName: j['item_name'] as String,
      finalPrice: (j['final_price'] as num).toDouble(),
      unitPrice: (j['unit_price'] as num?)?.toDouble(),
      quantity: (j['quantity'] as num?)?.toInt(),
      sellerUsername: j['seller_username'] as String?,
      imageUrl: j['image_url'] as String?,
      proofImageUrl: j['proof_image_url'] as String?,
      orderStatus: j['order_status'] as String? ?? 'completed',
      isBoughtItNow: j['is_bought_it_now'] as bool?,
      createdAt: DateTime.parse(j['created_at'] as String),
    );
  }

  bool get isDirectSale => type == CommerceType.directSale;
  bool get isCancelled => orderStatus == 'cancelled';
}

class CommerceSale {
  final CommerceType type;
  final int id;
  final String itemName;
  final double totalRevenue;
  final int? totalQuantitySold; // null → auction
  final int? orderCount; // null → auction
  final String? buyerUsername; // null → direct (çoklu alıcı)
  final String? imageUrl;
  final DateTime? endedAt;
  final String? endReason; // null → auction
  final bool? ordersVoided; // null → auction

  const CommerceSale({
    required this.type,
    required this.id,
    required this.itemName,
    required this.totalRevenue,
    this.totalQuantitySold,
    this.orderCount,
    this.buyerUsername,
    this.imageUrl,
    this.endedAt,
    this.endReason,
    this.ordersVoided,
  });

  factory CommerceSale.fromJson(Map<String, dynamic> j) {
    final typeStr = j['type'] as String;
    return CommerceSale(
      type: typeStr == 'direct' ? CommerceType.directSale : CommerceType.auction,
      id: (j['id'] as num).toInt(),
      itemName: j['item_name'] as String,
      totalRevenue: (j['total_revenue'] as num).toDouble(),
      totalQuantitySold: (j['total_quantity_sold'] as num?)?.toInt(),
      orderCount: (j['order_count'] as num?)?.toInt(),
      buyerUsername: j['buyer_username'] as String?,
      imageUrl: j['image_url'] as String?,
      endedAt: j['ended_at'] != null
          ? DateTime.parse(j['ended_at'] as String)
          : null,
      endReason: j['end_reason'] as String?,
      ordersVoided: j['orders_voided'] as bool?,
    );
  }

  bool get isDirectSale => type == CommerceType.directSale;
}
