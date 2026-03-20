import 'package:flutter/material.dart';

/// Kullanıcı adını deterministik olarak bir renge çevirir.
/// Aynı username her zaman aynı rengi döndürür.
Color usernameColor(String username) {
  const _palette = [
    Color(0xFFF87171), // kırmızı
    Color(0xFFFB923C), // turuncu
    Color(0xFFFBBF24), // sarı
    Color(0xFFA3E635), // lime
    Color(0xFF4ADE80), // yeşil
    Color(0xFF2DD4BF), // teal
    Color(0xFF22D3EE), // cyan
    Color(0xFF38BDF8), // mavi
    Color(0xFF818CF8), // indigo
    Color(0xFFC084FC), // mor
    Color(0xFFF472B6), // pembe
    Color(0xFFFB7185), // gül
  ];

  int hash = 0;
  for (final c in username.codeUnits) {
    hash = (hash * 31 + c) & 0x7FFFFFFF;
  }
  return _palette[hash % _palette.length];
}
