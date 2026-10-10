/// Uygulamanın desteklediği diller — tek kaynak.
///
/// Yeni bir dil eklemek için sadece buraya bir satır ekle.
/// TeqLanguageSelector bu listeden otomatik olarak beslenir.
class AppLanguage {
  const AppLanguage({required this.code, required this.nativeName});

  /// BCP-47 dil kodu ('tr', 'en', 'de', …)
  final String code;

  /// Dilin kendi dilindeki adı — uygulama dilinden bağımsız, her zaman sabit.
  final String nativeName;
}

const kSupportedLanguages = [
  AppLanguage(code: 'tr', nativeName: 'Türkçe'),
  AppLanguage(code: 'en', nativeName: 'English'),
  AppLanguage(code: 'de', nativeName: 'Deutsch'),
  AppLanguage(code: 'ru', nativeName: 'Русский'),
  AppLanguage(code: 'ar', nativeName: 'العربية'),
];
