# ML / Tracking / ClickHouse — Görev Listesi

**Plan:** `PLAN.md`
**Kural:** FAZ 1 tamamlanmadan FAZ 2'ye geçilmez. FAZ 6 (ML model güncellemeleri) için minimum 2 hafta veri birikimi şart.

---

## FAZ 1 — Temel: Veri Toplama Altyapısı

### ClickHouse DDL

- [x] **T01** — `feed_analytics` tablosuna `listing_subcategory LowCardinality(String) DEFAULT ''` sütunu ekle
  - `database_clickhouse.py` DDL + ALTER + `batch_insert_feed_analytics` güncellendi

- [x] **T02** — `search_events` tablosuna `subcategory LowCardinality(String) DEFAULT ''` sütunu ekle
  - DDL + ALTER + `buffer_search_event()` imzasına `subcategory: str = ''` eklendi

- [x] **T03** — `user_events`'e `subcategory LowCardinality(String) DEFAULT ''` ek sütun olarak eklendi
  - `metadata` kaldırılmadı; `buffer_user_event()` imzasına `subcategory: str = ''` eklendi
  - Redis row sonuna append (backward compat — eski satırlar 7-elemanlı, yeniler 8-elemanlı)

- [x] **T04** — `swipe_live_events` tablosuna `stream_subcategory` ve `listing_subcategory` eklendi
  - DDL + ALTER + `batch_insert_swipe_live_events()` güncellendi

- [x] **T05** — VPS deploy tamamlandı
  - `aaa_live_streams_subcategory` migration uygulandı (live_streams.subcategory)
  - `aab_merge_streams_and_loc` merge migration uygulandı
  - ClickHouse ALTER TABLE'lar servis başlangıcında init_clickhouse() içinde otomatik çalıştı

### Embedding Zenginleştirme

- [x] **T06** — `worker.py:_listing_embed_text()` fonksiyonunu güncelle
  - `_EMBED_EXTRA_KEYS` tuple (45+ key) + subcategory ile zenginleştirildi
  - Boş/None değerler sessizce atlanır

- [x] **T07** — `backfill_listing_embeddings_task` enqueue edildi (job: 81ae367701384dc0ad5e6a275db51672)
  - Worker arka planda tüm aktif ilanları yeni `_EMBED_EXTRA_KEYS` ile yeniden embed ediyor

### SwipeLive — LiveStream Modeli

- [x] **T08** — Alembic migration: `live_streams.subcategory VARCHAR(100) NULL`
  - `aaa_live_streams_subcategory.py` oluşturuldu; `down_revision = 'zz_hasar_vasita_all'`
  - `backend/app/models/stream.py`'a `subcategory: Mapped[Optional[str]]` eklendi

- [x] **T09** — `StreamStart` + `StreamOut` şemalarına `subcategory: Optional[str] = None` eklendi
  - `schemas/stream.py` güncellendi
  - `routers/streams.py` → `start_stream` endpoint'inde `body.subcategory` DB'ye yazılıyor (aşağıda doğrulandı)

---

## FAZ 2 — Mobile → Backend Sinyal Akışı

### Schema Güncelleme

- [x] **T10** — `schemas/analytics.py: FeedEventCreate`'e `listing_subcategory: str = Field(default="")` eklendi

- [x] **T11** — `schemas/analytics.py: SearchEventCreate`'e `subcategory: str = Field(default="")` eklendi

### Mobile: Feed Telemetry

- [x] **T12** — `feed_telemetry_service.dart: logEvent()` imzasına `listingSubcategory` eklendi
  - Payload dict'e `'listing_subcategory': listingSubcategory` eklendi

- [x] **T13** — `swipe_live_screen.dart: _recordListingEvent()` bug fix
  - `listing_category` artık listingCategory parametresinden okunuyor (hard-coded '' değil)
  - `listing_subcategory` ve `stream_subcategory` eklendi
  - `StreamOut` mobil modeline `subcategory` alanı eklendi
  - `_onPageChanged`, `_stopAndLog`, `_goToListing` çağrı siteleri güncellendi

- [x] **T14** — `search_screen.dart` logEvent impression/click çağrılarına `listingSubcategory` eklendi

### Mobile: Analytics Service

- [x] **T15** — `analytics_service.dart: trackSearch()`'e `subcategory` parametresi eklendi
  - Body'ye `'subcategory': subcategory` eklendi

- [ ] **T16** — `analytics_service.dart: getPriceEstimate()`'e `subcategory`, `extraFields` (km, year, fuel_type) parametresi ekle
  - Backend `/price-estimate` endpoint'ine bu parametreler geçirilsin

- [ ] **T17** — `analytics_service.dart: logInteraction()`'da `metadata` dict'e subcategory ekle
  - Her çağrı sitesinde listing'in subcategory'si varsa metadata'ya ekle

---

## FAZ 3 — Backend: Yazma Tarafı

- [x] **T18** — `routers/analytics.py: /feed-events` ingest endpoint'i güncellendi
  - `e.listing_subcategory` row'a eklendi; `column_names`'e `"listing_subcategory"` eklendi

- [x] **T19** — `routers/analytics.py: /search-events` ingest endpoint'i güncellendi
  - `buffer_search_event()` çağrısına `subcategory=body.subcategory` eklendi

- [x] **T20** — `routers/analytics.py: SwipeLiveEventItem`'a `stream_subcategory` + `listing_subcategory` eklendi
  - `events` dict'e her iki alan da eklendi; `batch_insert_swipe_live_events()` zaten hazırdı

- [x] **T21** — `use_cases/listings/queries/get_swipe_feed.py`'a `subcategory` eklendi

- [x] **T22** — `listing_utils.py: _row_dict()`'e `subcategory` ve `extra_fields` eklendi

---

## FAZ 4 — Feed & Öneri Algoritmaları

- [x] **T23** — `user_interests` tablosuna subcategory sütunu ekle (Alembic migration)
  - `aac_user_interests_subcategory.py` oluşturuldu; `down_revision = 'aab_merge_streams_and_loc'`
  - `user_interest.py` modeline `subcategory: Mapped[Optional[str]]` + index eklendi

- [x] **T24** — `use_cases/feed/queries/feed_queries.py` güncellendi
  - `get_user_interests()` → `WHERE subcategory IS NULL` (top-level)
  - `get_user_subcategory_interests()` → `WHERE subcategory IS NOT NULL`, `"category|subcategory": score`

- [x] **T25** — `feed_queries.py: _score_and_rank()` scoring SQL güncellendi
  - `subcat_affinity_expr` CASE ifadesi (top-8 subcategory, `l.category || '|' || COALESCE(l.subcategory,'')`)
  - `subcat_w = 0.08`; `cat_w` 0.30→0.22 (embedding), 0.40→0.32 (no embedding) olarak azaltıldı

- [x] **T26** — `feed_queries.py: greedy diversity` güncellendi
  - `MAX_PER_SUBCAT = 2` — `(category, subcategory)` çifti başına limit
  - `subcat_counts` dict'i ile takip edilir; overflow havuzuna düşer

- [x] **T27** — `recommendation_service.py` güncellendi
  - `get_user_subcategory_affinity()` fonksiyonu eklendi (ClickHouse + PostgreSQL)
  - `_ids_from_categories()` → `subcategories: Optional[list[str]]` + fallback mantığı
  - `get_personalized_feed()` → top subcategory bilgisi exploit pool'a geçirildi

- [x] **T28** — `swipe_live_queries.py: _score_stream()` güncellendi
  - `subcat_interests` parametresi eklendi; `subcat_key = "category|subcategory"` eşleşmesi
  - Fallback: subcategory skoru yoksa top-level category skoru kullanılır

- [x] **T29** — `swipe_live_queries.py: _fetch_listing_stream_correlation()` güncellendi
  - `stream_subcategory` GROUP BY'a eklendi; `subcat_interests` ile ağırlıklandırma

- [x] **T30** — `get_swipe_feed.py: GetSwipeFeedQuery` güncellendi
  - `preferred_categories` parametresi eklendi → SQLAlchemy `case()` ile öncelik sıralaması
  - `/swipe-feed` router: auth optional → interests → preferred_categories geçirilir

---

## FAZ 5 — Analytics Endpoint'leri

- [ ] **T31** — `routers/analytics.py: /price-estimate` güncelle
  - Kandidat SQL'e `AND (:subcat = '' OR l.subcategory = :subcat)` ekle
  - NER çarpanlarına `km`, `year`, `fuel_type` ekle
  - Mobile `getPriceEstimate()` çağrısı (T16) ile koordineli

- [ ] **T32** — `routers/analytics.py: /competitor-radar/{listing_id}` güncelle
  - Fallback sorgu: `WHERE category = :cat AND subcategory = :subcat`
  - Embedding sorgusu: subcategory filtresi ile daralt (subcategory yoksa category ile fallback)

- [ ] **T33** — `routers/analytics.py: /category-velocity` endpoint'ine subcategory parametresi ekle
  - `WHERE l.category = :cat AND (:subcat = '' OR l.subcategory = :subcat)`

- [ ] **T34** — ClickHouse `search_events` subcategory sütunu (T02) dolmaya başladıktan sonra:
  - `/demand-radar` ve `/demand-trends` endpoint'lerine subcategory `GROUP BY` ekle
  - Minimum 1 hafta veri birikmesi beklenir

- [ ] **T35** — `search.py: SearchListingsQuery`'ye `subcategory` filtresi ekle
  - `Listing.subcategory == subcategory` — opsiyonel parametre
  - GIN index kullanan extra_fields JSONB filtresi: `extra_fields @> '{"fuel_type": "gasoline"}'::jsonb`

---

## FAZ 6 — ML Model Güncellemeleri *(Minimum 2 Hafta Veri Birikmesi Şart)*

- [ ] **T36** — `kmeans_service.py` cluster profili güncelle
  - `SELECT id, embedding, category, subcategory FROM listings`
  - `cat_profiles`: `{(category, subcategory): fraction}` — tuple key
  - `get_cold_start_embedding()`: subcategory bazlı ağırlık hesabı

- [ ] **T37** — `quality_service.py: extract_features()` güncelle
  - extra_fields completeness sinyalleri ekle:
    - Araç: `has_km`, `has_year`, `has_fuel_type`, `has_gear` (bool)
    - Gayrimenkul: `has_room_count`, `has_size`, `has_floor` (bool)
    - Elektronik: `has_ram`, `has_processor` (bool)
  - `_rule_based_score()` completeness bonus ekle: dolu her alan +0.5 puan
  - `train_quality_model()` sorgusuna `l.subcategory`, `l.extra_fields` ekle

- [ ] **T38** — `feed_als_ml.py` ALS eğitimini güncelle
  - `feed_analytics` sorgusuna `listing_subcategory` ekle (T01 sonrası veri var)
  - Item feature matrix'e subcategory one-hot encoding ekle
  - Soğuk başlangıç ilanları için subcategory bazlı başlangıç vektörü üret

- [ ] **T39** — `bpr_service.py` negatif örneklemeyi güncelle
  - Pozitif: kullanıcının tıkladığı ilan (category + subcategory)
  - Negatif: aynı category'den farklı subcategory'deki ilan (daha güçlü negatif sinyal)

- [ ] **T40** — `swipe_live_ml.py` ALS eğitimini güncelle
  - `swipe_live_events` sorgusuna `stream_subcategory` ekle (T04 sonrası veri var)
  - Stream feature matrix'e subcategory ekle
  - `get_user_stream_recommendations()` dönen adayları stream.subcategory affinity ile re-rank et

---

## Doğrulama & Deploy

- [ ] **T41** — FAZ 1–3 sonrası entegrasyon testi
  - Feed event'inde `listing_subcategory` doğru yazılıyor mu? (ClickHouse SELECT)
  - Search event'inde `subcategory` doğru yazılıyor mu?
  - SwipeLive event'inde `listing_category` artık boş gelmiyor mu?

- [ ] **T42** — FAZ 4 sonrası feed kalite testi
  - "arabalar > sedan" tıklayan kullanıcının feed'inde kamyon/tekne oranı azaldı mı?
  - SwipeLive'da subcategory affinity skorlaması çalışıyor mu?

- [ ] **T43** — FAZ 6 sonrası ML model doğrulama
  - ALS precision@10 baseline vs subcategory-aware model karşılaştırması
  - K-Means cold start: onboarding A/B testi

- [ ] **T44** — Commit + push + VPS deploy (her FAZ sonunda)
  - `git pull && sudo systemctl restart teqlif`
  - ARQ worker'ı yeniden başlat: `sudo systemctl restart teqlif-worker`
