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
}
