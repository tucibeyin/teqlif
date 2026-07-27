import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// KATEGORI_PLAN ve sistem genelindeki tüm sayısal alanların (Fiyat, KM, m², CC vb.)
/// aktif dil kurallarına ve mantıksal kararlara (Yıl, Kat hariç) göre formatlanmasını
/// ve dönüştürülmesini sağlayan merkezi servis.
class TeqNumberFormatter {
  // Kesinlikle binlik ayraç uygulanmayacak alan adları (Sıra, Yıl, Kat, Yaş, ID vb.)
  static const _kUnformattedKeys = <String>{
    'year',
    'model_year',
    'production_year',
    'building_age',
    'floor',
    'floor_count',
    'room_count',
    'id',
    'listing_id',
    'user_id',
    'phone',
    'postal_code',
    'zip_code',
  };

  /// Belirtilen alan anahtarının [key] binlik ayraçtan muaf (Sıra/Yıl/Kat) olup olmadığını kontrol eder.
  static bool isUnformattedKey(String? key) {
    if (key == null || key.trim().isEmpty) return false;
    final k = key.trim().toLowerCase();
    if (_kUnformattedKeys.contains(k)) return true;
    if (k.endsWith('_id') ||
        k.endsWith('_year') ||
        k.endsWith('_age') ||
        k.endsWith('_floor') ||
        k == 'id') {
      return true;
    }
    return false;
  }

  /// Herhangi bir değeri (sayı veya string) aktif dilin kuralına göre formatlar.
  /// Ör: 150000 -> "150.000" (TR) / "150,000" (EN)
  /// Kara listedeki anahtarlar (Ör: year=2023) ham haliyle döndürülür.
  static String format(
    dynamic value, {
    String? fieldKey,
    String? locale,
    String? unit,
  }) {
    if (value == null || value.toString().trim().isEmpty) return '';

    final rawStr = value.toString().trim();

    // 1. Kara liste kontrolü (Yıl, Kat, Yaş, ID vb.)
    if (fieldKey != null && isUnformattedKey(fieldKey)) {
      return unit != null && unit.isNotEmpty ? '$rawStr $unit' : rawStr;
    }

    // 2. Sayısal dönüşüm
    final numVal = parse(value);

    // Sayıya çevrilemiyorsa (ör: dropdown metni, "Benzin", "Otomatik", "3+1"), olduğu gibi döndür
    if (numVal == null) {
      return unit != null && unit.isNotEmpty ? '$rawStr $unit' : rawStr;
    }

    // 3. Formatlama
    final isDecimal = numVal is double && numVal.remainder(1) != 0;
    final pattern = isDecimal ? '#,##0.##' : '#,##0';
    final targetLocale = locale ?? Intl.defaultLocale ?? 'tr_TR';

    try {
      final formatter = NumberFormat(pattern, targetLocale);
      final formatted = formatter.format(numVal);
      return unit != null && unit.isNotEmpty ? '$formatted $unit' : formatted;
    } catch (_) {
      final fallbackStr = numVal.toString();
      return unit != null && unit.isNotEmpty ? '$fallbackStr $unit' : fallbackStr;
    }
  }

  /// String veya num olarak gelen formatlı veya formatsız verileri saf sayıya çevirir.
  /// Ör: "1.500.000" -> 1500000 | "12,5" -> 12.5 | "1,500.50" -> 1500.5
  static num? parse(dynamic input) {
    if (input == null) return null;
    if (input is num) return input;
    final text = input.toString().trim();
    if (text.isEmpty) return null;

    // Hem nokta hem virgül varsa (Ör: "1.500.000,50" veya "1,500,000.50")
    if (text.contains('.') && text.contains(',')) {
      final lastDot = text.lastIndexOf('.');
      final lastComma = text.lastIndexOf(',');
      if (lastComma > lastDot) {
        // Virgül ondalık ayracı (TR): 1.500.000,50 -> 1500000.50
        final cleaned = text.replaceAll('.', '').replaceAll(',', '.');
        return num.tryParse(cleaned);
      } else {
        // Nokta ondalık ayracı (EN): 1,500,000.50 -> 1500000.50
        final cleaned = text.replaceAll(',', '');
        return num.tryParse(cleaned);
      }
    }

    // Sadece virgül varsa (Ör: "1,500" veya "12,5")
    if (text.contains(',') && !text.contains('.')) {
      final parts = text.split(',');
      if (parts.last.length == 3 && parts.length > 1) {
        // Genelde binlik ayraç (EN: 1,500)
        return num.tryParse(text.replaceAll(',', ''));
      } else {
        // Ondalık ayraç (TR: 12,5 -> 12.5)
        return num.tryParse(text.replaceAll(',', '.'));
      }
    }

    // Sadece nokta varsa (Ör: "150.000" veya "12.5")
    if (text.contains('.') && !text.contains(',')) {
      final parts = text.split('.');
      if (parts.last.length == 3 && parts.length > 1) {
        // Genelde binlik ayraç (TR: 1.500.000)
        return num.tryParse(text.replaceAll('.', ''));
      } else {
        // Ondalık ayraç (EN: 12.5)
        return num.tryParse(text);
      }
    }

    // Düz rakam string (Ör: "150000")
    return num.tryParse(text);
  }
}

/// Form girdi alanlarında (TextField) kullanıcı veri girerken aktif dile ve mantıksal kurallara göre
/// anlık binlik ayraç biçimlendirmesi yapan evrensel TextInputFormatter.
class TeqNumericInputFormatter extends TextInputFormatter {
  final String? fieldKey;
  final String? locale;
  final bool allowDecimal;

  const TeqNumericInputFormatter({
    this.fieldKey,
    this.locale,
    this.allowDecimal = false,
  });

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue.copyWith(text: '');
    }

    // 1. Kara liste kontrolü: Yıl, Kat, Yaş, ID gibi sayılarda binlik ayraç KULLANMA
    if (TeqNumberFormatter.isUnformattedKey(fieldKey)) {
      final pattern = allowDecimal ? RegExp(r'[^0-9.,]') : RegExp(r'[^0-9]');
      final cleanText = newValue.text.replaceAll(pattern, '');
      return TextEditingValue(
        text: cleanText,
        selection: TextSelection.collapsed(offset: cleanText.length),
      );
    }

    // 2. Binlik ayraç formatlama (Fiyat, KM, m², CC, Çalışma Saati vb.)
    String textToFormat = newValue.text;
    if (!allowDecimal) {
      final digits = textToFormat.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.isEmpty) return newValue.copyWith(text: '');

      final numVal = int.tryParse(digits);
      if (numVal == null) return newValue;

      final targetLocale = locale ?? Intl.defaultLocale ?? 'tr_TR';
      final formatter = NumberFormat('#,##0', targetLocale);
      final formatted = formatter.format(numVal);
      return TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    } else {
      final cleaned = textToFormat.replaceAll(RegExp(r'[^0-9.,]'), '');
      if (cleaned.isEmpty) return newValue.copyWith(text: '');

      if (cleaned.endsWith('.') || cleaned.endsWith(',')) {
        return TextEditingValue(
          text: cleaned,
          selection: TextSelection.collapsed(offset: cleaned.length),
        );
      }

      final parts = cleaned.split(RegExp(r'[.,]'));
      final intPart = int.tryParse(parts[0]) ?? 0;
      final targetLocale = locale ?? Intl.defaultLocale ?? 'tr_TR';
      final formatter = NumberFormat('#,##0', targetLocale);
      String formatted = formatter.format(intPart);
      if (parts.length > 1) {
        formatted += '.${parts[1]}';
      }
      return TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
  }
}
