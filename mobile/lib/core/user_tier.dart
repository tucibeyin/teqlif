import 'package:flutter/material.dart';

/// Kullanıcı tier sabitleri ve yardımcıları — Flutter karşılığı: backend/tier.py
///
/// TEK KAYNAK: Tüm tier mantığı buradan okunur.
/// Hiçbir ekran/widget literal tier değeri içermemelidir.
abstract class UserTier {
  static const standard = 'standard';
  static const tier1    = 'tier1';   // PRO      (Temel üyelik)
  static const tier2    = 'tier2';   // PRO+     (İleri üyelik)
  static const tier3    = 'tier3';   // PREMIUM  (Premium üyelik)
  static const tier4    = 'tier4';   // PREMIUM+ (Sınırsız üyelik)

  /// Aktif üyeliği (tier1–tier4) olan kullanıcı ise true döner.
  static bool hasSubscription(String userType) => userType != standard;

  /// Yalnızca tier1 ise true döner.
  static bool isTier1(String userType) => userType == tier1;

  /// tier2 veya üstü ise true döner.
  static bool isTier2OrAbove(String userType) =>
      userType == tier2 || userType == tier3 || userType == tier4;

  /// tier3 veya üstü ise true döner.
  static bool isTier3OrAbove(String userType) =>
      userType == tier3 || userType == tier4;

  /// Yalnızca tier3 ise true döner.
  static bool isTier3(String userType) => userType == tier3;

  /// Yalnızca tier4 ise true döner.
  static bool isTier4(String userType) => userType == tier4;

  /// Aylık yayın süresi sınırı (dakika). null = sınırsız (tier4).
  /// Backend: tier.py STREAM_LIMIT_MINUTES ile senkron tutulmalı.
  static int? streamLimitMinutes(String userType) {
    switch (userType) {
      case tier4: return null;    // sınırsız
      case tier3: return 21600;   // 360 saat
      case tier2: return 10800;   // 180 saat
      case tier1: return 5400;    // 90 saat
      default:    return 1800;    // 30 saat (standard)
    }
  }

  /// Tier'ın izin verdiği maksimum yayın kalitesi.
  static String maxStreamQuality(String userType) {
    if (isTier3OrAbove(userType)) return '1080p';
    if (hasSubscription(userType)) return '720p';
    return '540p';
  }

  /// Kullanılabilir kalite seçenekleri (kilitli olmayanlar dahil — tüm olası değerler).
  static const List<String> allStreamQualities = ['540p', '720p', '1080p'];

  /// Verilen kalite değeri bu tier için kilitli mi?
  static bool isQualityLocked(String userType, String quality) {
    switch (quality) {
      case '1080p': return !isTier3OrAbove(userType);
      case '720p':  return !hasSubscription(userType);
      default:      return false;
    }
  }

  /// Kilitli kalite için gereken minimum tier.
  static String requiredTierForQuality(String quality) {
    switch (quality) {
      case '1080p': return tier3;
      case '720p':  return tier1;
      default:      return standard;
    }
  }

  /// Tier sıralaması (0=standard … 4=tier4).
  static int tierLevel(String userType) {
    switch (userType) {
      case tier4: return 4;
      case tier3: return 3;
      case tier2: return 2;
      case tier1: return 1;
      default:    return 0;
    }
  }

  /// Yayın geliri komisyon oranı — host'a kalan pay (tam sayı yüzde).
  /// Backend: tier.py COMMISSION_RATE ile senkron tutulmalı.
  static int commissionPercent(String userType) {
    switch (userType) {
      case tier4: return 100;
      case tier3: return 100;
      case tier2: return 90;
      case tier1: return 75;
      default:    return 50;
    }
  }

  /// Tier'a göre kral tacı renk gradyanı.
  /// PREMIUM / PREMIUM+ → teqlif cyan; PRO / PRO+ → altın sarı.
  static List<Color> crownGradient(String userType) {
    return isTier3OrAbove(userType)
        ? const [Color(0xFF0284C7), Color(0xFF38BDF8)]
        : const [Color(0xFFD97706), Color(0xFFFFD700)];
  }
}
