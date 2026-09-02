# Uluslararası İlan Sistemi — Mimari Plan

> **Versiyon:** 2.0 (codebase tarama sonrası güncellendi)
> **Kapsam:** Geo veri · DB migration · Signup · İlan Ver · Filtre · Listing Card · Feed · Redis · ML/ClickHouse
> **Prensipler:** architectural_decisions.md · OTA (ADR #1) · Cache Taksonomisi (ADR #9) · MVVM (ADR #8) · Clean Architecture

---

## İçindekiler

1. [Karar Özeti](#1-karar-özeti)
2. [Mevcut Kod Durumu — Ne Değişecek](#2-mevcut-kod-durumu--ne-değişecek)
3. [Geo Veri Katmanı — geo.db](#3-geo-veri-katmanı--geodb)
4. [Backend & DB Migration](#4-backend--db-migration)
5. [Flutter: GeoService](#5-flutter-geoservice)
6. [Flutter: Paket Değişiklikleri](#6-flutter-paket-değişiklikleri)
7. [Signup Ekranı](#7-signup-ekranı)
8. [İlan Ver Ekranı (create_listing_screen)](#8-i̇lan-ver-ekranı-create_listing_screen)
9. [Filtre Kontrolü (TeqFilterSheet)](#9-filtre-kontrolü-teqfiltersheet)
10. [Listing Card](#10-listing-card)
11. [Feed Sorguları](#11-feed-sorguları)
12. [Redis Cache Stratejisi](#12-redis-cache-stratejisi)
13. [OTA / ARB](#13-ota--arb)
14. [ADR Uyumluluk Kontrol Listesi](#14-adr-uyumluluk-kontrol-listesi)
15. [Deploy Sırası](#15-deploy-sırası)
16. [Test Kontrol Listesi](#16-test-kontrol-listesi)
17. [cross_border_consent_locale — KVKK Analizi](#17-cross_border_consent_locale--kvkk-analizi)
18. [ML / ClickHouse / AI Etki Analizi](#18-ml--clickhouse--ai-etki-analizi)

---

## 1. Karar Özeti

| Konu | Karar |
|------|-------|
| Geo veri kaynağı | dr5hn/countries-states-cities-database (MIT lisanslı, açık kaynak) |
| Veri depolama | SQLite (`assets/geo/geo.db`) — app içinde bundle, offline |
| Backend geo API | YOK — picker ve filtre için hiç backend çağrısı yapılmaz |
| Ülke seçimi | Signup'ta bir kez seçilir, `user.country_code` olarak saklanır |
| Feed varsayılanı | `user.country_code` ile eşleşen ilanlar |
| Para birimi | Ülke seçiminden otomatik → `user.currency_code` |
| Listing dili | İlan Ver'de `listing_lang` alanı, varsayılan `user.locale` |
| Kapsam | 250 ülke · ~5.000 eyalet · ~150.000 şehir |
| `province`/`district` alanları | Mevcut sütunlar korunur — `state_name`/`city_name` olarak yeniden anlamlandırılır |

---

## 2. Mevcut Kod Durumu — Ne Değişecek

### 2.1 Backend Model Eksikleri

| Model | Mevcut Alanlar | Eksik |
|-------|---------------|-------|
| `listings` | `province (String 100)`, `district (String 100)`, `location (String 100 — eski)` | `country_code`, `currency_code`, `listing_lang` |
| `users` | `locale (String 10, default "tr")` | `country_code`, `currency_code` |
| `cities` | `id, name, sort_order` | Türkiye-only, `country_code` yok |
| `districts` | `id, city_id, name` | Türkiye-only |
| `user_interests` | `user_id, category, subcategory, score` | `country_code` yok |
| `analytics_events` | `event_metadata (JSONB)` | `country_code` yok |
| `user_interactions` | `item_id, item_type, interaction_type` | `country_code` yok |

> `province` → `state_name`, `district` → `city_name` semantik dönüşümüdür — DB sütun adları korunabilir veya migration ile rename edilebilir. Bu plan rename tercih eder.

### 2.2 Mobile Servis Eksikleri

| Dosya | Mevcut | Değişecek |
|-------|--------|-----------|
| `city_service.dart` | `GET /api/cities` → `List<String>` | Yerini `GeoService` alacak |
| `create_listing_screen.dart` | `_selectedProvince`, `_selectedDistrict` | `_selectedCountry`, `_selectedState`, `_selectedCity` |
| `register_screen.dart` | Ülke/para birimi alanı yok | Country picker eklenecek |
| `TeqFilterSheet` | `city (String?)` tek alan | `country_code`, `stateName`, `cityName` cascade |
| `ListingFilterState` | `city, condition, sortBy, minPrice, maxPrice` | `countryCode`, `stateName`, `cityName` eklenecek |
| `_HorizontalListingCard` | Fiyat ₺ hardcoded, konum gösterilmiyor | Para birimi dinamik, konum badge eklenmeli |

### 2.3 ClickHouse Tablo Eksikleri

Tüm tablolarda `country_code` kolonu yok:

| Tablo | TTL | ORDER BY |
|-------|-----|----------|
| `user_events` | 180 gün | `(timestamp, item_id)` |
| `feed_analytics` | 365 gün | `(listing_id, event_type, timestamp)` |
| `search_events` | 365 gün | `(category, timestamp)` |
| `swipe_live_events` | 180 gün | `(user_id, timestamp)` |
| `direct_sale_events` | 730 gün | — |

---

## 3. Geo Veri Katmanı — geo.db

### 3.1 Kaynak

```
github.com/dr5hn/countries-states-cities-database
→ json/countries.json
→ json/states.json
→ json/cities.json
```

### 3.2 Dönüşüm Script'i

**Dosya:** `scripts/build_geo_db.py`

```python
# Çalıştırma: python3 scripts/build_geo_db.py
# Çıktı: mobile/assets/geo/geo.db
```

Script şu tabloları oluşturur:

```sql
CREATE TABLE countries (
    code          TEXT PRIMARY KEY,   -- 'TR', 'AE', 'RU'
    name          TEXT NOT NULL,      -- 'Turkey'
    currency_code TEXT NOT NULL,      -- 'TRY'
    phone_code    TEXT,               -- '+90'
    flag_emoji    TEXT                -- '🇹🇷'
);

CREATE TABLE states (
    id           INTEGER PRIMARY KEY,
    country_code TEXT NOT NULL REFERENCES countries(code),
    name         TEXT NOT NULL,       -- 'İstanbul'
    state_code   TEXT                 -- '34'
);
CREATE INDEX idx_states_country ON states(country_code);

CREATE TABLE cities (
    id           INTEGER PRIMARY KEY,
    state_id     INTEGER NOT NULL REFERENCES states(id),
    country_code TEXT NOT NULL,
    name         TEXT NOT NULL        -- 'Kadıköy'
);
CREATE INDEX idx_cities_state ON cities(state_id);
```

### 3.3 Flag Emoji Üretimi

```dart
// mobile/lib/utils/country_flags.dart
String flagEmoji(String code) =>
  code.toUpperCase().runes
    .map((r) => String.fromCharCode(r - 0x41 + 0x1F1E6))
    .join();
// 'TR' → '🇹🇷'
```

Backend'e veya DB'ye flag saklanmaz — her zaman hesaplanır.

### 3.4 Boyut

| Dosya | Ham | APK/IPA (sıkıştırılmış) |
|-------|-----|------------------------|
| geo.db | ~5 MB | ~2 MB |

### 3.5 Asset Tanımı

```yaml
# pubspec.yaml (mevcut assets listesine eklenir)
flutter:
  assets:
    - assets/geo/geo.db
```

---

## 4. Backend & DB Migration

### 4.1 `listings` Tablosu

Mevcut: `province (String 100)`, `district (String 100)`, `location (String 100)`.

```sql
-- Mevcut sütunları rename et
ALTER TABLE listings RENAME COLUMN province TO state_name;
ALTER TABLE listings RENAME COLUMN district TO city_name;

-- Yeni sütunlar
ALTER TABLE listings ADD COLUMN country_code  VARCHAR(2)  NOT NULL DEFAULT 'TR';
ALTER TABLE listings ADD COLUMN currency_code VARCHAR(3)  NOT NULL DEFAULT 'TRY';
ALTER TABLE listings ADD COLUMN listing_lang  VARCHAR(5)  NOT NULL DEFAULT 'tr';
```

- Rename sonrası mevcut ilanlar verilerini korur (TR illeri `state_name` olarak kalır)
- `location` eski alanı silinmez — backcompat; read-only kalır, yeni kod yazmaz

### 4.2 `users` Tablosu

```sql
ALTER TABLE users ADD COLUMN country_code  VARCHAR(2) NOT NULL DEFAULT 'TR';
ALTER TABLE users ADD COLUMN currency_code VARCHAR(3) NOT NULL DEFAULT 'TRY';
```

- Mevcut kullanıcılar `TR` / `TRY` alır → backward compat korunur

### 4.3 İndeksler

```sql
CREATE INDEX ix_listings_country       ON listings(country_code);
CREATE INDEX ix_listings_country_state ON listings(country_code, state_name);
-- ix_listings_province eski indexi drop edilir:
DROP INDEX IF EXISTS ix_listings_province;
```

### 4.4 Listing SQLAlchemy Modeli (`backend/app/models/listing.py`)

```python
# province → state_name rename (mapped_column name argümanıyla)
state_name:    Mapped[Optional[str]] = mapped_column(String(100), index=False)
city_name:     Mapped[Optional[str]] = mapped_column(String(100))
country_code:  Mapped[str]           = mapped_column(String(2),  default='TR', index=True)
currency_code: Mapped[str]           = mapped_column(String(3),  default='TRY')
listing_lang:  Mapped[str]           = mapped_column(String(5),  default='tr')
```

### 4.5 User SQLAlchemy Modeli (`backend/app/models/user.py`)

```python
country_code:  Mapped[str] = mapped_column(String(2),  default='TR')
currency_code: Mapped[str] = mapped_column(String(3),  default='TRY')
```

### 4.6 Pydantic Schema Değişiklikleri

```python
# ListingCreate (backend/app/schemas/)
country_code:  str = 'TR'
state_name:    Optional[str] = None   # eski: province
city_name:     Optional[str] = None   # eski: district
currency_code: str = 'TRY'
listing_lang:  str = 'tr'

# UserRegister
country_code:  str = 'TR'
currency_code: str = 'TRY'
```

### 4.7 ADR #9 Zorunluluğu

```python
# migration upgrade() sonunda
bump_schema_version()   # SCHEMA_VERSIONED cache'i invalidate eder
```

### 4.8 Fiyat Sinyali Endpoint

`GET /api/listings/{id}/price-signal` — `last_sold_price` kullanıyor, `currency_code` filtresi YOK.

```python
# listings.py price-signal endpoint'ine eklenecek WHERE koşulu:
AND listings.currency_code = :currency_code
```

---

## 5. Flutter: GeoService

**Yeni dosya:** `mobile/lib/services/geo_service.dart`

### 5.1 Model Sınıfları

**Yeni dosya:** `mobile/lib/models/geo_models.dart`

```dart
class GeoCountry {
  final String code;          // 'TR'
  final String name;          // 'Turkey'
  final String currencyCode;  // 'TRY'
  final String phoneCode;     // '+90'
  final String flagEmoji;     // '🇹🇷'
}

class GeoState {
  final int    id;
  final String countryCode;
  final String name;
  final String stateCode;
}

class GeoCity {
  final int    id;
  final int    stateId;
  final String countryCode;
  final String name;
}
```

### 5.2 GeoService

```dart
class GeoService {
  static Database? _db;
  static List<GeoCountry>?                 _countries;
  static final Map<String, List<GeoState>> _stateCache = {};
  static final Map<int,    List<GeoCity>>  _cityCache  = {};

  /// main() içinde WidgetsFlutterBinding.ensureInitialized() sonrası çağrılır.
  /// assets/geo/geo.db → getApplicationDocumentsDirectory()'e kopyalar (ilk açılış).
  static Future<void> init() async { ... }

  static Future<List<GeoCountry>> getCountries() async { ... }
  static Future<List<GeoState>>   getStates(String countryCode) async { ... }
  static Future<List<GeoCity>>    getCities(int stateId) async { ... }
  static GeoCountry?              findCountry(String code) { ... }
}
```

`GeoService.init()` → `main()` içine, `Hive.initFlutter()` ile aynı blokta çağrılır.

---

## 6. Flutter: Paket Değişiklikleri

**`pubspec.yaml`'a eklenecek:**

```yaml
dependencies:
  sqflite: ^2.3.3
  path: ^1.9.0
```

`path_provider: ^2.1.4` zaten mevcut ✓

---

## 7. Signup Ekranı

**Dosya:** `mobile/lib/screens/auth/register_screen.dart`

### 7.1 Mevcut State

```dart
// Mevcut (ülke/currency YOK):
bool _eulaAccepted = false;
bool _ageConfirmed = false;
bool _crossBorderConsent = false;
String? _usernameStatus;
```

### 7.2 Eklenecek State

```dart
GeoCountry? _selectedCountry;   // signup'ta seçilen ülke
// currency_code _selectedCountry.currencyCode'dan otomatik
```

### 7.3 Yeni UI Elemanı

Mevcut form alanları sonuna (cross_border checkbox'ından önce) eklenir:

```
[Ülke Seç ▼]   ← GeoService.getCountries(), arama destekli dialog/dropdown
                ← Seçim → currency_code _selectedCountry.currencyCode'dan
                ← Varsayılan: user.locale == 'tr' → Turkey; diğerleri → null (zorunlu seçim)
```

Para birimi kullanıcıya gösterilmez, arka planda otomatik set edilir.

### 7.4 API Payload

**Dosya:** `mobile/lib/services/auth_service.dart` — `register()` metodu

```dart
// Mevcut payload'a eklenecek:
'country_code':  _selectedCountry!.code,          // 'TR'
'currency_code': _selectedCountry!.currencyCode,  // 'TRY'
```

### 7.5 OTA Key'leri

```
signupCountryLabel  → "Ülke" / "Country" / "البلد" / "Страна"
signupCountryHint   → "Ülkenizi seçin" / "Select your country" / ...
signupCountryRequired → "Lütfen ülke seçin"
```

---

## 8. İlan Ver Ekranı (create_listing_screen)

**Dosya:** `mobile/lib/screens/create_listing_screen.dart`

### 8.1 Mevcut State (silinecekler)

```dart
// KALDIRILACAK:
String?      _selectedProvince;
String?      _selectedDistrict;
List<String> _provinces = [];
List<String> _districts = [];
// → CityService.getCities() ve CityService.getDistricts() çağrıları da silinir
```

### 8.2 Yeni State

```dart
// EKLENECEKler:
GeoCountry? _selectedCountry;   // user.country_code'dan önceden dolu gelir
GeoState?   _selectedState;
GeoCity?    _selectedCity;
List<GeoState> _states = [];
List<GeoCity>  _cities = [];
String _listingLang = '';        // user.locale'den default
```

### 8.3 `_loadData()` Değişikliği

```dart
// MEVCUT:
final cities = await CityService.getCities();
_provinces = cities;

// YENİ:
final country = GeoService.findCountry(userCountryCode ?? 'TR');
_selectedCountry = country;
_listingLang = userLocale ?? 'tr';
if (country != null) {
  _states = await GeoService.getStates(country.code);
}
```

### 8.4 Cascade

```dart
void _onCountryChanged(GeoCountry c) {
  _selectedCountry = c;
  _selectedState = null;
  _selectedCity  = null;
  _cities = [];
  _states = await GeoService.getStates(c.code);
  setState(() {});
}

void _onStateChanged(GeoState s) {
  _selectedState = s;
  _selectedCity  = null;
  _cities = await GeoService.getCities(s.id);
  setState(() {});
}
```

### 8.5 İlan Dili (listing_lang)

```
[İlan Dili ▼]  ← Dropdown: TR / EN / AR / RU
               ← Varsayılan: user.locale
               ← Label: fieldListingLang (OTA)
```

### 8.6 Payload Değişikliği

```dart
// MEVCUT:
if (_selectedProvince != null) 'province': _selectedProvince,
if (_selectedDistrict != null) 'district': _selectedDistrict,

// YENİ (field adları backend migration'la eşleşiyor):
if (_selectedCountry != null) 'country_code':  _selectedCountry!.code,
if (_selectedState   != null) 'state_name':    _selectedState!.name,
if (_selectedCity    != null) 'city_name':     _selectedCity!.name,
                              'currency_code': _selectedCountry?.currencyCode ?? 'TRY',
                              'listing_lang':  _listingLang,
```

---

## 9. Filtre Kontrolü (TeqFilterSheet)

**Dosyalar:**
- `mobile/lib/ui_library/components/filters/teq_filter_sheet.dart`
- `mobile/lib/models/listing_filter_state.dart`

### 9.1 Mevcut `ListingFilterState`

```dart
// MEVCUT:
final String? category;
final String? subcategory;
final String? city;          // tek şehir adı String
final String? condition;
final String? sortBy;
final double? minPrice;
final double? maxPrice;
final String? searchQuery;
final DateTime? dateFrom;
final DateTime? dateTo;
final Map<String, dynamic> extraFields;
// District filtresi YOK, country filtresi YOK
```

### 9.2 Güncellenmiş `ListingFilterState`

```dart
// EKLENECEKler — city kaldırılmaz, country/state/city cascade ile değiştirilir:
final String? countryCode;   // 'TR', 'AE', null
final String? stateName;     // 'İstanbul', null
final String? cityName;      // 'Kadıköy', null
// eski `city` alanı → stateName olarak rename edilir
```

`copyWith`, `==`, `hashCode` güncellenir.

### 9.3 TeqFilterSheet'e Eklenen Filtreler

Mevcut `showCity` bloğu yeniden yazılır:

```
[Ülke   ▼]   ← GeoService.getCountries(), searchable dialog
[İl     ▼]   ← GeoService.getStates(selectedCountry), ülke seçilince aktif
[İlçe   ▼]   ← GeoService.getCities(selectedState.id), il seçilince aktif
```

### 9.4 Cascade Davranışı

- Ülke değişince → İl temizlenir → İlçe temizlenir
- İl değişince → İlçe temizlenir
- Ülke seçilmezse → İl + İlçe disabled görünür

### 9.5 Feed'e Parametre

```
GET /api/listings?country_code=TR&state_name=İstanbul&city_name=Kadıköy
```

### 9.6 State

```dart
// TeqFilterSheet içinde:
GeoCountry? _filterCountry;
GeoState?   _filterState;
GeoCity?    _filterCity;
List<GeoState> _filterStates = [];
List<GeoCity>  _filterCities = [];
```

---

## 10. Listing Card

**Dosya:** `mobile/lib/screens/search_screen.dart` → `_HorizontalListingCard`
(Bağımsız `listing_card.dart` dosyası yok — kart `search_screen.dart` içinde tanımlı)

### 10.1 Mevcut Durum

```dart
// Gösterilenler:
- listing['image_urls'][0]          // CachedNetworkImage
- listing['price']  → _fmt()        // ₺ hardcoded, binlik nokta
- listing['is_sponsored'] badge
- listing['is_highlight'] badge
- ListingBadgeOverlay(listing)      // condition/status
// Konum: GÖSTERİLMİYOR
// Para birimi: TRY hardcoded (₺)
```

### 10.2 Gerekli Değişiklikler

**Konum Badge'i ekle:**

```dart
// state_name varsa göster (kart 120px genişliğinde — kısa tutulmalı)
if (listing['state_name'] != null)
  Text(
    '${listing['state_name']} ${flagEmoji(listing['country_code'] ?? 'TR')}',
    style: TextStyle(fontSize: 10),
    overflow: TextOverflow.ellipsis,
    maxLines: 1,
  )
```

**Fiyat para birimi:**

```dart
// MEVCUT:
Text('${_fmt(price)} ₺')

// YENİ (currency_code'a göre sembol):
Text('${_fmt(price)} ${_currencySymbol(listing['currency_code'] ?? 'TRY')}')

// Yardımcı:
String _currencySymbol(String code) => const {
  'TRY': '₺', 'USD': '\$', 'EUR': '€', 'AED': 'د.إ', 'GBP': '£',
  'SAR': '﷼', 'QAR': '﷼', 'RUB': '₽',
}[code] ?? code;
```

### 10.3 Listing Detail Screen

`listing_detail_screen.dart` içinde de `province`/`district` referansları `state_name`/`city_name` olarak güncellenir.

---

## 11. Feed Sorguları

Birden fazla feed endpoint'i var — hepsine `country_code` eklenmeli.

### 11.1 `GET /api/listings` (SearchListingsQuery)

**Dosya:** `backend/app/routers/listings.py`

```python
# Mevcut sorgu parametreleri: category, subcategory, location, q, limit, offset...
# EKLENECEK:
country_code: Optional[str] = Query(None)   # filtre varsa override, yoksa user.country_code

# WHERE koşulu:
AND listings.country_code = COALESCE(:country_code, :user_country_code)
AND (:state_name IS NULL OR listings.state_name = :state_name)
AND (:city_name  IS NULL OR listings.city_name  = :city_name)
```

### 11.2 `GET /api/feed` (Personalized)

**Dosya:** `backend/app/routers/feed.py`

ClickHouse epsilon-greedy feed, BPR önerileri ve recently-active ilanlar —
hepsine `AND listings.country_code = :user_country_code` eklenir.

### 11.3 `GET /api/feed/for-you` (pgvector cosine)

`preference_embedding` sorgusu:

```sql
-- MEVCUT:
ORDER BY listing.embedding <=> :user_embedding LIMIT 50

-- YENİ:
WHERE listing.country_code = :user_country_code
  AND listing.status = 'active'
ORDER BY listing.embedding <=> :user_embedding LIMIT 50
```

Redis cache key'i `feed:foryou:{user_id}` → `feed:foryou:{user_id}:{country_code}` olur.
(Kullanıcı filtre değiştirirse farklı ülke için ayrı cache oturumu)

### 11.4 `GET /api/feed/recent`

`feed:recent` ZSET — tüm ülkelerin ilanları karışık.

```python
# YENİ YAPI: ülke başına ayrı ZSET
# feed:recent:{country_code}   ← ZSET, score=listing.id, maks 2000 eleman

# İlan oluşturulurken:
await redis.zadd(f'feed:recent:{listing.country_code}', {str(listing.id): listing.id})
await redis.zremrangebyrank(f'feed:recent:{listing.country_code}', 0, -2001)

# İlan silinirken:
await redis.zrem(f'feed:recent:{listing.country_code}', str(listing.id))

# Okurken (user.country_code ile):
ids = await redis.zrevrange(f'feed:recent:{user.country_code}', 0, limit-1)
```

### 11.5 Swipe Feed

`GET /api/listings/swipe-feed` — `GetSwipeFeedQuery`'ye `country_code` filtresi eklenir.
`preferred_categories` sorgusu için UserInterest'te `country_code` filtresi (§18.4).

### 11.6 Trending

**`compute_trending_listings_task`** (her 30 dakika):

```python
# MEVCUT: global trending
# YENİ: ülke başına trending
GROUP BY country_code, listing_id
# → trend:listings:{country_code} key'leri
```

**`compute_trending_categories_task`** (6 saatte bir) — benzer şekilde ülke bazlı.

---

## 12. Redis Cache Stratejisi

### 12.1 Değişmesi Gereken Key'ler

| Eski Key | Yeni Key | Neden |
|----------|----------|-------|
| `feed:recent` (ZSET) | `feed:recent:{country_code}` | Ülke karışımını önler |
| `feed:{uid}:foryou` | `feed:foryou:{uid}:{country_code}` | Ülke değişince ayrı cache |
| `trend:listings` | `trend:listings:{country_code}` | Ülke bazlı trending |
| `trend:categories` | `trend:categories:{country_code}` | Ülke bazlı trending |

### 12.2 Değişmeyen Key'ler

Bu key'ler kullanıcı bazlı olduğu için `country_code` eklemeye gerek yok — kullanıcı zaten bir ülkede kayıtlı:

| Key | Açıklama |
|-----|----------|
| `listing:{id}` | İlan verisi, country_code zaten içinde |
| `bpr:rec:{uid}` | BPR önerileri, ülke bazlı eğitim sorun (§18) |
| `interests:{uid}` | UserInterest, ülke filtresi compute sırasında |
| `condition_pref:{uid}` | Kişisel tercih |
| `feed:session:{uid}` | 30 dk session embedding |
| `feed:hesitated:{uid}` | Hesitated shelf |
| `not_interested:{uid}` | 14 günlük filtre |
| `swipelive:als:*` | SwipeLive ALS vektörleri |

### 12.3 ClickHouse Buffer Key'leri

ClickHouse'a yazarken `country_code` event'e eklenir — Redis buffer key yapısı değişmez:

```python
# ch_buf:user_events, ch_buf:search_events — mevcut key isimleri korunur
# Sadece buffer'a push edilen JSON payload'a 'country_code' alanı eklenir
```

---

## 13. OTA / ARB

### 13.1 Yeni Key'ler (TR, EN, AR, RU)

```json
"signupCountryLabel":   "Ülke",
"signupCountryHint":    "Ülkenizi seçin",
"signupCountryRequired":"Lütfen ülke seçin",
"fieldCountry":         "Ülke",
"fieldState":           "İl / Eyalet",
"fieldCity":            "İlçe / Şehir",
"fieldListingLang":     "İlan Dili",
"listingLangHint":      "İlanı hangi dilde yazdınız?",
"listingLangTr":        "Türkçe",
"listingLangEn":        "İngilizce",
"listingLangAr":        "Arapça",
"listingLangRu":        "Rusça"
```

### 13.2 Ülke İsimleri

Ülke isimleri `geo.db`'deki `countries.name` alanından gelir (İngilizce). Türkçe isimler için `country_{CODE}` key'leri ilerleyen sprintte eklenebilir — şimdilik İngilizce fallback kabul edilir.

### 13.3 Deploy

```bash
git pull && python3 scripts/sync_translations.py && sudo systemctl restart teqlif
```

---

## 14. ADR Uyumluluk Kontrol Listesi

| ADR | Kural | Bu plan |
|-----|-------|---------|
| #1 OTA | Yeni UI string → ARB → sync | ✅ Tüm yeni labellar ARB'de |
| #2 Declarative | Field config JSON → DB | ✅ Geo, category field değil — ayrı sistem |
| #4 Error Handling | `handleError(e, loc)` | ✅ GeoService hataları handleError'a düşer |
| #5 Async Button | Network çağrısı → TeqAsyncButton | ✅ Signup submit TeqAsyncButton |
| #8 MVVM | Karmaşık ekran → ViewModel | ✅ create_listing mevcut ViewModel'e eklenir |
| #9 Cache | Schema değişikliği → bump_schema_version() | ✅ Migration sonunda çağrılır |

---

## 15. Deploy Sırası

```
── BACKEND (önce) ──────────────────────────────────────────────────────────────

1. Alembic migration yaz:
   a. listings.province → state_name  (rename)
   b. listings.district → city_name   (rename)
   c. listings: + country_code VARCHAR(2) DEFAULT 'TR'
   d. listings: + currency_code VARCHAR(3) DEFAULT 'TRY'
   e. listings: + listing_lang VARCHAR(5) DEFAULT 'tr'
   f. users: + country_code VARCHAR(2) DEFAULT 'TR'
   g. users: + currency_code VARCHAR(3) DEFAULT 'TRY'
   h. DROP INDEX ix_listings_province
   i. CREATE INDEX ix_listings_country
   j. CREATE INDEX ix_listings_country_state
   k. bump_schema_version()

2. alembic upgrade head

3. Backend model güncellemeleri:
   - listing.py: province→state_name, district→city_name, yeni alanlar
   - user.py: country_code, currency_code
   - Pydantic schema'lar

4. feed.py + listings.py router: country_code WHERE koşulları

5. feed:recent ZSET → feed:recent:{country_code} geçişi:
   - worker.py'de ilan oluşturma/silme noktaları güncellenir
   - Geçiş sonrası eski feed:recent key'i TTL ile expire bırakılır

6. price-signal endpoint: currency_code filtresi

7. trending tasks: country_code GROUP BY

8. ClickHouse migration:
   ALTER TABLE user_events        ADD COLUMN country_code LowCardinality(String) DEFAULT 'TR';
   ALTER TABLE feed_analytics     ADD COLUMN country_code LowCardinality(String) DEFAULT 'TR';
   ALTER TABLE search_events      ADD COLUMN country_code LowCardinality(String) DEFAULT 'TR';
   ALTER TABLE swipe_live_events  ADD COLUMN country_code LowCardinality(String) DEFAULT 'TR';

9. ClickHouse event yazma noktaları: country_code ekle
   - buffer_user_event(), buffer_search_event(), batch_insert_swipe_live_events()
   - POST /api/analytics/feed-batch

10. ARB güncelle → sync_translations.py → sudo systemctl restart teqlif

── MOBILE (sonra) ──────────────────────────────────────────────────────────────

11. scripts/build_geo_db.py çalıştır → mobile/assets/geo/geo.db üret

12. pubspec.yaml: sqflite + path ekle, assets/geo/geo.db ekle
    flutter pub get

13. mobile/lib/utils/country_flags.dart (flagEmoji util)
    mobile/lib/models/geo_models.dart
    mobile/lib/services/geo_service.dart

14. main.dart: GeoService.init() ekle (Hive.initFlutter() yanına)

15. register_screen.dart: country picker + AuthService payload

16. create_listing_screen.dart:
    - CityService çağrıları kaldır
    - GeoService cascade ekle
    - listing_lang dropdown
    - payload güncelle

17. listing_filter_state.dart: countryCode, stateName, cityName alanları
    teq_filter_sheet.dart: Country→State→City cascade

18. search_screen.dart (_HorizontalListingCard):
    - Konum badge ekle
    - Fiyat para birimi dinamik

19. listing_detail_screen.dart: province→state_name, district→city_name

── SONRAKI SPRINT (veri birikince) ────────────────────────────────────────────

20. _listing_embed_text: listing_lang prefix ekle
21. BPR eğitimi: country_code segmentasyonu
22. SwipeLive ALS: country_code filtresi
23. compute_user_interests_task: country_code filtresi
24. Embedding modeli: paraphrase-multilingual-MiniLM-L12-v2 geçişi (büyük migration)
```

---

## 16. Test Kontrol Listesi

**Geo DB:**
- [ ] `geo.db` tüm 250 ülke içeriyor
- [ ] Ülke seçimi → İl listesi doğru doluyor (TR → 81 il)
- [ ] İl seçimi → İlçe listesi doğru doluyor (İstanbul → 39 ilçe)
- [ ] Offline: uçak modunda picker çalışıyor
- [ ] `flagEmoji('TR')` → 🇹🇷, `flagEmoji('AE')` → 🇦🇪

**Signup:**
- [ ] Ülke seçilmeden form submit edilemiyor
- [ ] Ülke seçilince `country_code` + `currency_code` backend'e doğru gidiyor
- [ ] Mevcut kullanıcılar (country_code NULL/TR) bozulmuyor

**İlan Ver:**
- [ ] Kayıt sonrası `country_code`, `state_name`, `city_name` DB'de görünüyor
- [ ] `listing_lang` alanı DB'ye yazılıyor
- [ ] Ülke değişince İl sıfırlanıyor, İl değişince İlçe sıfırlanıyor

**Listing Card:**
- [ ] Mevcut ilanlar (state_name=NULL) konum satırı göstermiyor (graceful)
- [ ] Yeni Türk ilanı: `İstanbul 🇹🇷` gösteriyor
- [ ] `currency_code = 'AED'` olan ilan `د.إ` sembolüyle gösteriyor

**Feed:**
- [ ] Türk kullanıcı → sadece TR ilanları görüyor (varsayılan)
- [ ] Filtre ile ülke değiştirince farklı ülke ilanları geliyor
- [ ] `feed:recent:TR` ZSET dolup boşalıyor
- [ ] for-you feed `feed:foryou:{uid}:TR` key'ini kullanıyor
- [ ] Trending Türkiye için ayrı, BAE için ayrı çalışıyor

**ClickHouse:**
- [ ] `user_events.country_code` doluyor
- [ ] `feed_analytics.country_code` doluyor
- [ ] `search_events.country_code` doluyor

**Fiyat Sinyali:**
- [ ] `price-signal` endpoint farklı `currency_code`'ları karıştırmıyor

**Dil:**
- [ ] TR/EN/AR/RU tüm yeni labellar doğru görünüyor
- [ ] RTL: Arapça'da picker sağdan sola doğru hizalı

---

## 17. cross_border_consent_locale — KVKK Analizi

### 17.1 Mevcut Uygulama

`user.py` ve `auth.py` incelendiğinde, `cross_border_consent_locale` bir **KVKK madde 9 hukuki uyumluluk kaydıdır** — feed görünürlük kontrolü değil.

```python
cross_border_consent_given:      Mapped[bool]              # onay verildi mi?
cross_border_consent_at:         Mapped[Optional[datetime]] # ne zaman?
cross_border_consent_version:    Mapped[Optional[str]]      # sözleşme versiyonu (v1)
cross_border_consent_ip:         Mapped[Optional[str]]      # hangi IP'den?
cross_border_consent_locale:     Mapped[Optional[str]]      # kullanıcı onayı hangi dilde gördü?
cross_border_consent_revoked_at: Mapped[Optional[datetime]]
```

`register_screen.dart`'ta kayıt sırasında **zorunlu checkbox** olarak zaten aktif:

```dart
consentLocale: _crossBorderConsent ? loc.lang : null
// → cross_border_consent_locale'e yazılır
```

### 17.2 Gerçek Amacı

KVKK kapsamında kullanıcı verisi OVH US sunucularında işlenirken:
- Kullanıcının bilinçli onay verdiği ispat edilmeli
- Onayın hangi dilde gösterildiği kayıt altında tutulmalı (hukuki delil)
- Sözleşme versiyonu değişirse yeni onay alınmalı

### 17.3 Feed Görünürlüğü İçin Kullanılır mı?

**Hayır.** Feed filtresi `user.country_code` üzerinden gider (§11). Bu alan değiştirilmez.

### 17.4 Uluslararası Açılımda Yapılacak

Sözleşme metni yeni pazarlara göre güncellenirse `cross_border_consent_version` `v2`'ye çıkarılır ve login sırasında yeni onay istenir. Bu planın kapsamı dışında — ayrı hukuki görev.

---

## 18. ML / ClickHouse / AI Etki Analizi

### 18.1 Öncelik Matrisi

| Sistem | Sorun | Öncelik | Zamanlaması |
|--------|-------|---------|-------------|
| Feed sorguları | `country_code WHERE` yok | 🔴 Kritik | §15 / adım 4 |
| Fiyat sinyali | `currency_code` filtresi yok | 🔴 Kritik | §15 / adım 6 |
| feed:recent ZSET | Ülke karışımı | 🔴 Kritik | §15 / adım 5 |
| ClickHouse tabloları | `country_code` kolonu yok | 🟠 Yüksek | §15 / adım 8-9 |
| Trending | Global, ülke bazlı değil | 🟠 Yüksek | §15 / adım 7 |
| BPR eğitimi | Country segmentasyonu yok | 🟠 Yüksek | Sonraki sprint |
| compute_user_interests | Country filtresi yok | 🟡 Orta | Sonraki sprint |
| preference_embedding | Tüm ülke sinyalleri karışık | 🟡 Orta | BPR sonrası |
| SwipeLive ALS | Country filtresi yok | 🟡 Orta | Sonraki sprint |
| Item2Vec | Country sinyal gürültüsü | 🟡 Orta | Feed filtresiyle azalır |
| KMeans | Dil karışımı | 🟡 Orta | Veri birikince |
| Embedding modeli | İngilizce ağırlıklı | 🟡 Orta | MENA kullanıcı gelince |
| Turkish NLP stemmer | TR-only | 🟡 Orta | Çok dilli arama gerekince |

---

### 18.2 🔴 Kritik — Fiyat Sinyali

**Dosya:** `backend/app/routers/listings.py` — `GET /{listing_id}/price-signal`

`last_sold_price` kolonunda `currency_code` yok. 500 TRY ≠ 500 AED (≈ 4.500 TRY).

```python
# Eklenecek WHERE koşulu:
AND listings.currency_code = :target_currency_code
AND listings.status = 'sold'
```

Bu düzeltme listings tablosuna `currency_code` eklenince (§4.1) uygulanır.

---

### 18.3 🟠 Yüksek — ClickHouse Tabloları

Tablo şemaları (§2.3'ten). Her tabloya eklenecek:

```sql
ALTER TABLE user_events        ADD COLUMN country_code LowCardinality(String) DEFAULT 'TR';
ALTER TABLE feed_analytics     ADD COLUMN country_code LowCardinality(String) DEFAULT 'TR';
ALTER TABLE search_events      ADD COLUMN country_code LowCardinality(String) DEFAULT 'TR';
ALTER TABLE swipe_live_events  ADD COLUMN country_code LowCardinality(String) DEFAULT 'TR';
```

ClickHouse `ALTER TABLE ADD COLUMN` non-blocking; mevcut satırlar DEFAULT değeri alır.

**Event yazma noktaları:**
- `buffer_user_event()` → payload'a `country_code: user.country_code` ekle
- `buffer_search_event()` → payload'a `country_code` ekle
- `batch_insert_swipe_live_events()` → row'a `country_code` ekle
- `POST /api/analytics/feed-batch` → feed_analytics insert'e `country_code` ekle

---

### 18.4 🟠 Yüksek — BPR ve compute_user_interests

**BPR** (`backend/app/services/ml/bpr_service.py`, Pzt/Çar/Cum 03:00):

```sql
-- MEVCUT: tüm kullanıcı etkileşimleri karışık
WHERE interaction_type = ANY(ARRAY['listing_view', ...])

-- HEDEF: country_code bazlı segmentasyon
-- Yeterli veri gelene kadar: country_code feature olarak matrise dahil edilir
-- Yeterli veri sonrası: ülke başına ayrı model
```

**compute_user_interests_task** (`worker.py`, her 15 dakika):

```python
# Sinyal kaynakları: analytics_events, listing_likes, favorites, DM, swipelive_dwell
# Şu an tüm etkileşimler toplanıyor — ülke filtresi yok

# EKLENECEK: Kullanıcının country_code'uyla eşleşen listing'lerden gelen sinyaller
# → UserInterest tablosuna country_code kolonu eklenebilir (ileriki sprint)
```

---

### 18.5 🟡 Orta — SwipeLive ALS

**Dosya:** `backend/app/services/ml/swipe_live_ml.py` (her gece 03:15)

ClickHouse `swipe_live_events`'ten eğitim yapıyor. `country_code` kolonu eklenince stream öneri skoru ülke bazlı hesaplanabilir. Şimdi değil.

---

### 18.6 🟡 Orta — Embedding Modeli

**Dosya:** `backend/app/services/ml/ml_service.py`

```python
MODEL_NAME = "sentence-transformers/all-MiniLM-L6-v2"
# İngilizce ağırlıklı — Arapça için zayıf
```

**Kısa vade önlem** (`_listing_embed_text` — `worker.py`):

```python
def _listing_embed_text(listing) -> str:
    lang = (listing.listing_lang or 'tr').upper()
    prefix = f"[{lang}] "       # '[AR] ' — model bu işareti öğrenir
    parts = [prefix + (listing.title or ""), ...]
```

Bu iyileştirme `listing_lang` DB'ye yazıldıktan sonra (§15/adım 20) uygulanır.

**Uzun vade:** `paraphrase-multilingual-MiniLM-L12-v2` — 50 dil, Arapça/Rusça dahil. Büyük migration (embedding'lerin yeniden hesaplanması gerekir). Ayrı sprint.

---

### 18.7 🟡 Orta — Turkish NLP

**Dosya:** `backend/app/services/ml/turkish_nlp.py`

```python
_stemmer = snowballstemmer.stemmer("turkish")
```

`listing_lang`'a göre stemmer seçimi — Türkçe için mevcut, Arapça için Khoja stemmer, Rusça için Snowball Russian. Şimdi değil, çok dilli arama oluşunca.

---

### 18.8 ARQ Cron Task Özeti (Etkilenenler)

| Task | Zamanlama | Yapılacak Değişiklik |
|------|-----------|---------------------|
| `flush_interactions_to_db` | Her 5 dk | ClickHouse buffer'a `country_code` ekle |
| `compute_user_interests_task` | Her 15 dk | İleride: listing country_code filtresi |
| `compute_trending_listings_task` | Her 30 dk | country_code GROUP BY (§15/adım 7) |
| `compute_trending_categories_task` | 6 saatte bir | country_code GROUP BY |
| `populate_foryou_feed_task` | Saatte bir | for-you cache key'ine country_code |
| `train_bpr_task` | Pzt/Çar/Cum 03:00 | İleride: country segmentasyonu |
| `train_swipe_live_als_task` | Her gece 03:15 | İleride: country_code filtresi |
| `update_user_preference_embedding` | Flush tetikler | İleride: country bazlı sinyal |
