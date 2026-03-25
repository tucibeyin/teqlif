class ListingOffer {
  final int id;
  final int listingId;
  final int userId;
  final String username;
  final String? profileImageUrl;
  final double amount;
  final DateTime createdAt;

  const ListingOffer({
    required this.id,
    required this.listingId,
    required this.userId,
    required this.username,
    this.profileImageUrl,
    required this.amount,
    required this.createdAt,
  });

  factory ListingOffer.fromJson(Map<String, dynamic> j) {
    return ListingOffer(
      id: (j['id'] as int?) ?? 0,
      listingId: (j['listing_id'] as int?) ?? 0,
      userId: (j['user_id'] as int?) ?? 0,
      username: j['username'] as String? ?? '',
      profileImageUrl: j['profile_image_url'] as String?,
      amount: (j['amount'] as num?)?.toDouble() ?? 0.0,
      createdAt: DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
