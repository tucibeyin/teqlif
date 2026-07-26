# İlan Filtreleme — Analiz ve Tasarım (v3)

---

## 0. Mevcut i18n Mimarisi (Kapsam Anlama)

```
backend/app/utils/i18n.py
  _get_t(lang)  →  mobile/lib/l10n/app_<lang>.arb  oku
                   (categories.py: t.get("cat_vehicles", c.label))

flutter: LocalizationService (Hive, i18n_cache)
  - Planlanmış OTA migration: T01-T30 todo list
  - Hedef: ARB dosyaları → DB translations tablosu → /api/i18n/{lang}
```

**Bu analiz o planın parçasıdır.** Kategori/subcategory/field label'ları
aynı i18n altyapısından geçer. Katalog ayrı endpointte sadece **yapı** döndürür;
label çözümlemesi `LocalizationService.t()` ile client tarafında yapılır.

---

## 1. Slug Birliği — Tek Gerçek Kaynak: DB

### Mevcut Sorun

| Konum | Slug Örnekleri | Durum |
|---|---|---|
| `categories.key` | `vehicles`, `electronics` | ✅ DB primary key |
| `category_fields.subcategory` | `automobile`, `mobile_phone` | ✅ DB'de var ama FK yok |
| `kSubcategories` (Dart) | `vehicles → automobile` mapping | ❌ Tek kaynak Flutter'da |
| Mock data (ClickHouse) | `vasita`, `otomobil` (Türkçe) | ⚠️ Mock veri hatası, production verisi doğru |

### Hedef Durum

```
DB:
  categories.key      →  "vehicles"          (İngilizce slug, değişmez)
  subcategories.key   →  "automobile"         (İngilizce slug, değişmez)
  subcategories.category_key  →  FK to categories.key

Flutter:
  kSubcategories      →  kaldırılır (CatalogService fallback olarak tutar)
  category_fields.subcategory  →  category_key kolonu eklenir

i18n (ARB / translations tablosu):
  "cat_vehicles"      →  TR: "Vasıta", EN: "Vehicles", ...
  "subcat_automobile" →  TR: "Otomobil", EN: "Automobile", ...
  "extraField_brand"  →  TR: "Marka", EN: "Brand", ...
```

### Gerekli DB Değişiklikleri

**1. `subcategories` tablosu (yeni Alembic migration):**
```sql
CREATE TABLE subcategories (
  key          VARCHAR(80) PRIMARY KEY,
  category_key VARCHAR(80) NOT NULL REFERENCES categories(key) ON DELETE CASCADE,
  sort_order   INTEGER DEFAULT 0,
  is_active    BOOLEAN DEFAULT TRUE
);
-- Backfill: kSubcategories mapping'inden 50 subcategory ekle
```

**2. `category_fields.category_key` kolonu:**
```sql
ALTER TABLE category_fields
  ADD COLUMN category_key VARCHAR(80) REFERENCES categories(key);
-- Backfill: subcategory → category_key mevcut mapping'den
-- Bu olmadan /api/catalog tam tree dönemez
```

**3. i18n label'ları (T05 — mevcut todo):**
```
translations tablosuna ekle (veya ARB dosyalarına):
  subcat_automobile, subcat_motorcycle, subcat_truck, ...  (≈50 key)
```

---

## 2. Etkilenen Ekranlar

### 2.1 Ana Listeleme (API-driven)

| Ekran | Mevcut | Hedef |
|---|---|---|
| `home_screen.dart` | Kategori ikonu şeridi + şehir chip | `ListingFilterBar` (tam set) |

### 2.2 Profil/İlan (Client-side)

| Ekran | Mevcut | Hedef |
|---|---|---|
| `profile_screen.dart` | `ListingFilter` accordion | `ListingFilterBar` |
| `public_profile_screen.dart` | Aynısı | `ListingFilterBar` |
| `sales_screen.dart` | Inline chip'ler | `ListingFilterBar` |

### 2.3 Pro Araçlar (Client-side analitik)

| Ekran | Mevcut | Hedef |
|---|---|---|
| `competitor_radar_screen.dart` | `String? _categoryFilter` + chip satırı | `ListingFilterBar` |
| `demand_trends_screen.dart` | `String? _selectedCategory` + chip satırı | `ListingFilterBar` |
| `pro_insights_screen.dart` | `_filterBar()` + `_filterChip()` inline | `ListingFilterBar` |

---

## 3. Mimari: Separation of Concerns

```
┌─────────────────────────────────────────────────────────────┐
│                        BACKEND                              │
│                                                             │
│  GET /api/catalog          GET /api/catalog/version         │
│  → YAPI döndür             → MD5(structure) döndür          │
│    categories.key                                           │
│    subcategories.key                                        │
│    category_fields (type, required, options.value)          │
│  (Label YOK — i18n ayrı)                                    │
│                                                             │
│  GET /api/i18n/{lang}      (mevcut plan: T07)               │
│  → flat JSON: { "cat_vehicles": "Vasıta", ... }             │
│    cat_*, subcat_*, extraField_*, opt_*                      │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                        FLUTTER                              │
│                                                             │
│  CatalogService (Hive: catalog_cache)                       │
│  ├─ categories[]    ← /api/catalog (yapı)                   │
│  ├─ subcategories[] ← içinde                                │
│  └─ fields[]        ← içinde                                │
│                                                             │
│  LocalizationService (Hive: i18n_cache)  ← MEVCUT          │
│  ├─ t("cat_vehicles")      → "Vasıta"                       │
│  ├─ t("subcat_automobile") → "Otomobil"                     │
│  └─ t("extraField_brand")  → "Marka"                        │
│                                                             │
│  Label çözümleme: t("cat_" + category.key)                  │
│                   t("subcat_" + subcategory.key)             │
│                   t(field.labelKey)  (zaten böyle)          │
└─────────────────────────────────────────────────────────────┘
```

**Neden ikisi ayrı?**
- Çeviri değiştiğinde katalog yeniden indirilmez (ve tersi)
- `CatalogService` sadece yapısal değişimlerde (yeni kategori/alan) güncellenir
- `LocalizationService` sadece metin değişimlerinde güncellenir
- İkisi de Hive'da, her ikisi de version-checked background refresh ile

---

## 4. Backend: `/api/catalog` Endpoint

```
GET /api/catalog
Accept-Language: tr   (veya user.locale)

Response 200:
{
  "version": "a3f2c8d1",
  "categories": [
    {
      "key": "vehicles",
      "sort_order": 1,
      "subcategories": [
        {
          "key": "automobile",
          "sort_order": 1,
          "fields": [
            {
              "key": "brand",
              "label_key": "extraField_brand",
              "type": "dropdown",
              "required": true,
              "options": [
                { "value": "bmw", "label_key": "opt_bmw" },
                { "value": "mercedes", "label_key": "opt_mercedes" }
              ]
            },
            {
              "key": "model",
              "label_key": "extraField_model",
              "type": "dropdown",
              "required": true,
              "depends_on": "brand",
              "options": [...]
            }
          ]
        }
      ]
    }
  ]
}

GET /api/catalog/version
→ { "version": "a3f2c8d1" }
```

**Backend cache:** Redis 24h (`cache:catalog`)
**Version:** MD5 of categories + subcategories + category_fields + field_options row count + updated_at max

**DİKKAT:** Response'ta label string yok, sadece `label_key`. Label çözümlemesi Flutter'da `t(label_key)` ile yapılır.

---

## 5. Flutter: `CatalogService`

**Dosya:** `mobile/lib/services/catalog_service.dart`
**Hive box:** `catalog_cache`
**Açılış stratejisi:** LocalizationService ile özdeş

```
App açılış (main.dart):
  1. CatalogService.readCacheSync()   → Hive'dan anında yükle (0ms)
  2. runApp()
  3. Arka planda: CatalogService.checkAndRefresh()
       → GET /api/catalog/version
       → cached_version != server_version ?
           → GET /api/catalog → Hive güncelle → notifier emit
```

**API (public):**
```dart
class CatalogService {
  // Senkron getterlar (Hive'dan — her zaman anında)
  static List<CatalogCategory> get categories;
  static List<CatalogSubcategory> subcategoriesFor(String categoryKey);
  static List<ExtraFieldDef>    fieldsFor(String subcategoryKey);
  static bool get isReady;

  // Async (açılış + arka plan refresh)
  static Future<void> init();                // main()'de await
  static Future<void> checkAndRefresh();     // arka planda

  // Fallback — CatalogService boşsa kSubcategories'e düşer
}
```

**Fallback zinciri (geriye dönük uyumluluk):**
```
CatalogService.fieldsFor(sub)
  → isReady ? _catalog[sub].fields : FieldConfigService.getFields(sub)
    → HTTP /api/field-config/{sub} : kSubcategoryFields[sub]

CatalogService.subcategoriesFor(cat)
  → isReady ? _catalog[cat].subcats : kSubcategories[cat]
```

---

## 6. Flutter: `ListingFilterState` — Veri Modeli

**Dosya:** `mobile/lib/models/listing_filter_state.dart`

```dart
class ListingFilterState {
  final String? category;         // 'vehicles'
  final String? subcategory;      // 'automobile'
  final String? city;             // 'İstanbul'
  final String? condition;        // 'new' | 'used' | 'damaged'
  final String? sortBy;           // 'newest' | 'price_asc' | 'price_desc'
  final double? minPrice;
  final double? maxPrice;
  final Map<String, dynamic> extraFields;  // {brand:'bmw', year:2020}

  bool get isEmpty;
  int  get activeCount;   // aktif filtre sayısı (badge için)

  ListingFilterState copyWith({...});
  ListingFilterState clearAll() => const ListingFilterState();
}
```

> **`searchQuery` bu modele girmez** — arama kutusu her ekranda zaten ayrıdır.

---

## 7. Flutter: `ListingFilterBar` — Tetikleyici Widget

**Dosya:** `mobile/lib/widgets/listing_filter_bar.dart`

```
┌─────────────────────────────────────────────────────────────┐
│  🔍  İlan başlığı veya açıklamada ara...              [✕]   │
│  [🎛 Filtrele (3) ▼]                [✕ Temizle]            │
└─────────────────────────────────────────────────────────────┘
```

```dart
class ListingFilterBar extends StatelessWidget {
  const ListingFilterBar({
    required this.searchCtrl,
    required this.appliedFilter,
    required this.onSearchChanged,
    required this.onSearchCleared,
    required this.onFilterApplied,
    this.onFilterCleared,
    this.showCategory    = true,
    this.showSubcategory = true,
    this.showExtraFields = true,
    this.showCity        = true,
    this.showCondition   = true,
    this.showSort        = false,
    this.showPriceRange  = false,
    this.showSearchBar   = true,
  });
}
```

---

## 8. Flutter: `ListingFilterSheet` — Bottom Sheet Modal

**Dosya:** `mobile/lib/widgets/listing_filter_sheet.dart`

```
┌─────────────────────────────────────────────────────────────┐
│  ─── (drag handle)                            [✕ Kapat]    │
│  Filtrele                                                    │
├─────────────────────────────────────────────────────────────┤
│  KATEGORİ                                                   │
│  [🚗 Vasıta] [📱 Elektronik] [🏠 Emlak] [...]              │
│                                                             │
│  ALT KATEGORİ  (AnimatedSize — kategori seçince açılır)    │
│  [Otomobil] [Motosiklet] [Kamyonet] [Kamyon] [...]         │
│                                                             │
│  DETAY FİLTRELER  (AnimatedSize — subcategory seçince)     │
│  CatalogService.fieldsFor(sub) → anında, HTTP yok           │
│  Marka  [BMW ▼]   Model [3 Serisi ▼]   Yıl [2020 ▼]       │
│                                                             │
│  ŞEHİR      [📍 İstanbul ▼]                                 │
│  DURUM      [Tümü] [Sıfır] [İkinci El] [Hasarlı]           │
│  FİYAT      Min [___] TL    Max [___] TL                   │
│  SIRALAMA   [En Yeni] [Ucuzdan] [Pahalıdan]                │
│                                                             │
├─────────────────────────────────────────────────────────────┤  STICKY
│  [Filtreyi Temizle]        [   Filtre Uygula (3)         ]  │
└─────────────────────────────────────────────────────────────┘
```

**Davranış:**
1. Modal açılınca `appliedFilter`'ı kopyalar → pending state
2. Kategori değişince: subcategory + extra fields sıfırlanır
3. Subcategory değişince: extra fields sıfırlanır, `CatalogService.fieldsFor()` senkron çağrılır
4. "Filtre Uygula" → `onApplied(pending)` callback, modal kapanır
5. Backdrop tıklama → pending atılır, applied değişmez
6. Label'lar: `t("cat_" + key)`, `t("subcat_" + key)`, `t(field.labelKey)`

---

## 9. Ekran Kullanım Tablosu

| Ekran | cat | sub | extra | city | cond | sort | price | mod |
|---|---|---|---|---|---|---|---|---|
| `home_screen` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | API |
| `profile_screen` | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | local |
| `public_profile_screen` | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | local |
| `sales_screen` | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | local |
| `competitor_radar` | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | local |
| `demand_trends` | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | local |
| `pro_insights` | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | local |

---

## 10. `create_listing_screen` + `edit_listing_screen` Etkisi

```dart
// ÖNCE — kSubcategories Dart sabiti
final subcats = kSubcategories[_selectedCategory] ?? [];

// SONRA — DB'den Hive cache ile
final subcats = CatalogService.subcategoriesFor(_selectedCategory ?? '');

// ÖNCE — Her subcategory seçiminde HTTP isteği + await
final fields = await FieldConfigService.getFields(_selectedSubcategory);

// SONRA — Senkron, bekleme yok
final fields = CatalogService.fieldsFor(_selectedSubcategory ?? '');
```

---

## 11. Uygulama Sırası (FAZ'lar)

### FAZ 0 — DB Altyapı

| # | İş |
|---|---|
| DB-1 | `subcategories` tablosu + backfill (≈50 kayıt) |
| DB-2 | `category_fields.category_key` kolonu + backfill |
| DB-3 | `subcat_*` label key'leri ARB / translations'a ekle (T05 ile birleşir) |

### FAZ 1 — Backend Catalog Endpoint

| # | İş |
|---|---|
| C-1 | `routers/catalog.py` — `GET /api/catalog/version` + `GET /api/catalog` |
| C-2 | Redis 24h cache + cache key stratejisi |
| C-3 | `main.py` router kaydı + VPS deploy + curl test |

### FAZ 2 — Flutter CatalogService

| # | İş |
|---|---|
| F-1 | `models/catalog.dart` — Hive adapter'lı model sınıfları |
| F-2 | `services/catalog_service.dart` — init, readCacheSync, checkAndRefresh |
| F-3 | `main.dart` entegrasyonu |
| F-4 | `FieldConfigService` delegation güncelle |

### FAZ 3 — Filtre Componentleri

| # | İş |
|---|---|
| W-1 | `models/listing_filter_state.dart` |
| W-2 | `widgets/listing_filter_sheet.dart` |
| W-3 | `widgets/listing_filter_bar.dart` |

### FAZ 4 — Listing Ekranları Migration (create/edit)

| # | İş |
|---|---|
| M-1 | `create_listing_screen.dart` — kSubcategories + FieldConfigService → CatalogService |
| M-2 | `edit_listing_screen.dart` — aynı |

### FAZ 5 — Tüm Diğer Ekranlar Migration

| # | Ekran |
|---|---|
| E-1 | `home_screen.dart` |
| E-2 | `profile_screen.dart` + `public_profile_screen.dart` |
| E-3 | `sales_screen.dart` |
| E-4 | `competitor_radar_screen.dart` |
| E-5 | `demand_trends_screen.dart` |
| E-6 | `pro_insights_screen.dart` |

---

## 12. Yeni Dosyalar

```
backend/app/
  routers/catalog.py
  migrations/xxx_subcategories_and_category_key.py

mobile/lib/
  models/
    catalog.dart
    listing_filter_state.dart
  services/
    catalog_service.dart
  widgets/
    listing_filter_bar.dart
    listing_filter_sheet.dart
```

---

## 13. Silinen / Değiştirilen Kod

| Dosya | Değişim |
|---|---|
| `listing_fields.dart:kSubcategories` | Fallback olarak kalır, artık primary kaynak değil |
| `home_screen.dart` kategori şeridi | `ListingFilterBar` ile değişir |
| `profile_screen.dart: ListingFilter` + iç sınıfları | Silinir |
| `public_profile_screen.dart` | Aynısı |
| `sales_screen.dart` inline filtre | `ListingFilterBar` |
| `competitor_radar_screen.dart` chip satırı | `ListingFilterBar` |
| `demand_trends_screen.dart` chip satırı | `ListingFilterBar` |
| `pro_insights_screen.dart: _filterBar()` | `ListingFilterBar` |

---

## 14. Kapsam Dışı

| | Neden |
|---|---|
| `search_screen.dart` | Explore + semantic search, ayrı domain |
| `pro_insights` analitik filtreler (tarih, fiyat sinyali) | Farklı domain |
| `retargeting_screen.dart` | İlan seçme, filtreleme değil |
