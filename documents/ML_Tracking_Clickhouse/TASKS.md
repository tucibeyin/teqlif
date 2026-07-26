# ML / Tracking / ClickHouse — Görev Listesi

**Plan:** `PLAN.md`
**Kural:** FAZ 1 tamamlanmadan FAZ 2'ye geçilmez. FAZ 6 (ML model güncellemeleri) için minimum 2 hafta veri birikimi şart.

---

## FAZ 1 — Temel: Veri Toplama Altyapısı

### ClickHouse DDL

- [ ] **T01** — `feed_analytics` tablosuna `listing_subcategory String DEFAULT ''` sütunu ekle
  - `database_clickhouse.py` DDL + Buffer tablo
  - `buffer_feed_event()` fonksiyon imzasına `listing_subcategory: str = ''` ekle

- [ ] **T02** — `search_events` tablosuna `subcategory String DEFAULT ''` sütunu ekle
  - DDL + Buffer tablo
  - `buffer_search_event()` fonksiyon imzasına `subcategory: str = ''` ekle

- [ ] **T03** — `user_events` tablosunda `metadata` (boş string) yerine `subcategory String DEFAULT ''` sütunu ekle
  - DDL değişikliği — `metadata` kaldırılmıyor, `subcategory` ek sütun olarak eklenir
  - `buffer_user_event()` imzasına `subcategory: str = ''` ekle

- [ ] **T04** — `swipe_live_events` tablosuna `stream_subcategory String DEFAULT ''` ve `listing_subcategory String DEFAULT ''` ekle
  - DDL + Buffer tablo
  - `buffer_swipe_live_event()` imzasına her ikisini de ekle

- [ ] **T05** — VPS'te ClickHouse migration'larını çalıştır ve `DESCRIBE TABLE` ile doğrula

### Embedding Zenginleştirme

- [ ] **T06** — `worker.py:_listing_embed_text()` fonksiyonunu güncelle
  - Mevcut: `title + description + category + condition`
  - Eklenecek: `subcategory` + extra_fields'dan `brand`, `model`, `year`, `km`, `fuel_type`, `gear`, `body_type`, `color`, `room_count`, `size`, `floor`, `processor`, `ram`
  - Boş/None değerler sessizce atlanır
  - Biçim: `"title description category subcategory condition brand model 2020 50000km benzin otomatik sedan"`

- [ ] **T07** — `backfill_listing_embeddings_task` ile mevcut tüm aktif ilanları yeniden embed et
  - Task zaten var; T06 sonrası çalıştırılır
  - VPS'te ARQ worker'ı üzerinden tetikle

### SwipeLive — LiveStream Modeli

- [ ] **T08** — Alembic migration: `live_streams.subcategory VARCHAR(100) NULL` kolonu ekle
  - `backend/app/models/stream.py`'a `subcategory: Mapped[Optional[str]]` ekle

- [ ] **T09** — `StreamStart` şemasına `subcategory: Optional[str] = None` ekle
  - `schemas/stream.py`
  - Yayın başlatma endpoint'inde kaydet

---

## FAZ 2 — Mobile → Backend Sinyal Akışı

### Schema Güncelleme

- [ ] **T10** — `schemas/analytics.py: FeedEventCreate`'e `listing_subcategory: Optional[str] = None` ekle

- [ ] **T11** — `schemas/analytics.py: SearchEventCreate`'e `subcategory: Optional[str] = None` ekle

### Mobile: Feed Telemetry

- [ ] **T12** — `feed_telemetry_service.dart: logEvent()` imzasına `subcategory` ekle
  - Batched payload dict'e `'listing_subcategory': subcategory ?? ''` ekle

- [ ] **T13** — `swipe_live_screen.dart: _recordListingEvent()` bug fix
  - Satır 479: `'listing_category': ''` → `'listing_category': listingCategory`
  - `_onPageChanged` çağrısında `listingCategory` parametresini doldur (listing dict'ten oku)
  - `listing_subcategory` da ekle

- [ ] **T14** — Feed ekranında `logEvent()` çağrı sitelerini güncelle — `subcategory` parametresi geçirilsin
  - `home_screen.dart` veya feed widget'ları

### Mobile: Analytics Service

- [ ] **T15** — `analytics_service.dart: trackSearch()`'e `subcategory` parametresi ekle
  - Backend'e gönderilen body'ye `'subcategory': subcategory ?? ''` ekle

- [ ] **T16** — `analytics_service.dart: getPriceEstimate()`'e `subcategory`, `extraFields` (km, year, fuel_type) parametresi ekle
  - Backend `/price-estimate` endpoint'ine bu parametreler geçirilsin

- [ ] **T17** — `analytics_service.dart: logInteraction()`'da `metadata` dict'e subcategory ekle
  - Her çağrı sitesinde listing'in subcategory'si varsa metadata'ya ekle

---

## FAZ 3 — Backend: Yazma Tarafı

- [ ] **T18** — `routers/analytics.py: /feed-events` ingest endpoint'ini güncelle
  - `FeedEventCreate.listing_subcategory` → `buffer_feed_event()` çağrısına geçir

- [ ] **T19** — `routers/analytics.py: /search-events` ingest endpoint'ini güncelle
  - `SearchEventCreate.subcategory` → `buffer_search_event()` çağrısına geçir

- [ ] **T20** — `routers/streams.py` swipe-live event ingest'ini güncelle
  - `stream_subcategory`, `listing_subcategory` → `buffer_swipe_live_event()` çağrısına geçir

- [ ] **T21** — `use_cases/listings/queries/get_swipe_feed.py`'ı güncelle
  - `_row_dict()`'e `subcategory` ve seçili extra_fields özeti ekle (`year`, `km`, `fuel_type`, `gear`, `room_count`, `size` gibi)

- [ ] **T22** — Ana feed API `listing_utils.py: _row_dict()`'e `subcategory` ve `extra_fields` özeti ekle
  - Feed kartı için gereken alanlar: `subcategory`, `year`, `km`, `fuel_type`, `gear`, `room_count`, `size`
  - N+1 sorununu ortadan kaldırır

---

## FAZ 4 — Feed & Öneri Algoritmaları

- [ ] **T23** — `user_interests` tablosuna subcategory sütunu ekle (Alembic migration)
  - `(user_id, category, subcategory, score)` — `subcategory = NULL` mevcut top-level kayıtlara dokunmaz
  - Index: `(user_id, category, subcategory)`

- [ ] **T24** — `use_cases/feed/queries/feed_queries.py: get_user_interests()`'i güncelle
  - Subcategory bazlı skorları da döndür

- [ ] **T25** — `feed_queries.py: _score_and_rank()` scoring SQL'e subcategory affinity terimi ekle
  - `_get_subcategory_pref_expr()` fonksiyonu yaz — condition tercihi CASE ifadesine benzer biçimde
  - Scoring formülüne `subcat_affinity × 0.08` ağırlığıyla ekle (freshness veya quality ağırlığından al)

- [ ] **T26** — `feed_queries.py: greedy diversity`'ye subcategory limiti ekle
  - `MAX_PER_SUBCAT = 2` — aynı subcategory'den 2'den fazla ilan art arda feed'e girmesin

- [ ] **T27** — `recommendation_service.py: _thompson_sample_categories()`'i subcategory seviyesine indir
  - `get_user_category_affinity()` subcategory bazlı skoru da çeksin
  - `_ids_from_categories()` `WHERE subcategory = ANY(:subcats)` filtresi ekle

- [ ] **T28** — `swipe_live_queries.py: _score_stream()` affinity terimini güncelle
  - `interests.get((stream.category, stream.subcategory), interests.get(stream.category, 0.05))`
  - Fallback: subcategory skoru yoksa top-level skoru kullan

- [ ] **T29** — `swipe_live_queries.py: _fetch_listing_stream_correlation()` güncelle
  - `stream_subcategory × listing_subcategory` matrisini de hesapla (ClickHouse şeması T04'te hazır olacak)

- [ ] **T30** — `swipe_live_queries.py: GetSwipeFeedQuery`'yi güncelle
  - `func.random()` yerine: kullanıcı affinity'sine göre ağırlıklı sıralama
  - Temel: `user_interests` skoruna göre `category` + `subcategory` eşleşmesi öncelikli

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
