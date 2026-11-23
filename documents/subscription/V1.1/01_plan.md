# Abonelik V1.1 — 4 Tier Geçiş Planı

**Durum:** Planlama / Tasarım  
**Son güncelleme:** Kasım 2026  
**İlgili ADR:** §13 (Development Workflow), §40 (CreditGate), `credit_service.py`

Bu döküman genişletilebilir yapıdadır. Her bölüm bağımsız tamamlanabilir.  
Tamamlananlar `✅`, devam edenler `🔄`, henüz başlanmayanlar `📋` ile işaretlenir.

---

## İçindekiler

1. [Karar Özeti](#1-karar-özeti)
2. [Tier Tablosu](#2-tier-tablosu)
3. [Backend Değişiklikleri](#3-backend-değişiklikleri)
4. [Flutter / Mobile Değişiklikleri](#4-flutter--mobile-değişiklikleri)
5. [ARB / OTA Lokalizasyon](#5-arb--ota-lokalizasyon)
6. [Ekran Değişiklikleri](#6-ekran-değişiklikleri)
7. [Fiyatlandırma](#7-fiyatlandırma) *(TODO)*
8. [UI / UX Tasarımı](#8-ui--ux-tasarımı) *(TODO)*
9. [App Store / Google Play](#9-app-store--google-play) *(TODO)*

---

## 1. Karar Özeti

### Neden 4 Tier?

V1.0'da yalnızca `standard` ve `pro` vardı; 540p / 720p kalite farkı tek başına yeterli
dönüşüm motivasyonu sağlamıyordu. 1080p ve sınırsız yayın saati iki yeni tier'ı
meşrulaştırıyor:

- **Normal → PRO:** Yayın süresi (15h → 45h) ve kalite (540p → 720p) + tüm PRO araçlar
- **PRO → PRO+:** 1080p kalite + yüksek kredi limitleri — ciddi satıcı segmenti
- **PRO+ → PREMIUM:** Sınırsız yayın saati — profesyonel / kurumsal satıcılar

### Yayın Saati Mantığı

Normal kullanıcı için 15 saat/ay ≈ günde ~30 dakika. Açık artırma yapan aktif satıcı
günde 1+ saat ihtiyaç duyar → doğal PRO dönüşüm baskısı. Kayıt izleme süresi (24 saat)
MinIO ILM kısıtı nedeniyle tüm ücretli tierlarda aynı kalır.

---

## 2. Tier Tablosu

| Özellik | Normal | PRO | PRO+ | PREMIUM |
|---------|--------|-----|------|---------|
| **Yayın kalitesi** | 540p | 720p | 1080p | 1080p |
| **Yayın süresi/ay** | 15 saat | 45 saat | 100 saat | Sınırsız |
| **Kayıt izleme** | — | 24 saat | 24 saat | 24 saat |
| **PRO Araçlara erişim** | — | ✓ | ✓ | ✓ |
| | | | | |
| **Blast (ücretsiz/ay)** | 3 | 10 | 20 | 30 |
| **Blast per-op kişi cap** | 5 | 15 | 30 | 50 |
| **Boost (ücretsiz/ay)** | 0 | 3 | 6 | 10 |
| **AI Açıklama (ücretsiz/ay)** | 0 | 6 | 15 | 30 |
| **Reaktivasyon (ücretsiz/ay)** | 0 | 3 | 6 | 10 |
| | | | | |
| **Blast ek kullanım** | 10 teqlik | 10 teqlik | 10 teqlik | 10 teqlik |
| **Boost ek kullanım** | 50 teqlik | 50 teqlik | 50 teqlik | 50 teqlik |
| **AI Açıklama ek kullanım** | 5 teqlik | 5 teqlik | 5 teqlik | 5 teqlik |
| **Reaktivasyon ek kullanım** | 10 teqlik | 10 teqlik | 10 teqlik | 10 teqlik |

> **Not:** Teqlik maliyetleri tüm tierlarda aynı — sadece ücretsiz hak miktarı değişiyor.

---

## 3. Backend Değişiklikleri

### 3.1 `credit_service.py` 📋

**Dosya:** `backend/app/services/credit_service.py`

**`_PREMIUM_TYPES`** genişletilecek:
```python
# Şimdiki:
_PREMIUM_TYPES: frozenset[str] = frozenset({"pro"})

# Yeni:
_PREMIUM_TYPES: frozenset[str] = frozenset({"pro", "pro_plus", "premium"})
```

**`_FEATURES`** dict'e 2 yeni key eklenecek (`free_pro_plus`, `free_premium`):
```python
CreditFeature.BLAST: {
    "key_prefix":          "blast_credits",
    "free_standard":       3,
    "free_pro":            10,   # 6 → 10
    "free_pro_plus":       20,
    "free_premium":        30,
    "cost_teqlik":         10,
    "per_op_cap_standard": 5,
    "per_op_cap_pro":      15,   # 10 → 15
    "per_op_cap_pro_plus": 30,
    "per_op_cap_premium":  50,
},
# ... diğer feature'lar benzer şekilde
```

**`free_limit()` ve `per_op_cap()`** tier-aware dict lookup'a dönüştürülecek:
```python
_TIER_ORDER = ["standard", "pro", "pro_plus", "premium"]

def free_limit(feature: CreditFeature, user_type: str) -> int:
    cfg = _FEATURES[feature]
    key = f"free_{user_type}" if f"free_{user_type}" in cfg else "free_standard"
    return cfg.get(key, cfg["free_standard"])
```

### 3.2 Yayın Saati Takibi 📋

Mevcut `CreditFeature` mekanizması kredi sayımı için yazılmış; yayın saati **dakika cinsinden**
ayrı bir Redis anahtarında takip edilecek. Yeni `CreditFeature.STREAM_MINUTES` eklenmeyecek —
bunun yerine `stream_service.py` içinde ayrı fonksiyon:

```python
# Redis key: stream_minutes:{user_id}:{YYYY-MM}
# Yayın başlarken: dakika rezervasyonu yok, biterken toplam süre eklenir
# Limit kontrolü: yayın başlatma endpoint'inde (routers/streams.py)
```

**Limitler (dakika):**
- Normal: 900 dk (15 saat)
- PRO: 2700 dk (45 saat)
- PRO+: 6000 dk (100 saat)
- PREMIUM: `None` (sınırsız)

### 3.3 `routers/streams.py` 📋

Yayın başlatma endpoint'inde iki kontrol eklenecek:

1. **Kalite kontrolü:** `user_type` → izin verilen maksimum çözünürlük
2. **Süre kontrolü:** Aylık kalan dakika kontrolü (yayın bitişinde sayaç güncelleme)

Mevcut `line 317: if current_user.user_type != 'pro'` → tier-aware fonksiyona taşınacak.

### 3.4 DB Migration 📋

`users.user_type` alanı mevcut `String(20)` — yeni değerler sığar, tip değişikliği gerekmez.
Ancak eski `CHECK` kısıtı varsa güncellenecek:

```sql
-- Alembic migration (multi-statement yasak — ayrı revision'lar)
-- Revision 1: CHECK kısıtını kaldır
-- Revision 2: Yeni CHECK kısıtı ekle
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_user_type_check;
ALTER TABLE users ADD CONSTRAINT users_user_type_check
  CHECK (user_type IN ('standard', 'pro', 'pro_plus', 'premium'));
```

> **ADR Kuralı:** Multi-statement revision yasak; her ALTER ayrı revision.

### 3.5 `routers/auth.py` ve Diğerleri 📋

`user_type == 'pro'` karşılaştırması tüm backend'de taranacak; tier-aware helper'a taşınacak:

```python
def is_paid_tier(user_type: str) -> bool:
    return user_type in _PREMIUM_TYPES

def tier_level(user_type: str) -> int:
    return {"standard": 0, "pro": 1, "pro_plus": 2, "premium": 3}.get(user_type, 0)
```

---

## 4. Flutter / Mobile Değişiklikleri

### 4.1 `models/user.dart` 📋

**Şimdiki durum:**
```dart
bool get isPremium => userType == 'pro';
bool get isPro => userType == 'pro';
```

**Yeni:**
```dart
bool get isPaidTier => ['pro', 'pro_plus', 'premium'].contains(userType);
bool get isPro      => userType == 'pro';
bool get isProPlus  => userType == 'pro_plus';
bool get isPremium  => userType == 'premium';

int get tierLevel => const {'standard': 0, 'pro': 1, 'pro_plus': 2, 'premium': 3}[userType] ?? 0;

String get tierDisplayName => const {
  'standard': 'Normal',
  'pro':      'PRO',
  'pro_plus': 'PRO+',
  'premium':  'PREMIUM',
}[userType] ?? 'Normal';
```

> **Dikkat:** Mevcut `isPremium` bool'u `isPaidTier`'a dönüştürülüyor — tüm kullanım yerlerini
> taramak gerekiyor (grep: `isPremium`).

### 4.2 `pro_hub_screen.dart` ve `pro_hub_view_model.dart` 📋

`isPremium: bool` parametresi → `userType: String` veya `tierLevel: int`'e dönüştürülecek.
`_ProStatusCard` widgeti tier adını ve rengini dinamik gösterecek:

| Tier | Renk | Rozet |
|------|------|-------|
| PRO | Mevcut PRO rengi | PRO |
| PRO+ | Farklılaştırılacak (TODO §8) | PRO+ |
| PREMIUM | Premium renk (TODO §8) | ✦ PREMIUM |

### 4.3 `pro_subscription_view_model.dart` 📋

Şu an yalnızca PRO satın alma akışı mevcut. 4 tier için plan seçimi UI'ı eklenecek.
(Detay: §8 UI/UX)

### 4.4 Stream Kalite Seçimi 📋

`host_stream_screen.dart`'ta yayın başlatma: kullanıcının tier'ına göre izin verilen
maksimum kalite sunulacak. Üst tier kalite seçenekleri kilitli gösterilip tier upgrade
yönlendirmesi yapılacak.

### 4.5 `credit_gate_view_model.dart` 📋

`CreditGateData` modeli tier bazlı limit bilgisini API'den alıyor — backend değişikliği
sonrası Flutter tarafı otomatik doğru limitleri gösterir. Model güncellemesi gerekmez,
API response değişir.

---

## 5. ARB / OTA Lokalizasyon

### 5.1 Yeni Anahtarlar 📋

**Dosyalar:** `documents/language/app_tr.arb` ve 4 dil daha (en, de, ru, ar)

Eklenecek anahtar örnekleri:
```json
"tierPro":           "PRO",
"tierProPlus":       "PRO+",
"tierPremium":       "PREMIUM",
"tierNormal":        "Normal",
"streamHoursLeft":   "Bu ay {hours} saatiniz kaldı",
"streamHoursUsed":   "{used} / {total} saat kullanıldı",
"streamLimitReached":"Aylık yayın limitine ulaştınız",
"upgradeToPro":      "PRO'ya Geç",
"upgradeToProPlus":  "PRO+'ya Geç",
"upgradeToPremium":  "PREMIUM'a Geç",
"proHubStreamHours": "Yayın Saati",
"proHubBlastCredits":"Kitle Bildirimi",
"proHubBoostCredits":"Öne Çıkarma",
"proHubAiCredits":   "AI Açıklama",
"proHubReactCredits":"Reaktivasyon"
```

> **Workflow:** ARB → `git push` → VPS'te `git pull` → `sync_main.py` (ADR §1).
> SQL'e doğrudan yazılmaz.

### 5.2 Mevcut Anahtarlar Güncellenecek 📋

`"pro": "PRO"` anahtarı tier adı olarak değil özellik adı olarak kullanılıyorsa
bağlamına göre ayrıştırılacak.

---

## 6. Ekran Değişiklikleri

### 6.1 PRO Araçlar (`pro_hub_screen.dart`) 📋

- Tier rozeti: Normal → zayıf CTA, PRO/PRO+/PREMIUM → kendi tier bilgisi + yenileme tarihi
- Yayın saati progress bar: `{kullanılan} / {toplam} saat` (sınırsız için farklı UI)
- Kredi kartları: Blast / Boost / AI / Reaktivasyon — ücretsiz hak + kullanılan gösterimi
- Upgrade CTA: kullanıcının bir üst tier'ına yönlendirme (PREMIUM zaten en üst)

### 6.2 Profilim (`profile_screen.dart`) 📋

- Tier rozeti profil başlığına eklenecek (PRO / PRO+ / PREMIUM badge)
- Normal kullanıcıda PRO'ya geç CTA'sı (mevcut varsa güncelleme)

### 6.3 Ayarlar 📋

- Abonelik bölümü: mevcut tier, yenileme tarihi, tier değiştir linki
- (Detay: §8 UI/UX, §9 App Store)

### 6.4 teqlik Cüzdanım (`wallet_repository.dart` → screen) 📋

- Kredi özeti: hangi tier'da olduğu, kalan ücretsiz haklar
- Yayın saati özeti: Cüzdan ekranında da görünebilir (tartışılacak)

### 6.5 Yayın Başlatma (`host_stream_screen.dart`) 📋

- Kalite seçici: tier'a göre izin verilen max kalite
- Aylık kalan süre uyarısı: `< 2 saat kaldı` uyarısı (soft warning)
- Limit dolunca yayın başlatma engeli + upgrade yönlendirme

### 6.6 Abonelik Seçim Ekranı (Yeni veya Mevcut Güncelleme) 📋

4 tier'ı yan yana veya dikey liste olarak gösteren plan seçim UI'ı.
(Detay: §8 UI/UX, §9 App Store fiyatlandırması)

---

## 7. Fiyatlandırma

📋 **Henüz belirlenmedi.**

Ele alınacak konular:
- Türkiye App Store / Google Play fiyat kademeleri
- Aylık vs yıllık abonelik (yıllık indirim oranı)
- PRO, PRO+, PREMIUM TL fiyatları
- Fiyat / özellik dengesi rakip analizi (Trendyol Live, Instagram Shop vb.)
- Öğrenci / lansman dönemi indirim politikası
- Mevcut PRO aboneleri geçiş senaryosu (grandfathering)

---

## 8. UI / UX Tasarımı

📋 **Henüz tasarlanmadı.**

Ele alınacak konular:
- Tier renk paleti ve rozet tasarımı (PRO / PRO+ / PREMIUM görsel dili)
- Plan seçim ekranı layout (karşılaştırma tablosu vs kart slider)
- Upgrade CTA yerleşimleri (ne zaman, nerede gösterilecek)
- Stream saati progress bar tasarımı
- Kilitli özellik UI pattern'ı (kilit ikonu + tier adı)
- Downgrade uyarı akışı

---

## 9. App Store / Google Play

📋 **Henüz planlanmadı.**

Ele alınacak konular:
- In-app purchase (IAP) entegrasyonu — mevcut ödeme sistemi vs platform native
- App Store Connect / Google Play Console ürün tanımlamaları
- Fatura ve abonelik yönetimi (iptal, iade, tier değişimi)
- Platform komisyonu (%15–30) fiyatlandırmaya etkisi
- Türkiye'de App Store fiyat listesi kısıtları
- Abonelik restore akışı (cihaz değişimi senaryosu)
