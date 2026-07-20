enum ListingStatus {
  active,
  passive,
  sold,
  suspended,
  expired,
  deleted,
}

extension ListingStatusExtension on ListingStatus {
  static ListingStatus fromJson(Map<String, dynamic> json) {
    final statusStr = json['status'] as String?;
    if (statusStr != null) {
      return ListingStatus.values.firstWhere(
        (e) => e.name == statusStr,
        orElse: () => ListingStatus.active,
      );
    }
    
    // Geriye dönük uyumluluk tamamen kaldırıldı, backend artık sadece 'status' Enum dönüyor.
    return ListingStatus.active;
  }
}

enum UserStatus {
  active,
  passive,
  banned,
  deleted,
}

extension UserStatusExtension on UserStatus {
  static UserStatus fromJson(Map<String, dynamic> json) {
    final statusStr = json['status'] as String?;
    if (statusStr != null) {
      return UserStatus.values.firstWhere(
        (e) => e.name == statusStr,
        orElse: () => UserStatus.active,
      );
    }
    return UserStatus.active;
  }
}

enum CategoryStatus {
  active,
  passive,
}

extension CategoryStatusExtension on CategoryStatus {
  static CategoryStatus fromJson(Map<String, dynamic> json) {
    final statusStr = json['status'] as String?;
    if (statusStr != null) {
      return CategoryStatus.values.firstWhere(
        (e) => e.name == statusStr,
        orElse: () => CategoryStatus.active,
      );
    }
    return CategoryStatus.active;
  }
}

enum SearchAlertStatus {
  active,
  passive,
}

extension SearchAlertStatusExtension on SearchAlertStatus {
  static SearchAlertStatus fromJson(Map<String, dynamic> json) {
    final statusStr = json['status'] as String?;
    if (statusStr != null) {
      return SearchAlertStatus.values.firstWhere(
        (e) => e.name == statusStr,
        orElse: () => SearchAlertStatus.active,
      );
    }
    return SearchAlertStatus.active;
  }
}
