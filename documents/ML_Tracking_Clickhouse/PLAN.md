# ML / Tracking / ClickHouse Güncelleme Planı

**Bağlam:** Kategorizasyon 8 düz kategoriden → subcategory + extra_fields (JSONB) mimarisine genişledi.
Sinyal akışının her katmanı (mobile → schema → ClickHouse → ML → feed scoring) hâlâ eski 8-kategori döneminde yazılmış durumda. Bu belge etki haritasını, yaklaşım kararlarını ve uygulama sırasını tanımlar.

---

## 1. Etki Haritası

### 1.1 ClickHouse — Veri Omurgası (4 tablo tamamen subcategory-kör)

| Tablo | Eksik Sütun | Mevcut Durum |
|-------|-------------|--------------|
| `feed_analytics` | `listing_subcategory` | `listing_condition` var; subcategory hiç yazılmıyor |
| `search_events` | `subcategory` | `category` (top-level) yazılıyor; alt kategori sinyali yok |
| `user_events` | `subcategory` | `metadata` sütunu her zaman boş string yazılıyor |
| `swipe_live_events` | `stream_subcategory`, `listing_subcategory` | İkisi de hiç yok; `listing_category` ise Flutter bug'ı yüzünden her zaman boş string geliyor |

### 1.2 Embedding — Semantik Aramanın Temeli

`worker.py:_listing_embed_text()` embedding metnini `title + description + category + condition` olarak kuruyor. `subcategory`, `km`, `year`, `fuel_type`, `gear`, `body_type`, `room_count`, `size`, `processor`, `ram` gibi extra_fields değerleri embedding'e girmiyor. GIN index (`ix_listings_extra_fields_gin`) tanımlı ama hiçbir sorgu JSONB containment (`@>`) kullanmıyor — index boşa gidiyor.

### 1.3 ML Modelleri

| Model | Dosya | Subcategory Etkisi |
|-------|-------|--------------------|
| ALS (feed) | `feed_als_ml.py` | Saf `user_id × listing_id` matrisi; subcategory item feature yok |
| BPR | `bpr_service.py` | Negatif örnekleme subcategory gözetilmeden yapılıyor |
| Item2Vec | `item2vec_service.py` | Co-occurrence penceresi subcategory sınırı tanımıyor |
| K-Means cold start | `kmeans_service.py` | Cluster profilleri `{category: fraction}` — subcategory yok |
| Quality score | `quality_service.py` | extra_fields completeness (km, year, room_count dolu mu?) sinyali yok |
| ALS (SwipeLive) | `swipe_live_ml.py` | Yalnızca `user_id × stream_id` matrisi; stream_subcategory yok |

### 1.4 Feed & Öneri Algoritmaları

**Ana feed** (`feed_queries.py`):
- `user_interests` tablosunda `(user_id, category, score)` — subcategory sütunu yok
- Scoring SQL'de affinity CASE ifadesi yalnızca top-level
- `_get_condition_pref_expr()` eşdeğeri subcategory tercihi için yok
- Greedy diversity `MAX_PER_CAT = 4` — subcategory çeşitliliği kontrolü yok

**Öneri servisi** (`recommendation_service.py`):
- Thompson Sampling yalnızca 8 kategoride Beta dağılımı tutuyor
- Kullanıcı yalnızca "arabalar > sedan" tıklıyor olsa bile Thompson tüm "vehicles"'ı güçlendirip feed'e kamyon, tekne de sokuyor

**SwipeLive öneri** (`swipe_live_queries.py`):
- `_score_stream()` affinity terimi: `interests.get(stream.category)` — top-level
- `_fetch_listing_stream_correlation()`: `stream_category × listing_category` korelasyonu hesaplıyor ama `listing_category` Flutter'dan her zaman boş geliyor (bug)
- `GetSwipeFeedQuery`: `func.random()` — sıralama tamamen rastgele
- `LiveStream` DB modeli: `subcategory` kolonu hiç yok

### 1.5 Analytics Endpoint'leri

| Endpoint | Sorun |
|----------|-------|
| `/price-estimate` | Kandidat SQL `WHERE category = :cat`; subcategory filtresi yok; farklı alt kategoriler aynı havuza giriyor |
| `/competitor-radar` | Fallback + embedding sorgusu subcategory-kör |
| `/category-velocity`, `/demand-radar`, `/demand-trends` | `GROUP BY l.category`; alt kategori breakdown yok |
| `/market-trends` | `GROUP BY l.category` |
| `/pro/metrics` search_visibility | `WHERE category IN (...)` |

### 1.6 Mobile Client

**`analytics_service.dart`:**
- `trackSearch()`: sadece top-level `category` gönderiyor
- `getPriceEstimate()`: subcategory, km, year, fuel_type parametresi almıyor
- `logInteraction()`: `metadata` dict subcategory geçirilmeden çağrılıyor

**`feed_telemetry_service.dart`:**
- `logEvent()`: subcategory parametresi yok
- Batched payload'a subcategory hiç eklenmemiş

**`swipe_live_screen.dart`:**
- `_recordListingEvent()` satır 479: `'listing_category': ''` hard-coded — her zaman boş

### 1.7 API Response Eksiklikleri

- Feed API `_row_dict()`: `subcategory` ve `extra_fields` dönmüyor → Feed kartında "2020 | 50K km | Benzin" göstermek için N+1 istek gerekiyor
- SwipeLive swipe-feed: `subcategory`, `extra_fields` serialize edilmiyor
- `StreamOut` Flutter modeli: `subcategory` alanı yok

---

## 2. Yaklaşım Kararları

### Karar 1 — ClickHouse Şeması: ALTER vs Yeni Tablo
**Karar: `ALTER TABLE ... ADD COLUMN`**

ClickHouse MergeTree motorunda `ADD COLUMN` non-blocking; mevcut satırlar default değer (boş string) alır. Yeni sütunlar sadece yeni INSERT'lerde dolar. Geriye dönük backfill için listing_id üzerinden PostgreSQL JOIN yapılabilir.

### Karar 2 — Embedding Güncelleme: Backfill mi, Incremental mi?
**Karar: Incremental + arka planda backfill task**

Yeni ve güncellenen ilanlar hemen yeni embedding metniyle yeniden embed edilir (mevcut worker flow'u kullanır). Mevcut ilan stoku için `backfill_listing_embeddings_task` çalıştırılır — bu task zaten var, `_listing_embed_text()` güncellendikten sonra mevcut ilanlar otomatik olarak daha zengin embedding alır.

### Karar 3 — user_interests Tablosu: Yeni Sütun mu, Yeni Tablo mu?
**Karar: Yeni (user_id, category, subcategory, score) satırı — mevcut tabloya ek**

`subcategory = NULL` olanlar mevcut top-level skorları, dolu olanlar subcategory skorları temsil eder. Feed scoring SQL her ikisini de birleştirerek kullanır. Bu şekilde backward compat korunur.

### Karar 4 — SwipeLive `LiveStream` Modeli: Alembic Migration mi?
**Karar: Evet, Alembic migration ile `subcategory` kolonu eklenir**

`StreamStart` şeması genişletilir: `subcategory: Optional[str]`. Eski yayınlar NULL kalır, yeni yayınlar subcategory ile başlatılabilir.

### Karar 5 — ML Model Yeniden Eğitimi: Subcategory Feature Injection
**Karar: Önce veri toplayın, sonra model güncelleyin**

ClickHouse'da subcategory verisi birikmeden model güncellemek anlamsız. FAZ 1–3 tamamlanıp 2-4 hafta veri toplandıktan sonra ALS/BPR/K-Means subcategory feature injection yapılır.

---

## 3. Uygulama Sırası

```
FAZ 1 (Temel — Veri Toplama)
  ├── ClickHouse DDL genişletme (4 tablo)
  ├── Embedding metni zenginleştirme
  └── LiveStream DB modeli: subcategory kolonu

FAZ 2 (Mobile → Backend Sinyal Akışı)
  ├── Schema güncelleme (FeedEventCreate, SearchEventCreate)
  ├── Mobile feed_telemetry_service.dart
  ├── Mobile analytics_service.dart
  └── SwipeLive listing_category bug fix

FAZ 3 (Backend — Yazma Tarafı)
  ├── feed-events ingest endpoint
  ├── search-events ingest
  └── swipe-live-events ingest

FAZ 4 (Feed & Öneri)
  ├── user_interests tablosuna subcategory
  ├── Feed scoring SQL güncellemesi
  ├── Recommendation Thompson Sampling → subcategory seviyesi
  └── SwipeLive öneri skorlaması: subcategory affinity

FAZ 5 (Analytics Endpoint'leri)
  ├── /price-estimate subcategory filtresi
  ├── /competitor-radar subcategory filtresi
  └── /demand-radar, /category-velocity subcategory breakdown

FAZ 6 (ML Model Güncellemeleri — Veri Birikiminden Sonra)
  ├── K-Means cluster profili: subcategory
  ├── Quality score: extra_fields completeness
  ├── ALS feed: subcategory item feature injection
  └── ALS SwipeLive: stream_subcategory sinyali

FAZ 7 (API Response & Search)
  ├── Feed API _row_dict(): subcategory + extra_fields özeti
  ├── SwipeLive swipe-feed serialize
  └── Search endpoint: subcategory filtresi + GIN index kullanımı
```

---

## 4. Bağımlılık Grafiği

```
ClickHouse DDL ──────────────────────────────→ demand-radar/trends subcategory
     │
     └──→ Mobile payload güncelleme ──────────→ Veri birikmesi (2-4 hafta)
               │                                      │
               └──→ Backend ingest güncelleme          └──→ ML model güncelleme
                         │                                  (K-Means, ALS, BPR)
                         └──→ user_interests subcategory
                                   │
                                   └──→ Feed scoring SQL
                                         └──→ Thompson subcategory
```

**Kritik yol:** ClickHouse DDL → Mobile payload → Backend ingest → user_interests → Feed scoring. ML model güncellemeleri bu kritik yolun sonundadır.
