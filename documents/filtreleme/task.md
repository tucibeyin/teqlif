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
- [ ] **DB-5** — VPS'te migration çalıştır, `subcategories` tablosunu verify et

---

## FAZ 1 — Backend Catalog Endpoint

- [ ] **C-1** — `backend/app/routers/catalog.py` dosyası oluştur
- [ ] **C-2** — `GET /api/catalog/version` endpoint: categories + subcategories + category_fields satır sayısı + max updated_at → MD5 hash
- [ ] **C-3** — `GET /api/catalog` endpoint: tam ağaç döndür (categories → subcategories → fields → options), sadece `label_key` (label string yok)
- [ ] **C-4** — Redis 24h cache ekle (`cache:catalog`)
- [ ] **C-5** — `main.py`'a catalog router kaydını ekle
- [ ] **C-6** — VPS deploy + curl ile her iki endpoint'i test et

---

## FAZ 2 — Flutter CatalogService

- [ ] **F-1** — `mobile/lib/models/catalog.dart` yaz: `CatalogCategory`, `CatalogSubcategory`, `CatalogField`, `CatalogOption` — Hive TypeAdapter'lı
- [ ] **F-2** — `mobile/lib/services/catalog_service.dart` yaz: `init()`, `readCacheSync()`, `checkAndRefresh()`, senkron getterlar (`categories`, `subcategoriesFor()`, `fieldsFor()`)
- [ ] **F-3** — Fallback zinciri ekle: `CatalogService.fieldsFor()` → `FieldConfigService.getFields()` → `kSubcategoryFields`
- [ ] **F-4** — Fallback zinciri ekle: `CatalogService.subcategoriesFor()` → `kSubcategories`
- [ ] **F-5** — `main.dart`: Hive box `catalog_cache` aç + `CatalogService.init()` + `CatalogService.readCacheSync()` sıralamasını LocalizationService ile eş tut
- [ ] **F-6** — `field_config_service.dart`: `CatalogService.isReady` kontrolü ekle, hazırsa HTTP yapmadan CatalogService'e delegate et

---

## FAZ 3 — Filtre Componentleri

- [ ] **W-1** — `mobile/lib/models/listing_filter_state.dart` yaz: `category`, `subcategory`, `city`, `condition`, `sortBy`, `minPrice`, `maxPrice`, `extraFields` + `isEmpty`, `activeCount`, `copyWith`, `clearAll`
- [ ] **W-2** — `mobile/lib/widgets/listing_filter_sheet.dart` yaz: DraggableScrollableSheet, kategori şerit, subcategory şerit (AnimatedSize), extra field'lar (AnimatedSize), şehir, durum, fiyat aralığı, sıralama, sticky footer
- [ ] **W-3** — `ListingFilterSheet`: pending state davranışı — kategori değişince subcategory+extraFields sıfırla; subcategory değişince extraFields sıfırla
- [ ] **W-4** — `ListingFilterSheet`: label'lar `t("cat_" + key)`, `t("subcat_" + key)`, `t(field.labelKey)` — LocalizationService üzerinden
- [ ] **W-5** — `mobile/lib/widgets/listing_filter_bar.dart` yaz: arama satırı + "Filtrele (N)" butonu + "Temizle" butonu; feature flag parametreleri (`showCategory`, `showSubcategory`, `showExtraFields`, `showCity`, `showCondition`, `showSort`, `showPriceRange`, `showSearchBar`)

---

## FAZ 4 — create_listing + edit_listing Migration

- [ ] **M-1** — `create_listing_screen.dart`: `kSubcategories[_selectedCategory]` → `CatalogService.subcategoriesFor(_selectedCategory ?? '')`
- [ ] **M-2** — `create_listing_screen.dart`: `await FieldConfigService.getFields(_selectedSubcategory)` → `CatalogService.fieldsFor(_selectedSubcategory ?? '')` (senkron, setState güncelle)
- [ ] **M-3** — `edit_listing_screen.dart`: aynı iki değişiklik
- [ ] **M-4** — Manuel test: ilan oluşturma + düzenleme akışı, subcategory seçiminde bekleme olmadığını doğrula

---

## FAZ 5 — Ekran Migration'ları

- [ ] **E-1** — `home_screen.dart`: kategori ikonu şeridi + şehir chip + filtre chip satırını kaldır; `ListingFilterBar(showSort: true, showPriceRange: true, showCity: true, showCondition: true)` ekle; API çağrısını `ListingFilterState`'e bağla
- [ ] **E-2** — `profile_screen.dart`: `ListingFilter` widget'ı + `_ListingFilterState` + `_CategoryChip` iç sınıflarını sil; `ListingFilterBar(showSubcategory: true, showCity: false, showCondition: false)` ekle
- [ ] **E-3** — `public_profile_screen.dart`: aynı değişiklik
- [ ] **E-4** — `sales_screen.dart`: inline filtre chip'lerini sil; `ListingFilterBar(showSubcategory: false, showCity: false, showCondition: false)` ekle
- [ ] **E-5** — `competitor_radar_screen.dart`: `_categoryFilter` + chip satırını kaldır; `ListingFilterBar(showSubcategory: false, showCity: false, showCondition: false, showSearchBar: false)` ekle
- [ ] **E-6** — `demand_trends_screen.dart`: `_selectedCategory` + chip satırını kaldır; `ListingFilterBar(showSubcategory: false, showCity: false, showCondition: false, showSearchBar: false)` ekle
- [ ] **E-7** — `pro_insights_screen.dart`: `_filterBar()` + `_filterChip()` metodlarını sil; `ListingFilterBar(showSubcategory: false, showCity: false, showCondition: false, showSearchBar: false)` ekle
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
