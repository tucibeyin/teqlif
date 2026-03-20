import 'package:flutter/services.dart';

/// Sayıyı Türk formatında gösterir: 1000000 → "1.000.000 ₺"
String fmtPrice(num? price) {
  if (price == null) return '';
  final s = price.toInt().toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return '${buf.toString()} ₺';
}

/// Binlik ayracı olarak nokta kullanan giriş formatlayıcısı.
/// Kullanıcı "1000000" yazarken "1.000.000" olarak gösterir.
/// Ham sayıyı almak için: text.replaceAll('.', '')
class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) return newValue.copyWith(text: '');
    final formatted = digits.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (m) => '${m[1]}.',
    );
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
