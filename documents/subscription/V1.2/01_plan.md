# Abonelik V1.2 — PREMIUM+ (5. Tier) + Fiyat Revizyonu + Araç Genişletme

**Durum:** Planlama / Implementasyon
**Son güncelleme:** Kasım 2026
**Önceki versiyon:** `documents/subscription/V1.1/01_plan.md`
**İlgili ADR:** §13 (Development Workflow), §10 (Tier Rename)

> Bu döküman V1.1'e göre **delta**'yı içerir. V1.1 standartları (§0 implementasyon
> standartları, clean architecture, Alembic kuralları, ARB workflow vb.) aynen geçerlidir.

---

## İçindekiler

1. [Değişiklik Özeti](#1-değişiklik-özeti)
2. [Tier Tablosu — V1.2](#2-tier-tablosu--v12)
3. [Fiyatlandırma — V1.2](#3-fiyatlandırma--v12)
4. [Yayın Saati Limitleri — V1.2](#4-yayın-saati-limitleri--v12)
5. [Araç Erişim Matrisi — V1.2](#5-araç-erişim-matrisi--v12)
6. [Renk / Marka](#6-renk--marka)
7. [Backend Değişiklikleri](#7-backend-değişiklikleri)
8. [Flutter / Mobile Değişiklikleri](#8-flutter--mobile-değişiklikleri)
9. [ARB / OTA Lokalizasyon](#9-arb--ota-lokalizasyon)
10. [App Store / Google Play](#10-app-store--google-play)
11. [Mevcut Kullanıcı Geçişi](#11-mevcut-kullanıcı-geçişi)
12. [Implementasyon Sırası](#12-implementasyon-sırası)

---

## 1. Değişiklik Özeti

### V1.1 → V1.2 Delta

| Konu | V1.1 | V1.2 |
|------|------|------|
| Tier sayısı | 4 (standard / tier1 / tier2 / tier3) | 5 (+ tier4 / PREMIUM+) |
| PRO aylık fiyat | 299,99 ₺ | **799,99 ₺** |
| PRO+ aylık fiyat | 699,99 ₺ | **1.499,99 ₺** |
| PREMIUM aylık fiyat | 1.299,99 ₺ | **2.899,99 ₺** |
| PREMIUM+ aylık fiyat | — | **5.999,99 ₺** |
| Standard yayın saati | 15 saat | **30 saat** |
| PRO yayın saati | 30 saat | **90 saat** |
| PRO+ yayın saati | 90 saat | **180 saat** |
| PREMIUM yayın saati | Sınırsız | **360 saat** |
| PREMIUM+ yayın saati | — | **Sınırsız** |
| PRO+ araç erişimi | Sadece yayın araçları | **+ Satış Analizi, İlan Analizi** |
| Yayın muhasebesi | Saniye | **Dakika (ceil)** ✅ Tamamlandı |

### Neden fiyat revizyonu?

Teqlif, basit bir yayın uygulaması değil; VoIP, görüntülü görüşme, canlı yayın
(açık artırma + direkt satış paneli), satış takip, alışveriş takip, mesajlaşma,
5 dil ve teqlif Araçları içeren bir e-ticaret altyapısıdır.

Karşılaştırma:
- Shopify Plus: ~$2.000/ay ≈ ₺65.000+
- Shopify Basic: ~$39/ay ≈ ₺1.300+
- Teqlif PRO ₺799/ay: **sabit ücret, komisyon yok**

Ayda ₺50.000 ciro yapan satıcı için ₺799/ay = %1,6 — değer açık.

### Neden PREMIUM+?

PREMIUM (360 saat/ay) günde 12 saat yayın yapan kullanıcıyı karşılar.
PREMIUM+'ın hedef kitlesi: ajanslar, günde 12+ saat yayıncılar, ciddi profesyonel satıcılar.
Sınırsız yayın garantisi + tüm araçlar = "endişe yok" premium konumu.

---

## 2. Tier Tablosu — V1.2

| Özellik | Standard | PRO (tier1) | PRO+ (tier2) | PREMIUM (tier3) | PREMIUM+ (tier4) |
|---------|----------|-------------|--------------|-----------------|------------------|
| **Yayın kalitesi** | 540p | 720p | 1080p | 1080p | 1080p |
| **Yayın süresi/ay** | 30 saat | 90 saat | 180 saat | 360 saat | **Sınırsız** |
| **Yayın gelir payı** | %50 | %75 | %90 | %100 | %100 |
| | | | | | |
| **Blast (ücretsiz/ay)** | 3 | 10 | 20 | 30 | 30 |
| **Blast per-op kişi cap** | 5 | 15 | 30 | 50 | 50 |
| **Boost (ücretsiz/ay)** | 0 | 3 | 6 | 10 | 10 |
| **AI Açıklama (ücretsiz/ay)** | 0 | 6 | 15 | 30 | 30 |
| **Reaktivasyon (ücretsiz/ay)** | 0 | 3 | 6 | 10 | 10 |
| | | | | | |
| **Satış Analizi** | — | — | ✓ | ✓ | ✓ |
| **İlan Analizi** | — | — | ✓ | ✓ | ✓ |
| **Canlı Yayınlarım** | — | — | — | ✓ | ✓ |
| **Diğer teqlif Araçları** | — | ✓ | ✓ | ✓ | ✓ |
| | | | | | |
| **Renk** | — | Altın | Altın | Cyan | Cyan |

> **Not:** PREMIUM+ kredi limitleri PREMIUM ile aynı — fark sadece yayın saatinde.
> Teqlik maliyetleri tüm tierlarda aynı; yalnızca ücretsiz hak miktarı değişiyor.

---

## 3. Fiyatlandırma — V1.2

### 3.1 Aylık Taban Fiyatlar

| Tier | Aylık | 3 Aylık | 6 Aylık | Yıllık |
|------|-------|---------|---------|--------|
| **PRO** | ₺799,99 | ₺2.159,99 | ₺3.999,99 | ₺7.199,99 |
| **PRO+** | ₺1.499,99 | ₺3.999,99 | ₺7.499,99 | ₺13.499,99 |
| **PREMIUM** | ₺2.899,99 | ₺7.799,99 | ₺14.999,99 | ₺26.999,99 |
| **PREMIUM+** | ₺5.999,99 | ₺15.999,99 | ₺29.999,99 | ₺53.999,99 |

**İndirim oranları:** 3 ay ≈ %10 | 6 ay ≈ %17 | 12 ay ≈ %25

**Tier arası çarpanlar:**
- Standard → PRO: ücretli geçiş
- PRO → PRO+: 1,88x
- PRO+ → PREMIUM: 1,93x
- PREMIUM → PREMIUM+: 2,07x

### 3.2 Yayın Saati Değer Analizi

| Tier | Fiyat/ay | Yayın Saati | Saat Başı Maliyet |
|------|----------|-------------|-------------------|
| Standard | — | 30 saat | — |
| PRO | ₺799,99 | 90 saat | ~₺8,89/saat |
| PRO+ | ₺1.499,99 | 180 saat | ~₺8,33/saat |
| PREMIUM | ₺2.899,99 | 360 saat | ~₺8,06/saat |
| PREMIUM+ | ₺5.999,99 | Sınırsız | — |

> Üst tier saat başı maliyet hafif düşüyor — upgrade'i finansal olarak meşrulaştırır.

### 3.3 App Store / Google Play Ürün ID'leri

**Mevcut (güncellenen fiyatlar):**
```
teqlif_pro_1m      → ₺799,99     (eski: ₺399,99)
teqlif_pro_3m      → ₺2.159,99   (eski: ₺1.079,99)
teqlif_pro_6m      → ₺3.999,99   (eski: ₺1.999,99)
teqlif_pro_12m     → ₺7.199,99   (eski: ₺3.599,99)

teqlif_pro_plus_1m   → ₺1.499,99   (eski: ₺899,99)
teqlif_pro_plus_3m   → ₺3.999,99   (eski: ₺2.399,99)
teqlif_pro_plus_6m   → ₺7.499,99   (eski: ₺4.499,99)
teqlif_pro_plus_12m  → ₺13.499,99  (eski: ₺7.999,99)

teqlif_premium_1m    → ₺2.899,99   (eski: ₺1.799,99)
teqlif_premium_3m    → ₺7.799,99   (eski: ₺4.599,99)
teqlif_premium_6m    → ₺14.999,99  (eski: ₺8.999,99)
teqlif_premium_12m   → ₺26.999,99  (eski: ₺15.999,99)
```

**Yeni oluşturulacak (PREMIUM+):**
```
teqlif_premium_plus_1m   → ₺5.999,99
teqlif_premium_plus_3m   → ₺15.999,99
teqlif_premium_plus_6m   → ₺29.999,99
teqlif_premium_plus_12m  → ₺53.999,99
```

> **Önemli:** App Store Connect ve Google Play Console'da ürün oluşturma/fiyat
> güncelleme geliştirici tarafından yapılır. Claude kod değişikliklerini yapar.

### 3.4 Velocity Limit Güncellemesi

`verify_purchase_command.py` içindeki `_PRODUCT_TRY_PRICES` tablosu tüm yeni
fiyatlarla güncellenmeli (IAP velocity limit için fallback değerler).

---

## 4. Yayın Saati Limitleri — V1.2

### 4.1 Yeni Limitler (dakika)

```python
STREAM_LIMIT_MINUTES: dict[str, int | None] = {
    TIER_STANDARD: 1_800,   # 30 saat
    TIER_1:        5_400,   # 90 saat
    TIER_2:        10_800,  # 180 saat
    TIER_3:        21_600,  # 360 saat
    TIER_4:        None,    # sınırsız (PREMIUM+)
}
```

### 4.2 FOMO Tasarımı

| Kullanıcı tipi | Aylık ihtiyaç | Uygun tier | Upgrade baskısı |
|----------------|---------------|------------|-----------------|
| Casual satıcı | 5–15 saat | Standard (30h) | PRO CTA |
| Düzenli satıcı (hafta 2× × 2 saat) | ~16 saat | Standard | Rahat |
| Aktif satıcı (hafta 3× × 3 saat) | ~36 saat | Standard sınırı aşılıyor | PRO CTA |
| Ciddi yayıncı (gün 3 saat) | ~90 saat | PRO+ dolumu | PREMIUM CTA |
| Profesyonel (gün 6 saat) | ~180 saat | PRO+ sınırı aşılıyor | PREMIUM CTA |
| Ajans / günlük yayıncı (gün 12+ saat) | 360+ saat | PREMIUM+ | — |

> Standard kullanıcı günde bir kere uğrar (~1 saat), platforma alışır. PRO'ya
> geçince yayın saati 3× artıyor — net değer hissi. Bu FOMO kasıtlı.

### 4.3 Mevcut Kod Durumu

Yayın muhasebesi **saniyeden dakikaya (ceil)** geçişi önceki session'da tamamlandı:
- `monthly_stream_seconds_used` → `monthly_stream_minutes_used` ✅
- Alembic migration `zzzzzzzk_stream_minutes` çalıştırıldı ✅
- Backend + Flutter güncellendi ✅

**V1.2'de değişecek:** Sadece limit değerleri (yukarıdaki tablo).

---

## 5. Araç Erişim Matrisi — V1.2

### 5.1 Mevcut (V1.1) vs Yeni (V1.2)

| Araç | V1.1 | V1.2 |
|------|------|------|
| Blast, Boost, AI Açıklama, Reaktivasyon | tier1+ | tier1+ |
| **Satış Analizi** | tier3 | **tier2+** |
| **İlan Analizi** | tier3 | **tier2+** |
| Canlı Yayınlarım | tier3 | tier3+ |
| Diğer araçlar | tier3 | tier3+ |

### 5.2 Mantık

PRO+ (tier2) kullanıcısı yüksek yayın saati + 1080p kalite + yüksek kredi hakkı alıyor.
"Satış ve İlan Analizi" araçları veri odaklı satıcı için somut değer katar —
PRO+'ya geçişi meşrulaştırır. "Canlı Yayınlarım" (kayıt arşivi) PREMIUM'a özel kalır.

### 5.3 Backend Değişikliği

`isTier3()` kontrolü olan araç endpoint'leri `isTier2OrAbove()` yapılacak:
- Satış Analizi endpoint(leri)
- İlan Analizi endpoint(leri)

Canlı Yayınlarım endpoint'i `isTier3OrAbove()` olarak kalır.

---

## 6. Renk / Marka

### 6.1 Renk Paleti

| Tier | Renk | Hex | Kullanım |
|------|------|-----|---------|
| Standard | — | — | Rozet yok |
| PRO (tier1) | Altın | `#D97706` | Badge, kral tacı |
| PRO+ (tier2) | Altın | `#D97706` | Badge, kral tacı |
| PREMIUM (tier3) | Teqlif Cyan | `#06B6D4` | Badge, kral tacı |
| PREMIUM+ (tier4) | Teqlif Cyan | `#06B6D4` | Badge, kral tacı |

> PRO ve PRO+ aynı altın renk — tier2 accent rengi `Color(0xFFD97706)` ✅ Önceki
> session'da subscription_sheet.dart'ta tamamlandı.

### 6.2 Subscription Sheet — CTA Renkleri

| Tab | CTA rengi |
|-----|-----------|
| PRO | Altın (`#D97706`) |
| PRO+ | Altın (`#D97706`) |
| PREMIUM | Cyan (`#06B6D4`) |
| PREMIUM+ | Cyan (`#06B6D4`) |

---

## 7. Backend Değişiklikleri

### 7.1 `tier.py` — 5. Tier Ekleme 📋

**Dosya:** `backend/app/services/subscription/tier.py`

```python
TIER_4 = "tier4"    # PREMIUM+ (Sınırsız üyelik)

SUBSCRIPTION_TIERS: frozenset[str] = frozenset({TIER_1, TIER_2, TIER_3, TIER_4})

TIER_RANK: dict[str, int] = {
    TIER_STANDARD: 0,
    TIER_1:        1,
    TIER_2:        2,
    TIER_3:        3,
    TIER_4:        4,
}

# Yayın limitleri — V1.2
STREAM_LIMIT_MINUTES: dict[str, int | None] = {
    TIER_STANDARD: 1_800,   # 30 saat
    TIER_1:        5_400,   # 90 saat
    TIER_2:        10_800,  # 180 saat
    TIER_3:        21_600,  # 360 saat
    TIER_4:        None,    # sınırsız
}

COMMISSION_RATE: dict[str, float] = {
    TIER_STANDARD: 0.50,
    TIER_1:        0.75,
    TIER_2:        0.90,
    TIER_3:        1.00,
    TIER_4:        1.00,  # PREMIUM+ ile aynı
}

QUALITY_PROFILE: dict[str, str] = {
    TIER_STANDARD: "standard",   # 540p
    TIER_1:        "tier1",      # 720p
    TIER_2:        "tier1",      # 1080p — tier2'ye profil gerekebilir
    TIER_3:        "tier3",      # 1080p
    TIER_4:        "tier3",      # 1080p — PREMIUM ile aynı profil
}

CREDIT_FREE_LIMITS: dict[str, dict[str, int]] = {
    "blast": {
        ...,
        TIER_4: 30,    # PREMIUM ile aynı
    },
    "boost": {
        ...,
        TIER_4: 10,
    },
    "ai_desc": {
        ...,
        TIER_4: 30,
    },
    "reactivation": {
        ...,
        TIER_4: 10,
    },
}

CREDIT_PER_OP_CAPS: dict[str, dict[str, int]] = {
    "blast": {
        ...,
        TIER_4: 50,    # PREMIUM ile aynı
    },
}

# PREMIUM+ IAP product'ları
PRODUCT_TIER: dict[str, str] = {
    ...,
    "teqlif_premium_plus_1m":    TIER_4,
    "teqlif_premium_plus_3m":    TIER_4,
    "teqlif_premium_plus_6m":    TIER_4,
    "teqlif_premium_plus_12m":   TIER_4,
}

PRODUCT_PLAN_TYPE: dict[str, str] = {
    ...,
    "teqlif_premium_plus_1m":   "monthly",
    "teqlif_premium_plus_3m":   "quarterly",
    "teqlif_premium_plus_6m":   "biannual",
    "teqlif_premium_plus_12m":  "annual",
}
```

### 7.2 DB Migration — `user_type` CHECK Constraint 📋

**Dosya:** yeni Alembic revision (ID ≤ 32 char)

```python
# revision = "zzzzzzzl_tier4_user_type"
def upgrade():
    op.execute("""
        ALTER TABLE users DROP CONSTRAINT IF EXISTS users_user_type_check
    """)
    op.execute("""
        ALTER TABLE users ADD CONSTRAINT users_user_type_check
        CHECK (user_type IN ('standard', 'tier1', 'tier2', 'tier3', 'tier4'))
    """)
```

> ADR kuralı: multi-statement yasak — iki ayrı revision veya tek revision ama
> DROP + ADD aynı revision'da (pg'de bu atomic, Alembic transaction'ı kırmaz).
> Tercih: tek revision, iki `op.execute` çağrısı.

### 7.3 `verify_purchase_command.py` — Fiyat Tablosu Güncelleme 📋

**Dosya:** `backend/app/use_cases/wallet/commands/verify_purchase_command.py`

`_PRODUCT_TRY_PRICES` tablosu tüm yeni fiyatlarla güncellenmeli:

```python
_PRODUCT_TRY_PRICES: dict[str, float] = {
    # ... consumable'lar değişmez ...
    # PRO — yeni fiyatlar
    "teqlif_pro_1m":           799.99,
    "teqlif_pro_3m":          2159.99,
    "teqlif_pro_6m":          3999.99,
    "teqlif_pro_12m":         7199.99,
    # PRO+
    "teqlif_pro_plus_1m":     1499.99,
    "teqlif_pro_plus_3m":     3999.99,
    "teqlif_pro_plus_6m":     7499.99,
    "teqlif_pro_plus_12m":   13499.99,
    # PREMIUM
    "teqlif_premium_1m":      2899.99,
    "teqlif_premium_3m":      7799.99,
    "teqlif_premium_6m":     14999.99,
    "teqlif_premium_12m":    26999.99,
    # PREMIUM+ (yeni)
    "teqlif_premium_plus_1m":   5999.99,
    "teqlif_premium_plus_3m":  15999.99,
    "teqlif_premium_plus_6m":  29999.99,
    "teqlif_premium_plus_12m": 53999.99,
}
```

### 7.4 Apple/Google Webhook Handler'ları 📋

**Dosyalar:**
- `backend/app/services/store/notifications/apple_handler.py`
- `backend/app/services/store/notifications/google_handler.py`

Tier4 (`tier4`) için `monthly_stream_minutes_used = 0` reset mantığı zaten
genel olarak çalışıyorsa değişiklik gerekmez. `tier_from_product` fonksiyonu
`PRODUCT_TIER` dict'ini kullandığından tier4 ürünleri otomatik tanınacak.

Kontrol edilecek: her iki handler'da `user_type` set eden yerlerde tier4'ün
özel bir case'i olup olmadığı.

### 7.5 Araç Endpoint'leri — PRO+ Erişim Genişletme 📋

Satış Analizi ve İlan Analizi endpoint'lerinde `isTier3()` → `isTier2OrAbove()`
değişikliği yapılacak.

İlgili dosyalar taranacak:
```bash
grep -rn "isTier3\|tier3\|TIER_3" backend/app/routers/ | grep -v "quality\|stream"
```

Canlı Yayınlarım endpoint'i değişmez (`isTier3OrAbove()` kalır).

---

## 8. Flutter / Mobile Değişiklikleri

### 8.1 `user_tier.dart` — tier4 Ekleme 📋

**Dosya:** `mobile/lib/core/user_tier.dart`

```dart
static const tier4 = 'tier4';  // PREMIUM+ (Sınırsız)

static bool hasSubscription(String userType) =>
    userType != standard;

static bool isTier3OrAbove(String userType) =>
    userType == tier3 || userType == tier4;

static bool isTier4(String userType) => userType == tier4;

static int? streamLimitMinutes(String userType) {
  switch (userType) {
    case tier4: return null;    // sınırsız
    case tier3: return 21600;   // 360 saat
    case tier2: return 10800;   // 180 saat
    case tier1: return 5400;    // 90 saat
    default:    return 1800;    // 30 saat (standard)
  }
}

static int tierLevel(String userType) {
  switch (userType) {
    case tier4: return 4;
    case tier3: return 3;
    case tier2: return 2;
    case tier1: return 1;
    default:    return 0;
  }
}

static int commissionPercent(String userType) {
  switch (userType) {
    case tier4: return 100;
    case tier3: return 100;
    case tier2: return 90;
    case tier1: return 75;
    default:    return 50;
  }
}

static bool isQualityLocked(String userType, String quality) {
  switch (quality) {
    case '1080p': return !isTier2OrAbove(userType);  // tier2+ = 1080p
    case '720p':  return !hasSubscription(userType);
    default:      return false;
  }
}
```

> **Dikkat:** `isTier2OrAbove` şu an sadece `tier2 || tier3` — `tier4` eklenmeli.

### 8.2 `subscription_sheet.dart` — 4. Tab Ekleme 📋

**Dosya:** `mobile/lib/widgets/subscription_sheet.dart`

Mevcut 3 tab (PRO / PRO+ / PREMIUM) → 4 tab (+ PREMIUM+) eklenmeli.

```dart
// _plansByTier'a tier4 ekle
tier4: [
  _PlanOption('teqlif_premium_plus_1m',  'monthly',   5999.99),
  _PlanOption('teqlif_premium_plus_3m',  'quarterly', 15999.99),
  _PlanOption('teqlif_premium_plus_6m',  'biannual',  29999.99),
  _PlanOption('teqlif_premium_plus_12m', 'annual',    53999.99),
],

// _TierBenefits'e tier4 satırı ekle (5 benefit)
// tier4 streamLimit → null → 'Sınırsız' gösterimi
// tier4 accent rengi → Cyan (#06B6D4) — tier3 ile aynı
```

### 8.3 `subscription_tools_screen.dart` — Yeni Limitler 📋

**Dosya:** `mobile/lib/screens/subscription_tools_screen.dart`

`_streamLimitMinutesFor` fonksiyonu `UserTier.streamLimitMinutes()` ile
çalışıyorsa otomatik güncellenir (tier4 eklendikten sonra). Kontrol edilmeli.

### 8.4 `start_stream_helper.dart` — Limit Kontrolü 📋

**Dosya:** `mobile/lib/utils/start_stream_helper.dart`

`UserTier.streamLimitMinutes()` çağrısıyla çalışıyorsa tier4 otomatik alınır.
`limitReached` mantığı `null` kontrolü içerdiği için değişmez.

### 8.5 Araç Erişim — Flutter UI 📋

Satış Analizi ve İlan Analizi araçlarında `isTier3()` guard'ı varsa
`isTier3OrAbove()` → `isTier2OrAbove()` yapılacak.

```bash
grep -rn "isTier3\|tier3" mobile/lib/ | grep -v "_test\|.g.dart"
```

---

## 9. ARB / OTA Lokalizasyon

### 9.1 Yeni Anahtarlar 📋

**Dosyalar:** `documents/language/app_tr.arb` ve 4 dil (en, de, ru, ar)

```json
"tierPremiumPlus": "PREMIUM+",
"subTierPremiumPlusName": "PREMIUM+",
"subTierPremiumPlusTagline": "Sınırsız yayın, tam güç",
"subBenefitStreamUnlimitedShort": "Sınırsız yayın saati"
```

### 9.2 Workflow

ARB → `git push` → VPS `git pull` → `sync_main.py` (teqlif-restart içinde çalışır)

---

## 10. App Store / Google Play

### 10.1 Geliştirici Yapacaklar 📋

App Store Connect:
1. `teqlif_premium_plus_*` subscription ürünleri oluştur (4 adet)
2. Subscription Group hiyerarşisi güncelle:
   ```
   PREMIUM+  (seviye 1 — en yüksek)
   PREMIUM   (seviye 2)
   PRO+      (seviye 3)
   PRO       (seviye 4)
   ```
3. Mevcut PRO / PRO+ / PREMIUM fiyatlarını güncelle (§3.3)
4. PREMIUM+ için TR/EN açıklamalar yaz

Google Play Console:
1. `teqlif_premium_plus` subscription oluştur
2. Base plan'ları ekle (1m / 3m / 6m / 12m)
3. Mevcut subscription fiyatlarını güncelle

> **Not:** Fiyat güncelleme ve ürün oluşturma geliştirici tarafından yapılır.
> Kod tarafını Claude uygular.

---

## 11. Mevcut Kullanıcı Geçişi

### 11.1 Fiyat Artışı Stratejisi

PRO: ₺399 → ₺799 (**2× artış**) — mevcut kullanıcılar için şok yaratabilir.

**Öneri: Grandfather Period**

```
Seçenek A — 3 ay koruma: Mevcut aktif aboneler 3 ay boyunca eski fiyattan devam eder.
Seçenek B — 6 ay koruma: Daha uzun koruma, daha az churn riski.
```

Uygulama App Store / Google Play tarafından yapılır (subscription fiyat grandfathering
Apple ve Google'ın kendi mekanizmaları). Kod değişikliği gerekmez.

### 11.2 Standard Kullanıcı Yayın Saati Değişimi

Standard: 15 saat → 30 saat (**iyileştirme** — kullanıcı lehine).
Hiçbir mevcut kullanıcı olumsuz etkilenmez.

---

## 12. Implementasyon Sırası

### Faz 1 — Backend Altyapı (önce bu)

1. `tier.py` — tier4 ekleme + tüm limit güncellemeleri
2. Alembic migration — `user_type` CHECK constraint
3. `verify_purchase_command.py` — fiyat tablosu güncelleme
4. Araç endpoint'leri — PRO+ erişim genişletme
5. Webhook handler'ları — tier4 kontrolü

### Faz 2 — Flutter

6. `user_tier.dart` — tier4 ekleme
7. `subscription_sheet.dart` — 4. tab (PREMIUM+)
8. ARB dosyaları — yeni lokalizasyon key'leri
9. Araç ekranları — `isTier2OrAbove` güncelleme

### Faz 3 — Deploy

10. Commit + push + `sudo teqlif-restart` (ADR §13)
11. Alembic migration çalıştırıldığını doğrula

### Faz 4 — Geliştirici (Claude değil)

12. App Store Connect — PREMIUM+ ürünleri + fiyat güncellemeleri
13. Google Play Console — PREMIUM+ subscription
14. Flutter build + store submission

---

*Bu döküman V1.2 implementasyonunun birincil referansıdır.*
*ADR §13 workflow ve V1.1 §0 standartları aynen geçerlidir.*
