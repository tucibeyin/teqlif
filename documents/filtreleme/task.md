# İlan Filtreleme — Task Listesi

Kaynak: `analiz.md` v3 — tüm FAZ'ların uygulama adımları.

---

## FAZ 0 — DB Altyapı

- [x] **DB-1** — `subcategories` tablosu Alembic migration yaz: `key`, `category_key` (FK → categories), `sort_order`, `is_active`
- [x] **DB-2** — `subcategories` backfill: `kSubcategories` Dart sabitindeki 59 kayıt SQL INSERT'e dönüştür
- [x] **DB-3** — `category_fields.category_key` kolonu Alembic migration yaz (ALTER TABLE + backfill)
- [x] **DB-3b** — `category_fields.subcategory` Türkçe slug'ları İngilizce'ye rename et (48 rename) — `aaa_slug_unification.py`
- [x] **DB-3c** — `category_fields.key` / `label_key` / `depends_on` Türkçe → İngilizce rename (45 field key rename)
- [x] **DB-4** — `subcat_*` label key'leri ARB dosyalarında zaten mevcut (59 key, 4 dil) — ek iş gerekmedi
- [x] **DB-5** — VPS'te migration çalıştır, `subcategories` tablosunu verify et (59 subcat, automobile→brand/year/mileage doğrulandı)

---

## FAZ 1 — Backend Catalog Endpoint

- [x] **C-1** — `backend/app/routers/catalog.py` oluşturuldu
- [x] **C-2** — `GET /api/catalog/version` endpoint: MD5 hash of full catalog JSON
- [x] **C-3** — `GET /api/catalog` endpoint: tam ağaç, sadece `label_key` (label string yok)
- [x] **C-4** — Redis 24h cache (`@cache(expire=86400)`) her iki endpoint'e eklendi
- [x] **C-4b** — `models/subcategory.py` + `alembic/env.py` import eklendi
- [x] **C-5** — `main.py`'a `catalog.router` kaydı eklendi
- [x] **C-6** — VPS deploy + curl testi: version=a600a069, 9 cat, 59 subcat doğrulandı

---

## FAZ 2 — Flutter CatalogService

- [x] **F-1** — `mobile/lib/models/catalog.dart`: `CatalogCategory`, `CatalogSubcategory`, `CatalogField`, `CatalogOption` — JSON string Hive, TypeAdapter yok
- [x] **F-2** — `mobile/lib/services/catalog_service.dart`: `initBox()`, `readCacheSync()`, `checkAndRefresh()`, `subcategoriesFor()`, `fieldsFor()` — kSubcategories fallback dahil
- [x] **F-3** — Fallback: `subcategoriesFor()` → `kSubcategories[cat]`; `fieldsFor()` → null döner, caller FieldConfigService'e düşer
- [x] **F-4** — `main.dart`: `CatalogService.initBox()` + `readCacheSync()` + `checkAndRefresh().ignore()` eklendi
- [x] **F-5** — `field_config_service.dart`: `CatalogService.isReady` ise HTTP atlamadan delegate et; `_fromCatalog()` ile `CatalogField` → `ExtraFieldDef` dönüşümü

---

## FAZ 3 — Filtre Componentleri

- [x] **W-1** — `mobile/lib/models/listing_filter_state.dart` yaz: `category`, `subcategory`, `city`, `condition`, `sortBy`, `minPrice`, `maxPrice`, `extraFields` + `isEmpty`, `activeCount`, `copyWith`, `clearAll`
- [x] **W-2** — `mobile/lib/widgets/listing_filter_sheet.dart` yaz: DraggableScrollableSheet, kategori şerit, subcategory şerit (AnimatedSize), extra field'lar (AnimatedSize), şehir, durum, fiyat aralığı, sıralama, sticky footer
- [x] **W-3** — `ListingFilterSheet`: pending state davranışı — kategori değişince subcategory+extraFields sıfırla; subcategory değişince extraFields sıfırla
- [x] **W-4** — `ListingFilterSheet`: label'lar `t("cat_" + key)`, `t("subcat_" + key)`, `t(field.labelKey)` — LocalizationService üzerinden
- [x] **W-5** — `mobile/lib/widgets/listing_filter_bar.dart` yaz: arama satırı + "Filtrele (N)" butonu + "Temizle" butonu; feature flag parametreleri (`showCategory`, `showSubcategory`, `showExtraFields`, `showCity`, `showCondition`, `showSort`, `showPriceRange`, `showSearchBar`)

---

## FAZ 4 — create_listing + edit_listing Migration

- [x] **M-1** — `create_listing_screen.dart`: `kSubcategories[_selectedCategory]` → `CatalogService.subcategoriesFor(_selectedCategory ?? '')`
- [x] **M-2** — `field_config_service.dart`'ta `_fromCatalog()` delegate; `getFields()` CatalogService.isReady ise HTTP yerine önbellek kullanır
- [x] **M-3** — `edit_listing_screen.dart`: kSubcategories/FieldConfigService kullanmıyordu — değişiklik gerekmedi
- [ ] **M-4** — Manuel test: ilan oluşturma + düzenleme akışı, subcategory seçiminde bekleme olmadığını doğrula

---

## FAZ 5 — Ekran Migration'ları

- [x] **E-1** — `home_screen.dart`: kategori ikonu şeridi + şehir chip + filtre chip satırını kaldır; `ListingFilterBar(showSort: true, showPriceRange: true, showCity: true, showCondition: true)` ekle; API çağrısını `ListingFilterState`'e bağla
- [x] **E-2** — `profile_screen.dart`: `ListingFilter` widget'ı + `_ListingFilterState` + `_CategoryChip` iç sınıflarını sil; `ListingFilterBar(showSubcategory: true, showCity: false, showCondition: false)` ekle
- [x] **E-3** — `public_profile_screen.dart`: aynı değişiklik
- [x] **E-4** — `sales_screen.dart`: inline filtre chip'lerini sil; `ListingFilterBar(showSubcategory: false, showCity: false, showCondition: false)` ekle
- [x] **E-5** — `competitor_radar_screen.dart`: `_categoryFilter` + chip satırını kaldır; `ListingFilterBar(showSubcategory: false, showCity: false, showCondition: false, showSearchBar: false)` ekle
- [x] **E-6** — `demand_trends_screen.dart`: `_selectedCategory` + chip satırını kaldır; `ListingFilterBar(showSubcategory: false, showCity: false, showCondition: false, showSearchBar: false)` ekle
- [x] **E-7** — `pro_insights_screen.dart`: `_filterBar()` + `_filterChip()` metodlarını sil; `ListingFilterBar(showSubcategory: false, showCity: false, showCondition: false, showSearchBar: false)` ekle
- [ ] **E-8** — Tüm ekranlarda manuel test: filtre uygula → temizle → sonuçlar doğru mu

---

## Bağımlılık Sırası

```
DB-1 → DB-2 → DB-3 → DB-4 → DB-5
                                 ↓
                        C-1 → C-6
                                 ↓
                        F-1 → F-6
                                 ↓
                        W-1 → W-5
                          ↓
               M-1 → M-4   E-1 → E-8
```
