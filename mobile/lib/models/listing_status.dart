enum ListingStatus {
  active,
  passive,
  sold,
  suspended,
  expired,
}

extension ListingStatusExtension on ListingStatus {
  static ListingStatus fromJson(Map<String, dynamic> json) {
    // Gelecekte backend enum'a geçtiğinde burası güncellenecektir:
    // final statusStr = json['status'] as String?;
    // if (statusStr != null) {
    //   return ListingStatus.values.firstWhere(
    //     (e) => e.name == statusStr,
    //     orElse: () => ListingStatus.active,
    //   );
    // }

    // Geriye dönük uyumluluk (is_active boolean'ına dayalı parsing)
    final isActive = json['is_active'] as bool? ?? true;
    final isDeleted = json['is_deleted'] as bool? ?? false;

    if (isDeleted) {
      return ListingStatus.passive; // Sistemde silinmiş görünüm pasif olarak yönetilebilir
    }

    return isActive ? ListingStatus.active : ListingStatus.passive;
  }
}
