import 'package:flutter/services.dart';

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
