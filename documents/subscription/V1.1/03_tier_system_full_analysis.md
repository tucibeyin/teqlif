# Tier Sistemi — Tam Analiz Raporu

**Tarih:** 2026-11-23  
**Durum:** Canlıya çıkmadı → backward compat yok → temiz refactor yapılabilir

---

## Mevcut Durum: "İki Dünya" Problemi

Şu an sistemde iki çelişen model var:

```
YENİ (tier.py — doğru)          ESKİ (her yerde — yanlış)
─────────────────────────        ──────────────────────────
4 tier: standard/pro/            2 durum: pro / değil
  pro_plus/premium
is_paid_tier(user_type)          user_type == 'pro'
commission_rate(user_type)       _HOST_SHARE_PRO = 95 / _HOST_SHARE_STD = 70
STREAM_LIMIT_SECONDS dict        hardcoded sayılar
QUALITY_PROFILE dict             hardcoded string'ler
```

---

## Backend: Tespit Edilen Sorunlar

### 🔴 Kritik Bug — Yanlış hesaplama (para/gelir etkisi)

| # | Dosya | Satır | Sorun | Etki |
|---|---|---|---|---|
| B1 | `send_gift_command.py` | 81 | `receiver_type == "pro"` → `_HOST_SHARE_PRO = 95` | PRO+ (%90), PREMIUM (%100) yerine %70 alıyor |
| B2 | `send_gift_command.py` | ~5 | `_HOST_SHARE_PRO = 95` | tier.py'daki PRO=%75 ile çakışıyor |
| B3 | `credit_service.py` | ~16 | `_PREMIUM_TYPES = {"pro"}` | PRO+/PREMIUM tüm credit feature'larında standart gibi muamele görüyor |
| B4 | `credit_service.py` | ~32-55 | `free_pro / free_standard` ikilik | 4 tier yerine 2 durum; PRO+/PREMIUM PRO limitini bile görmüyor |

### 🟡 Önemli Bug — Yanlış erişim kontrolü

| # | Dosya | Satır | Sorun |
|---|---|---|---|
| B5 | `get_reactivation_cost.py` | 27 | `== 'pro'` → PRO+/PREMIUM ücretsiz reactivation hakkı almıyor |
| B6 | `toggle_listing.py` | 59 | `== 'pro'` → aynı |
| B7 | `listings.py` | 865 | `!= 'pro'` → AI desc PRO+/PREMIUM'a engelleniyor |
| B8 | `listings.py` | 877 | `== 'pro'` → yanlış error code |
| B9 | `streams.py` | 213 | `== 'pro'` → ready_buyers sayımı yanlış |
| B10 | `search_listings_query.py` | 115,119 | `== 'pro'` → PRO+/PREMIUM ilanlar sıralamada standart ile aynı |

### 🟢 Kabul Edilebilir / Temizlenecek

| # | Dosya | Sorun | Not |
|---|---|---|---|
| B11 | `ads.py` | `is_pro` alanı response'da | Artık `!= 'standard'` ile düzeltildi; `user_type` eklenmesi tercih edilir |
| B12 | `wallet_summary` | `is_pro` alanı | Zaten `user_type` eklendi; `is_pro` silinebilir |
| B13 | `reconcile_subscription_command.py` | `"is_pro": False` return | Silinebilir |
| B14 | `admin_data.py` | `is_now_pro = user_type != 'pro'` | Admin-only, ayrıca ele alınır |

---

## `credit_service.py` — En Büyük Mimari Sorun

Şu an:
```python
_PREMIUM_TYPES = frozenset({"pro"})   # ← sadece pro!

_FEATURES = {
    CreditFeature.BLAST: {
        "free_standard": 3,
        "free_pro":      6,   # ← sadece 2 kategori
    }
}
```

Olması gereken (4 tier-aware):
```python
_FEATURES = {
    CreditFeature.BLAST: {
        "free_limits": {           # tier başına limit
            "standard": 3,
            "pro":      6,
            "pro_plus": 10,
            "premium":  15,
        },
        "per_op_caps": {
            "standard": 5,
            "pro":      10,
            "pro_plus": 15,
            "premium":  20,
        },
        "cost_teqlik": 10,
    },
    ...
}

def free_limit(feature, user_type) -> int:
    return _FEATURES[feature]["free_limits"].get(user_type, 0)
```

**Önemli:** Bu değerlerin ne olacağı **iş kararı** — geliştirici değil. Şimdilik PRO değerleriyle eşit bırakılabilir, sonra güncellenir.

---

## Flutter: Tespit Edilen Sorunlar

### `isPremium: bool` → `userType: String` geçişi

`isPremium` parametresi şu an **14 farklı ekran/widget** arasında zincir oluşturuyor:

```
ProHubScreen(isPremium: bool)
  → ProInsightsScreen(isPremium: bool)
  → ListingAnalyticsScreen(isPremium: bool)
  → ConversionBreakdownScreen(isPremium: bool)
  → MarketIntelligenceScreen(isPremium: bool)
  → DemandTrendsScreen(isPremium: bool)
  → BestStreamTimeScreen(isPremium: bool)
  → CompetitorRadarScreen(isPremium: bool)
  → LiveStreamHistoryScreen(isPremium: bool)
  → RetargetingScreen(isPremium: bool)
  → MyRecordingsScreen(isPremium: bool)
  → NotificationSettingsScreen(isPremium: bool)
```

**Şu an `isPremium: bool` ne işe yarıyor?**
Çoğu ekranda sadece paywall göster/gizle için kullanılıyor:
```dart
if (!isPremium) return _PaywallBanner();
```

**Sorun:** `isPremium = true` demek artık "standart değil" demek. Ama hangi tier? Bazı özellikler PRO+'a kısıtlı olabilir. Bool bunu ifade edemez.

### `ProHubViewModel` — Kısmen geçiş yapılmış, tutarsız

```dart
// SORUNLU: arg bool olarak geliyor, userType 'pro' olarak hardcoded atanıyor
return ProHubState(isPremium: arg, userType: arg ? 'pro' : 'standard');
//                                              ↑ PRO+ veya PREMIUM gelirse 'pro' yazıyor!
```

`ProHubScreen(isPremium: false)` ile açılan bir ekran, gerçek user_type'ı `verifyPremium()` çağrısıyla düzeltiyor — ama ilk render yanlış.

### WalletScreen — `isPro: bool` → `userType: String` kısmen yapıldı

`userType` eklendi ama `_isPro` bool state hâlâ var. İkisi birlikte çelişebilir:
```dart
// Bu ikisi sync dışına düşebilir:
bool _isPro = false;
String _userType = 'standard';
```

### CreateListingScreen

`_isPro: bool` var, `/auth/me` çekiyor, `data['user_type'] != 'standard'` ile set ediyor — mantık doğru ama bool yerine String olmalı.

---

## API Contract Sorunu

Şu an Flutter'a dönen API yanıtlarında karışıklık:

| Endpoint | Dönen | Eksik/Yanlış |
|---|---|---|
| `/auth/me` | `user_type` ✅ | — |
| `/wallet/summary` | `is_pro` + `user_type` ✅ | `is_pro` silinebilir |
| `/blast_credits` | `user_type` ✅ | — |
| `/boost_credits` | — | `user_type` yok |
| `/ai_desc_credits` | — | `user_type` yok |
| `/reactivation_credits` | — | `user_type` yok |
| `/ads/boost_status` | `is_pro` ⚠️ | `user_type` ile değiştirilmeli |

---

## Mimari Vizyon: Loose-Coupled Tier Sistemi

### Katmanlar

```
┌─────────────────────────────────────────────────────┐
│  LAYER 4: Campaign / Override Layer (gelecek ADR)    │
│  platform_config: kampanya, geçici boost, legacy     │
├─────────────────────────────────────────────────────┤
│  LAYER 3: Entitlement Resolution (yakında)           │
│  TierEntitlementService.resolve(user, feature)       │
│  → user override → campaign → tier config → default  │
├─────────────────────────────────────────────────────┤
│  LAYER 2: tier.py — Statik Tier Config (ŞİMDİ)      │
│  STREAM_LIMIT_SECONDS, COMMISSION_RATE, QUALITY     │
│  CREDIT_FREE_LIMITS, CREDIT_PER_OP_CAPS             │
│  Tek değişim noktası. Hiçbir router literal içermez. │
├─────────────────────────────────────────────────────┤
│  LAYER 1: DB — user.user_type (zaten var)            │
│  'standard' | 'pro' | 'pro_plus' | 'premium'        │
└─────────────────────────────────────────────────────┘
```

### Şimdi yapılacak: Layer 2'yi tamamla

`tier.py`'a credit limitleri ekle, `credit_service.py`'ı buradan oku. Artık tüm tier mantığı tek yerde.

### Yakında (ayrı ADR): Layer 3

`TierEntitlementService` — override zinciri. `platform_config`'ten okur. Kampanya, geçici bonus, legacy entitlement.

### Flutter tarafı

`isPremium: bool` → `userType: String` geçişi. Tüm 14 ekranda. Mantık şöyle:

```dart
// Her ekran kendi guard'ını yapar:
bool get hasAccess => userType != 'standard';          // genel paywall
bool get hasProPlusAccess => userType == 'pro_plus' || userType == 'premium';
bool get hasStreamingAccess => userType != 'standard'; // şimdilik tümü
```

---

## Refactor Kapsamı ve Sırası

### Faz 1 — Backend temizliği (kritik buglar + mimari) ~2-3 saat

1. **`credit_service.py`** — 4-tier aware `_FEATURES` tablosu; `_PREMIUM_TYPES` kaldır
2. **`tier.py`** — `CREDIT_FREE_LIMITS` ve `CREDIT_PER_OP_CAPS` sabitlerini ekle (single source)
3. **`send_gift_command.py`** — `commission_rate()` kullan, hardcoded sabitler kaldır
4. **`search_listings_query.py`** — `is_paid_tier()` kullan
5. **`streams.py`**, **`listings.py`**, **`get_reactivation_cost.py`**, **`toggle_listing.py`** — tüm `== 'pro'` → `is_paid_tier()`
6. **API responses** — `is_pro` alanları kaldırılıp `user_type` ile değiştirilir

### Faz 2 — Flutter refactoru ~2-3 saat

1. **`ProHubViewModel`** — `arg: bool` → `arg: String` (userType); `isPremium` state kaldır
2. **`ProHubScreen`** + 11 analytics ekranı — `isPremium: bool` → `userType: String`
3. **`WalletScreen`** — `_isPro: bool` kaldır, `_userType: String` tek source
4. **`CreateListingScreen`** — `_isPro: bool` → `_userType: String`
5. **StorageService** — `_userPremiumKey` ile saklanan `userType` string zaten doğru ✅

### Faz 3 — ADR yazılır, implement edilmez (gelecek sprint)

`TierEntitlementService` tasarımı: override zinciri, kampanya, legacy entitlement.

---

## Karar: Ne Yapılmayacak (Bu Refactoring'de)

- `platform_config`'e tier limitleri taşımak → Layer 3 kapsamında
- `premium_since` → `subscription_since` rename → migration riski, ayrıca
- `admin_data.py` tier toggle → admin-only, ayrıca
- Flutter'da özellik bazlı tier guard (`hasProPlusAccess`) → §8'de feature geliştirmeyle birlikte

---

## Özet Tablo

| Alan | Şu an | Olacak |
|---|---|---|
| Tier check | `== 'pro'` çoğu yerde | `is_paid_tier()` tek yer |
| Credit limits | 2 kategori (pro/std) | 4 kategori (tier tablosu) |
| Gift commission | hardcoded %95/%70 | `commission_rate(user_type)` |
| API response | `is_pro: bool` | `user_type: string` |
| Flutter routing | `isPremium: bool` | `userType: String` |
| Tier config source | dağınık, çoğaltılmış | sadece `tier.py` |
