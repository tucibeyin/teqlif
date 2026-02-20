class CategoryModel {
  final String id;
  final String name;
  final String slug;
  final String? icon;

  const CategoryModel({
    required this.id,
    required this.name,
    required this.slug,
    this.icon,
  });

  factory CategoryModel.fromJson(Map<String, dynamic> json) => CategoryModel(
        id: json['id'] as String,
        name: json['name'] as String,
        slug: json['slug'] as String,
        icon: json['icon'] as String?,
      );
}

class AdUserModel {
  final String? name;
  const AdUserModel({this.name});
  factory AdUserModel.fromJson(Map<String, dynamic>? json) =>
      AdUserModel(name: json?['name'] as String?);
}

class AdCountModel {
  final int bids;
  const AdCountModel({required this.bids});
  factory AdCountModel.fromJson(Map<String, dynamic>? json) =>
      AdCountModel(bids: json?['bids'] as int? ?? 0);
}

class ProvinceModel {
  final String id;
  final String name;
  const ProvinceModel({required this.id, required this.name});
  factory ProvinceModel.fromJson(Map<String, dynamic>? json) => ProvinceModel(
      id: json?['id'] as String? ?? '',
      name: json?['name'] as String? ?? '');
}

class DistrictModel {
  final String id;
  final String name;
  const DistrictModel({required this.id, required this.name});
  factory DistrictModel.fromJson(Map<String, dynamic>? json) => DistrictModel(
      id: json?['id'] as String? ?? '',
      name: json?['name'] as String? ?? '');
}

class AdModel {
  final String id;
  final String title;
  final String description;
  final double price;
  final double? startingBid;
  final double minBidStep;
  final bool isFixedPrice;
  final double? buyItNowPrice;
  final String status;
  final List<String> images;
  final int views;
  final DateTime? expiresAt;
  final DateTime createdAt;
  final String userId;
  final AdUserModel? user;
  final CategoryModel? category;
  final ProvinceModel? province;
  final DistrictModel? district;
  final AdCountModel? count;
  final List<BidModel> bids;

  const AdModel({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
    this.startingBid,
    this.minBidStep = 1,
    this.isFixedPrice = false,
    this.buyItNowPrice,
    required this.status,
    required this.images,
    required this.views,
    this.expiresAt,
    required this.createdAt,
    required this.userId,
    this.user,
    this.category,
    this.province,
    this.district,
    this.count,
    this.bids = const [],
  });

  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());

  double? get highestBidAmount {
    if (bids.isNotEmpty) {
      return bids.fold<double>(
          0, (max, bid) => bid.amount > max ? bid.amount : max);
    }
    return null;
  }

  factory AdModel.fromJson(Map<String, dynamic> json) => AdModel(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String,
        price: (json['price'] as num).toDouble(),
        startingBid: json['startingBid'] != null
            ? (json['startingBid'] as num).toDouble()
            : null,
        minBidStep:
            (json['minBidStep'] as num?)?.toDouble() ?? 1,
        isFixedPrice: json['isFixedPrice'] as bool? ?? false,
        buyItNowPrice: json['buyItNowPrice'] != null
            ? (json['buyItNowPrice'] as num).toDouble()
            : null,
        status: json['status'] as String? ?? 'ACTIVE',
        images: (json['images'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        views: json['views'] as int? ?? 0,
        expiresAt: json['expiresAt'] != null
            ? DateTime.parse(json['expiresAt'] as String)
            : null,
        createdAt: DateTime.parse(json['createdAt'] as String),
        userId: json['userId'] as String? ?? '',
        user: json['user'] != null
            ? AdUserModel.fromJson(json['user'] as Map<String, dynamic>)
            : null,
        category: json['category'] != null
            ? CategoryModel.fromJson(json['category'] as Map<String, dynamic>)
            : null,
        province: json['province'] != null
            ? ProvinceModel.fromJson(json['province'] as Map<String, dynamic>)
            : null,
        district: json['district'] != null
            ? DistrictModel.fromJson(json['district'] as Map<String, dynamic>)
            : null,
        count: json['_count'] != null
            ? AdCountModel.fromJson(json['_count'] as Map<String, dynamic>)
            : null,
        bids: (json['bids'] as List<dynamic>?)
                ?.map((e) => BidModel.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
}

class BidUserModel {
  final String id;
  final String name;
  const BidUserModel({required this.id, required this.name});
  factory BidUserModel.fromJson(Map<String, dynamic>? json) => BidUserModel(
      id: json?['id'] as String? ?? '',
      name: json?['name'] as String? ?? '');
}

class BidModel {
  final String id;
  final double amount;
  final String status;
  final String userId;
  final String adId;
  final DateTime createdAt;
  final BidUserModel? user;

  const BidModel({
    required this.id,
    required this.amount,
    required this.status,
    required this.userId,
    required this.adId,
    required this.createdAt,
    this.user,
  });

  factory BidModel.fromJson(Map<String, dynamic> json) => BidModel(
        id: json['id'] as String? ?? '',
        amount: (json['amount'] as num).toDouble(),
        status: json['status'] as String? ?? 'PENDING',
        userId: json['userId'] as String? ?? '',
        adId: json['adId'] as String? ?? '',
        createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt'] as String) : DateTime.now(),
        user: json['user'] != null
            ? BidUserModel.fromJson(json['user'] as Map<String, dynamic>)
            : null,
      );
}
