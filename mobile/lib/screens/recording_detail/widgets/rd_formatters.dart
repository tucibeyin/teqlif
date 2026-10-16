import '../../../utils/number_formatter.dart';

String rdLocale(String lang) {
  const map = {
    'tr': 'tr_TR',
    'en': 'en_US',
    'ar': 'ar_SA',
    'ru': 'ru_RU',
    'de': 'de_DE',
  };
  return map[lang] ?? 'tr_TR';
}

/// ₺1.234,56  biçiminde fiyat
String rdPrice(num amount, String lang) =>
    '₺${TeqNumberFormatter.format(amount, locale: rdLocale(lang))}';

/// 1.234 teqliq
String rdTeqliq(num amount, String lang) =>
    '${TeqNumberFormatter.format(amount, locale: rdLocale(lang))} teqliq';
