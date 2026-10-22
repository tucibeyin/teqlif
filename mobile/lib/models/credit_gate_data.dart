/// Kredi kapısı veri modeli.
///
/// [CreditFeature] — Python tarafıyla birebir eşleşen enum; backend'deki
/// `CreditFeature` str-Enum değerleri ile aynı string değerlere sahip.
///
/// [CreditGateData] — Herhangi bir kredili özellik için gerekli tüm
/// bilgiyi taşıyan immutable değer nesnesi.
library;

enum CreditFeature {
  blast,
  boost,
  aiDesc,
  reactivation;

  /// Backend'deki string karşılığı.
  String get apiKey => switch (this) {
        CreditFeature.blast => 'blast',
        CreditFeature.boost => 'boost',
        CreditFeature.aiDesc => 'ai_desc',
        CreditFeature.reactivation => 'reactivation',
      };

  /// ARB key prefix'i — `creditGate{prefix}Title` gibi key'ler türetilir.
  String get l10nPrefix => switch (this) {
        CreditFeature.blast => 'Blast',
        CreditFeature.boost => 'Boost',
        CreditFeature.aiDesc => 'AiDesc',
        CreditFeature.reactivation => 'Reactivation',
      };

  /// Backend API'sinin `cost_teqlik` alanı eksik gelirse kullanılan güvenli fallback.
  /// Gerçek değerler credit_service.py'deki `_COSTS` tablosundan gelir.
  int get fallbackCostTeqlik => switch (this) {
        CreditFeature.blast => 10,
        CreditFeature.boost => 50,
        CreditFeature.aiDesc => 5,
        CreditFeature.reactivation => 10,
      };
}

/// Onay akışının sonucu — tüm feature'larda aynı dönüş tipi.
class CreditGateResult {
  final bool success;

  /// l10n key — başarısız olduğunda gösterilecek hata metni.
  final String? errorKey;

  /// Feature'a özgü ek veri:
  /// - boost  → {'id': int, 'is_free': bool}
  /// - blast  → {'cooldown': bool, 'seconds_remaining': int} veya boş map
  /// - reactivation → boş map
  /// - aiDesc → boş map (deduction server-side, generate sonrası)
  final Map<String, dynamic>? payload;

  const CreditGateResult._({
    required this.success,
    this.errorKey,
    this.payload,
  });

  factory CreditGateResult.success([Map<String, dynamic>? payload]) =>
      CreditGateResult._(success: true, payload: payload);

  factory CreditGateResult.failure(String errorKey) =>
      CreditGateResult._(success: false, errorKey: errorKey);

  factory CreditGateResult.cancelled() =>
      const CreditGateResult._(success: false);

  /// Cooldown veya detail gibi payload içeren başarısız sonuç.
  factory CreditGateResult.failureWithPayload(Map<String, dynamic> payload) =>
      CreditGateResult._(success: false, payload: payload);
}

class CreditGateData {
  final CreditFeature feature;

  /// Kullanıcı tipi: 'pro' | 'standard'
  final String userType;

  /// Bu dönemde kalan ücretsiz hak sayısı.
  final int freeRemaining;

  /// Bu dönem toplam ücretsiz limit.
  final int freeLimitTotal;

  /// Ücretli kullanım başına TEQlik maliyeti.
  final int costTeqlik;

  /// Kullanıcının mevcut TEQlik bakiyesi.
  final int teqlikBalance;

  // Blast-özgü alanlar — diğer feature'larda 0.
  final int audienceSize;
  final int perOpCap;

  // Reactivation-özgü — 30 gün penceresi ücretsiz.
  final bool withinWindow;

  const CreditGateData({
    required this.feature,
    required this.userType,
    required this.freeRemaining,
    required this.freeLimitTotal,
    required this.costTeqlik,
    required this.teqlikBalance,
    this.audienceSize = 0,
    this.perOpCap = 0,
    this.withinWindow = false,
  });

  /// Kullanım ücretsiz mi?
  bool get isFree => withinWindow || freeRemaining > 0;

  /// Ücretli işlem için bakiye yeterli mi?
  bool get canAfford => isFree || teqlikBalance >= costTeqlik;

  bool get isStandard => userType != 'pro';
}
