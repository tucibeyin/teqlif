/// Kullanıcı tier sabitleri ve yardımcıları — Flutter karşılığı: backend/tier.py
///
/// TEK KAYNAK: Tüm tier mantığı buradan okunur.
/// Hiçbir ekran/widget literal tier değeri içermemelidir.
abstract class UserTier {
  static const standard = 'standard';
  static const pro      = 'pro';
  static const proPlus  = 'pro_plus';
  static const premium  = 'premium';

  /// Ücretli tier (PRO, PRO+ veya PREMIUM) ise true döner.
  static bool isPaidTier(String userType) => userType != standard;

  /// Yalnızca PRO tier ise true döner.
  static bool isPro(String userType) => userType == pro;

  /// PRO+ veya üstü ise true döner.
  static bool isProPlusOrAbove(String userType) =>
      userType == proPlus || userType == premium;

  /// Yalnızca PREMIUM tier ise true döner.
  static bool isPremiumTier(String userType) => userType == premium;

  /// Aylık yayın süresi sınırı (saniye). null = sınırsız (PREMIUM).
  static int? streamLimitSeconds(String userType) {
    switch (userType) {
      case premium: return null;    // sınırsız
      case proPlus: return 324000;  // 90 saat
      case pro:     return 108000;  // 30 saat
      default:      return 54000;   // 15 saat (standard)
    }
  }

  /// Tier'ın izin verdiği maksimum yayın kalitesi.
  static String maxStreamQuality(String userType) {
    if (isProPlusOrAbove(userType)) return '1080p';
    if (isPro(userType)) return '720p';
    return '540p';
  }

  /// Kullanılabilir kalite seçenekleri (kilitli olmayanlar dahil — tüm olası değerler).
  static const List<String> allStreamQualities = ['540p', '720p', '1080p'];

  /// Verilen kalite değeri bu tier için kilitli mi?
  static bool isQualityLocked(String userType, String quality) {
    switch (quality) {
      case '1080p': return !isProPlusOrAbove(userType);
      case '720p':  return !isPaidTier(userType);
      default:      return false;
    }
  }

  /// Kilitli kalite için gereken minimum tier adı.
  static String requiredTierForQuality(String quality) {
    switch (quality) {
      case '1080p': return proPlus;
      case '720p':  return pro;
      default:      return standard;
    }
  }

  /// Yayın geliri komisyon oranı — host'a kalan pay (tam sayı yüzde).
  /// Backend: tier.py COMMISSION_RATE ile senkron tutulmalı.
  static int commissionPercent(String userType) {
    switch (userType) {
      case premium: return 100;
      case proPlus: return 90;
      case pro:     return 75;
      default:      return 50;
    }
  }
}
