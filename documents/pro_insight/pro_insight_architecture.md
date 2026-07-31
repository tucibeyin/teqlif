# Pro Insight — Uçtan Uca Mimari Analiz

**Son güncelleme:** Temmuz 2026  
**Kapsam:** Flutter UI → API → ML/AI → ClickHouse → PostgreSQL → pgvector  
**Temel:** `Architectural Decisions.md` + Clean Architecture prensipleri  
**Bağlantılı:** `findings.md`

---

## İçindekiler

1. [Özellik Tanımı](#1-özellik-tanımı)
2. [Sistem Haritası](#2-sistem-haritası)
3. [Endpoint Envanteri](#3-endpoint-envanteri)
4. [Bölüm Bazlı Veri Akışı](#4-bölüm-bazlı-veri-akışı)
   - 4.1 KPI Özeti
   - 4.2 Dönüşüm Hunisi
   - 4.3 Sıcak Talepler (Hot Leads)
   - 4.4 Fiyat Zekası (Price Intel)
   - 4.5 Yayın Performansı
   - 4.6 Pazar Saatleri (Peak Hours)
   - 4.7 Akıllı Öneriler (Tips)
   - 4.8 PRO Metrikler
5. [Yardımcı Endpointler](#5-yardımcı-endpointler)
6. [Flutter UI Katmanı](#6-flutter-ui-katmanı)
7. [Veri Depolama Katmanları](#7-veri-depolama-katmanları)
8. [Cache Stratejisi](#8-cache-stratejisi)
9. [ML / AI Bileşenleri](#9-ml--ai-bileşenleri)
10. [Architectural Decisions Uyumluluk Denetimi](#10-architectural-decisions-uyumluluk-denetimi)
11. [Clean Architecture Uyumluluk Denetimi](#11-clean-architecture-uyumluluk-denetimi)
12. [Dosya Referans Haritası](#12-dosya-referans-haritası)

---

## 1. Özellik Tanımı

Pro Insight, `is_premium = true` satıcılara yönelik analitik paneli. Satıcıya şunu sunar:

- **KPI özeti**: gelir, satış, teklif sayısı, ilan stoku
- **Dönüşüm hunisi**: görüntüleme → inceleme → tereddüt → teklif → satış
- **Sıcak talepler**: ilgi gören ama satılmayan ilanlar, ısı skoru ile
- **Fiyat zekası**: pgvector semantik benzerlik → piyasa ortalaması karşılaştırması
- **Yayın performansı**: canlı yayın istatistikleri
- **Pazar saatleri**: platform geneli en yüksek etkileşim saatleri
- **Akıllı öneriler**: kural tabanlı danışman — fiyat, talep, yayın zamanlaması
- **PRO metrikler**: ortalama inceleme süresi, arama görünürlüğü, dönüş izleyici oranı

**Erişim koşulu:** `is_premium = true` — ancak kontrolün tutarlı uygulanmadığı tespit edildi (bkz. findings.md F-02).

---

## 2. Sistem Haritası

```
Flutter ProInsightsScreen
        │
        ├─ AnalyticsService.getProInsights()
        │         │ GET /api/analytics/pro-insights
        │         │
        │         ▼
        │   analytics.py:pro_insights()   ←──── Redis cache (5 dk)
        │         │
        │         ├─ §KPI ──────────────── PostgreSQL (listings, purchases, bids)
        │         │
        │         ├─ §Funnel ──────────── ClickHouse (user_events)
        │         │                       PostgreSQL (bids, purchases)
        │         │
        │         ├─ §Hot Leads ─────────  ClickHouse (user_events: view, bid_hesitation)
        │         │                        PostgreSQL (listing_likes)
        │         │
        │         ├─ §Price Intel ──────── pgvector (embedding <=> cosine distance)
        │         │                        PostgreSQL (listings: AVG/STDDEV)
        │         │
        │         ├─ §Stream Stats ──────  PostgreSQL (live_streams, bids, auctions)
        │         │
        │         ├─ §Peak Hours ────────  ClickHouse (user_events: tüm platform)
        │         │
        │         └─ §Tips ──────────────  Türetilmiş (§Price Intel + §Hot Leads + §Peak Hours)
        │                                  ClickHouse (bid_hesitation price_point → öneri fiyatı)
        │
        └─ AnalyticsService.getProMetrics()
                  │ GET /api/analytics/pro/metrics
                  │
                  ▼
            analytics.py:get_pro_metrics()
                  │
                  ├─ avg_detail_dwell ──── ClickHouse (user_events: detail_dwell)
                  ├─ search_visibility ─── ClickHouse (search_events)
                  ├─ best_posting_hour ─── ClickHouse (user_events: view, click) + PG (listing yaratma saati)
                  └─ return_viewer_rate ── PostgreSQL (live_stream_viewers)
```

---

## 3. Endpoint Envanteri

| Endpoint | Dosya | Satır | Auth | Premium | Cache | Veri Kaynakları |
|----------|-------|-------|------|---------|-------|-----------------|
| `GET /pro-insights` | analytics.py | L987 | ✅ | ❌ Eksik | Redis 5 dk | PG + CH |
| `GET /pro/metrics` | analytics.py | L2252 | ✅ | ❌ Eksik | Yok | PG + CH |
| `GET /pro/best-stream-time` | analytics.py | L1452 | ✅ | — | — | PG + CH |
| `GET /demand-radar` | analytics.py | L2143 | ✅ | ✅ Var | Redis 5 dk | CH (search_events) |
| `GET /competitor-radar/{id}` | analytics.py | L2393 | ✅ | ❌ Eksik | Yok | pgvector + PG |

**Not:** `is_premium` guard sadece `demand-radar`'da mevcut — diğer endpoint'lerde eksik.

---

## 4. Bölüm Bazlı Veri Akışı

### 4.1 KPI Özeti

**Kaynak:** Saf PostgreSQL — 3 sorgu

```sql
-- listings: toplam, aktif, ortalama fiyat, son 30 günde yeni
SELECT COUNT(*), COUNT(*) FILTER (status='active'), AVG(price), ...
FROM listings WHERE user_id = :uid

-- purchases: toplam gelir, 30d gelir, önceki 30d gelir, satış adedi
SELECT COUNT(*), SUM(p.price), SUM FILTER (:d30...), ...
FROM purchases p JOIN listings l ON l.id = p.listing_id
WHERE l.user_id = :uid AND p.buyer_id != :uid

-- bids: son 30 günde teklif sayısı (açık artırma)
SELECT COUNT(*) FROM bids b
JOIN auctions a ON a.stream_id = b.stream_id
JOIN listings l ON l.id = a.listing_id
WHERE l.user_id = :uid AND b.created_at >= :d30
```

**Dönen alanlar:**
```json
{
  "total_listings": 47,
  "active_listings": 23,
  "avg_listing_price": 1250.0,
  "total_sales": 12,
  "total_revenue": 18450.0,
  "revenue_30d": 4800.0,
  "revenue_growth_pct": 12.5,
  "sales_30d": 3,
  "bids_30d": 8
}
```

**UI:** `_KpiGrid` — 4 kartlı gradient grid (teal, mavi, amber, mor).

---

### 4.2 Dönüşüm Hunisi

**Kaynak:** ClickHouse (view, detail_dwell, bid_hesitation) + PostgreSQL (bids, purchases)

```sql
-- ClickHouse — satıcının tüm aktif ilanlarına ait görüntüleme/inceleme/tereddüt:
SELECT
    countIf(event_type = 'view')              AS views,
    countIf(event_type = 'detail_dwell')      AS dwells,
    countDistinctIf(user_id, event_type = 'bid_hesitation') AS hesitations
FROM user_events
WHERE item_type = 'listing'
  AND item_id IN ({listing_ids})
  AND timestamp >= now() - INTERVAL 30 DAY
```

`bids` ve `sales` PostgreSQL'den (KPI sorgusundan alınır).

**Hesaplama:**
- `view_to_bid_pct` = (bids / views) × 100
- `bid_to_sale_pct` = (sales / bids) × 100

**UI:** `_FunnelCard` — 4 satır horizontal LinearProgressIndicator. Renk kodları: mavi→sarı→mor→yeşil.

> **Uyarı:** `dwells` alanı artık backend'de mevcut ancak `_FunnelCard` bunu UI'da göstermiyor — bkz. findings.md F-13.

---

### 4.3 Sıcak Talepler (Hot Leads)

**Kaynak:** ClickHouse (view, bid_hesitation) + PostgreSQL (listing_likes)

**Algoritma — Heat Score:**

```python
def _heat(lid: int) -> float:
    age_h = max((_now_ts - ts_map.get(lid, _now_ts)) / 3600, 0.0)
    raw = (
        view_map.get(lid, 0) * 1 +   # görüntüleme: 1 puan
        like_map.get(lid, 0) * 2 +   # beğeni: 2 puan
        hes_map.get(lid, 0)  * 3     # tereddüt: 3 puan
    )
    return raw / (age_h + 2) ** 1.2  # yaş cezası — taze ilan avantajlı
```

**Sıralama:** En yüksek ısı skoru önce → ilk 5 döner.

**Limit:** Analiz edilen maks ilan = 20 (→ findings.md F-06).

**Dönen alanlar:**
```json
[
  {
    "listing_id": 42,
    "title": "iPhone 15 Pro",
    "price": 45000,
    "category": "Elektronik",
    "views_30d": 312,
    "hesitations_30d": 7,
    "heat_score": 18.4
  }
]
```

**UI:** `_buildHotLeadsCarousel` — yatay kaydırmalı 170px kartlar. Kategori filtresi ve arama (client-side).

---

### 4.4 Fiyat Zekası (Price Intel)

**Kaynak:** pgvector (opsiyonel) + PostgreSQL

**Algoritma:**

1. Satıcının aktif ilanları alınır (maks 5)
2. Her ilan için:
   - **Embedding varsa:** pgvector cosine distance ile en yakın 10 rakip ilan → AVG + STDDEV
   - **Embedding yoksa:** Aynı kategoride ortalama fiyat → AVG + STDDEV
3. Fiyat aralığı filtresi: `price_lo = my_price * 0.05`, `price_hi = my_price * 20` (outlier eleme)
4. Eşik hesaplama:
   ```python
   _threshold = max(min((stddev / avg) * 100, 40.0), 10.0) if stddev else 15.0
   ```
5. Sinyal:
   - `diff_pct > threshold` → "pahalı"
   - `diff_pct < -threshold` → "ucuz"
   - else → "uygun"

**pgvector sorgusu:**
```sql
SELECT AVG(price), STDDEV(price) FROM (
    SELECT price FROM listings
    WHERE user_id != :uid
      AND category = :cat
      AND status = 'active'
      AND price > :lo AND price < :hi
      AND embedding IS NOT NULL
    ORDER BY embedding <=> CAST(:emb AS vector)
    LIMIT 10
) sub
```

**UI:** `_buildPriceIntelCarousel` — 170px kartlar, sinyal rengi (kırmızı=pahalı, yeşil=ucuz, mavi=uygun). Sinyal filtresi chip'leri.

---

### 4.5 Yayın Performansı

**Kaynak:** Saf PostgreSQL — live_streams, auctions, bids tabloları

```sql
-- Genel istatistikler:
SELECT COUNT(*), AVG(viewer_count), MAX(viewer_count), AVG(duration_epoch/60), ...
FROM live_streams
WHERE host_id = :uid AND is_live = false AND ended_at IS NOT NULL

-- En iyi 3 yayın (viewer_count DESC, bid_count DESC):
SELECT ls.title, ls.viewer_count, dur_min, COUNT(b.id) AS bid_count
FROM live_streams ls
LEFT JOIN auctions a ON a.stream_id = ls.id
LEFT JOIN bids b ON b.stream_id = a.stream_id
WHERE ls.host_id = :uid AND is_live = false
GROUP BY ls.id, ...
ORDER BY ls.viewer_count DESC, bid_count DESC LIMIT 3
```

**UI:** `_StreamStatsCard` — 4 metrik kutusu (toplam, bu ay, ortalama izleyici, zirve). En iyi yayınlar sıralı liste.

---

### 4.6 Pazar Saatleri (Peak Hours)

**Kaynak:** ClickHouse — tüm platform, satıcıya özel değil

```sql
SELECT toHour(timestamp) AS hr, COUNT(*) AS cnt
FROM user_events
WHERE timestamp >= now() - INTERVAL 30 DAY
  AND event_type IN ('view','detail_dwell','bid_hesitation')
GROUP BY hr ORDER BY cnt DESC LIMIT 5
```

**UI:** `_PeakHourBar` — max sayıya göre normalize edilmiş bar chart. Rank rozeti.

> **Uyarı:** Platform geneli saatler — satıcının kendi ilanlarına ait saatler değil. Bkz. findings.md F-05.

---

### 4.7 Akıllı Öneriler (Tips)

**Algoritma — Kural Motoru:**

Türetilmiş data; 4 kaynağa dayanır:

| Kural | Tetikleyici | Öneri Tipi |
|-------|------------|------------|
| Pahalı ilan | `price_intel[].signal == 'pahalı'` | "Fiyatı düşür" |
| Ucuz ilan | `price_intel[].signal == 'ucuz'` | "Fiyatı artır" |
| Sıcak talep | `hot_leads[0].hesitations_30d > 0` | "Fiyat küçük düşür veya açıklama güçlendir" |
| Tereddüt fiyat noktası | ClickHouse: `AVG(price_point) < listing.price * 0.85` + `cnt >= 2` | "Önerilen fiyata yaklaştır" |
| Yayın zamanlaması | `peak_hours` mevcutsa | "En yoğun saatte yayın yap" |
| Düşük dönüşüm | `view_to_bid_pct < 5% AND views > 10` | "Fotoğraf/açıklama iyileştir" |
| Hiçbiri yok | — | "Her şey iyi görünüyor" |

**Özel Kural — Tereddüt Fiyat Noktası:**
```sql
-- ClickHouse: alıcıların yazdığı ortalama teklif fiyatı
SELECT item_id, AVG(price_point) AS avg_pp, COUNT() AS cnt
FROM user_events
WHERE event_type = 'bid_hesitation'
  AND item_id IN ({seller_listing_ids})
  AND price_point > 0
  AND timestamp >= now() - INTERVAL 30 DAY
GROUP BY item_id
HAVING cnt >= 2
```
Ortalama alıcı teklifi, ilan fiyatının %85'inden düşükse öneri tetiklenir. Önerilen fiyat 50 TL'ye yuvarlanır.

**UI:** `_TipCard` — renkli border + ikon + başlık + açıklama.

---

### 4.8 PRO Metrikler (`/pro/metrics`)

Ayrı endpoint, ayrı veri yapısı:

| Metrik | Kaynak | Sorgu |
|--------|--------|-------|
| `avg_detail_dwell_seconds` | ClickHouse | `AVG(duration_seconds)` WHERE `event_type='detail_dwell'` |
| `search_visibility` | ClickHouse | `search_events` WHERE `category IN (satıcı kategorileri)` |
| `best_posting_hour` | ClickHouse + PG JOIN | view/click CTR → ilan yaratma saatine göre |
| `return_viewer_rate_pct` | PostgreSQL | `live_stream_viewers` — 2+ yayın izleyen oran |

**Uyarı:** Bu endpoint'te Redis cache yok — her çağrıda tüm sorgular çalışır.

**UI:** `_ProMetricsCard` — 3 chip + arama görünürlüğü listesi.

---

## 5. Yardımcı Endpointler

### 5.1 Demand Radar (`/demand-radar`)

```
Tek premium guard olan endpoint.
4 ClickHouse sorgusu paralel (asyncio.gather):
- search_events: top_queries (>= 2 arama)
- search_events: by_category
- search_events: by_subcategory
- search_events: daily_volume

Cache: Redis 5 dk, kullanıcı-bağımsız key.
```

### 5.2 Competitor Radar (`/competitor-radar/{listing_id}`)

```
Listing sahibi değilse 404.
Embedding varsa: pgvector cosine < 0.45 → en yakın 20 rakip
Embedding yoksa: category + subcategory + fiyata göre ABS(price - :price) ASC

Metrikler: avg_price, min_price, max_price, pct_rank (0=en ucuz, 100=en pahalı)
Signal: pahalı (>=75), ucuz (<=25), uygun (diğer)
Önerilen fiyat: pahalı→avg*0.95, ucuz→avg*1.03, uygun→avg*0.97

Cache: Yok.
```

---

## 6. Flutter UI Katmanı

### 6.1 Ekran Yapısı

```
ProInsightsScreen (ConsumerStatefulWidget)
│
├─ State:
│   _data: Map<String, dynamic>?       ← /pro-insights ham yanıtı
│   _metrics: Map<String, dynamic>?    ← /pro/metrics ham yanıtı
│   _loading: bool
│   _hasError: bool
│   _showAll: Map<String, bool>        ← bölüm başına "daha fazla gör" toggle
│   _hotLeadsFilter: ListingFilterState
│   _priceIntelFilter: ListingFilterState
│   _priceIntelSignal: String
│
├─ Yükleme: Future.wait([getProInsights(), getProMetrics()])
│
└─ Build → _buildBody(loc)
      │
      ├─ _KpiGrid (4 kart, 2×2 grid)
      ├─ _FunnelCard (horizontal progress bar'lar)
      ├─ _TipCard listesi (koşullu — tips boş değilse)
      ├─ Hot leads carousel (TeqFilterBar + _HotLeadCard horizontal)
      ├─ Price intel carousel (TeqFilterBar + chip + _PriceIntelCard horizontal)
      ├─ _StreamStatsCard (4 metrik + sıralı yayın listesi)
      ├─ _PeakHourBar listesi
      └─ _ProMetricsCard (3 chip + search visibility)
```

### 6.2 Filtre Mimarisi

Hot leads ve price intel için `TeqFilterBar` + client-side filtre:
```dart
// İstemci tarafında filtre — API'ye yeni çağrı yok
void _onHotLeadsFilterChanged(ListingFilterState f) {
  final dateChanged = f.dateFrom != _hotLeadsFilter.dateFrom ...;
  setState(() { _hotLeadsFilter = f; });
  if (dateChanged) _load();  // Tarih değişince yeniden yükle
}
```

Tarih filtresi değiştiğinde backend'e yeni çağrı yapılır ve Redis cache atlanır:
```python
cached_data = await redis.get(cache_key) if not (start_date or end_date) else None
```

### 6.3 Kullanılan Widget Bileşenleri

| Widget | Kaynak | Kullanım |
|--------|--------|---------|
| `TeqFilterBar` | ui_library | Hot leads + price intel filtresi |
| `FilterChip` | Material | Price intel sinyal filtresi |
| `LinearProgressIndicator` | Material | Funnel + peak hours |
| `GridView.count` | Material | KPI grid |
| `ListView.builder` | Material | Tüm carousel'lar |
| `RefreshIndicator` | Material | Pull-to-refresh |

---

## 7. Veri Depolama Katmanları

### PostgreSQL Tabloları

| Tablo | Kullanım | Filtre |
|-------|---------|--------|
| `listings` | KPI, hot_leads, price_intel | `user_id = :uid` |
| `purchases` | KPI gelir/satış | `buyer_id != :uid AND l.user_id = :uid` |
| `bids` | KPI teklif sayısı | `l.user_id = :uid AND a.stream_id = b.stream_id` |
| `auctions` | Teklif JOIN köprüsü | `stream_id` |
| `live_streams` | Yayın performansı | `host_id = :uid` |
| `live_stream_viewers` | Return viewer rate | `stream.host_id = :uid` |
| `listing_likes` | Hot leads beğeni | `listing_id IN (...)` |
| `listing_offers` | (şu an kullanılmıyor) | — |

### ClickHouse — `user_events`

| Sütun | Tip | Kullanım |
|-------|-----|---------|
| `user_id` | UInt64 | Funnel: `countDistinctIf(user_id, ...)` |
| `item_id` | UInt64 | Tüm listing sorgularında `IN (listing_ids)` |
| `item_type` | String | `'listing'` filtresi |
| `event_type` | String | `view`, `detail_dwell`, `bid_hesitation` |
| `price_point` | Float64 | Tereddüt fiyat noktası analizi |
| `duration_seconds` | Float64 | avg_detail_dwell_seconds |
| `timestamp` | DateTime | Son 30 gün filtresi |
| `subcategory` | String | demand-radar subcategory breakdown |

### ClickHouse — `search_events`

| Sütun | Kullanım |
|-------|---------|
| `query` | Demand radar: top arama kelimeleri |
| `category` | Demand radar: kategori bazlı hacim |
| `subcategory` | Demand radar: alt kategori breakdown |
| `timestamp` | Zaman filtresi |

### pgvector — `listings.embedding`

- Model: text-embedding (boyut belirtilmemiş)
- Mesafe ölçütü: cosine (`<=>` operatörü)
- Kullanım: Price intel'de semantik benzer ilan bulma + competitor radar
- Eşik: `< 0.45` (competitor radar)

### Redis

| Key Pattern | TTL | İçerik |
|-------------|-----|--------|
| `cache:pro_insights:{uid}:{locale}:{sd}:{ed}` | 300s | /pro-insights yanıtı |
| `cache:demand_radar:{days}:{category}` | 300s | /demand-radar yanıtı |

---

## 8. Cache Stratejisi

| Nokta | Mekanizma | TTL | Not |
|-------|-----------|-----|-----|
| /pro-insights | Redis | 5 dk | Tarih filtresi varsa atlanır |
| /pro/metrics | **Yok** | — | Her çağrıda 4 sorgu |
| /demand-radar | Redis | 5 dk | Kullanıcı-bağımsız key |
| /competitor-radar | **Yok** | — | Her çağrıda pgvector |
| /pro/best-stream-time | — | — | İncelenmedi |

Flutter'da SWR (stale-while-revalidate) yok — `AnalyticsService.getProInsights()` ham http.get, Hive cache katmanı yok.

---

## 9. ML / AI Bileşenleri

### 9.1 Fiyat Zekası — Semantik Benzerlik (pgvector)

**Tür:** Embedding tabanlı k-NN regresyon (k=10)  
**Girdi:** İlanın embedding vektörü  
**Çıktı:** Benzer ilanların fiyat ortalaması ve standart sapması  
**Model:** Listing oluşturulduğunda hesaplanan embedding (muhtemelen sentence-transformer)  
**Fallback:** Embedding yoksa kategori bazlı basit ortalama  

### 9.2 Tereddüt Fiyat Noktası Analizi (ClickHouse)

**Tür:** Kural tabanlı fiyat öneri sistemi  
**Veri:** `bid_hesitation` event'lerindeki `price_point` (kullanıcının yazdığı teklif tutarı)  
**Kural:** `AVG(price_point) < listing.price * 0.85 AND COUNT >= 2`  
**Çıktı:** 50 TL'ye yuvarlanmış önerilen fiyat  
**Sınırlama:** Kural deterministik — ML tabanlı değil, istatistiksel

### 9.3 Heat Score (Hot Leads Sıralama)

**Tür:** Ağırlıklı sayac + yaş fonksiyonu  
**Formül:** `(views×1 + likes×2 + hesitations×3) / (age_h + 2)^1.2`  
**Yorum:** Saf ML değil; belirleyici ağırlıklar mühendislik kararı

### 9.4 Fiyat Sinyal Eşiği

**Tür:** Adaptif eşik  
**Formül:** `threshold = max(min((stddev/avg)*100, 40.0), 10.0) if stddev else 15.0`  
**Yorum:** Piyasa volatilitesi arttıkça eşik genişliyor — iyi yaklaşım

---

## 10. Architectural Decisions Uyumluluk Denetimi

### §1 OTA Localization

| Kural | Durum |
|-------|-------|
| `loc.t()` kullanımı | ✅ Tüm UI bileşenlerinde |
| `ScaffoldMessenger` yasak | ✅ Kullanılmıyor |
| Tips hard-coded Türkçe format string | ⚠️ Kısmi ihlal — fallback metinler Türkçe hard-coded |
| `ConsumerWidget` pattern | ✅ Tüm bileşenler doğru |

### §3 ML / Analytics / ClickHouse

| Kural | Durum |
|-------|-------|
| ClickHouse: `user_events` tek kaynak | ✅ Tüm davranış sinyalleri CH'den |
| ML mantığı service layer'da | ⚠️ İhlal — heat score, fiyat sinyal mantığı router'da |
| Parametreli CH sorguları | ⚠️ Kısmi — `%(uid)s` doğru, ama bazı f-string interpolasyonlar var |

### §4 Merkezi Error Handling

| Kural | Durum |
|-------|-------|
| `handleError(e, ref.read(localizationProvider))` | ❌ İhlal — `catch (_) {}` yutma |
| `TeqToast` kullanımı | ❌ İhlal — hata durumunda hiçbir toast yok |
| Backend bölüm hataları loglanıyor | ✅ `logger.warning("[ProInsights] ...")` |

### §2.7 UI Bileşen Kararları

| Kural | Durum |
|-------|-------|
| `TeqToast` vs `ScaffoldMessenger` | ✅ |
| Pull-to-refresh | ✅ `RefreshIndicator` |
| Yükleme: `CircularProgressIndicator` | ✅ |
| Hata: Yeniden dene butonu | ✅ `_buildError()` |

---

## 11. Clean Architecture Uyumluluk Denetimi

### Katman Ayrımı

```
Beklenen:
  Presentation Layer (Flutter) → Use Case Layer → Repository Layer → Data Layer

Mevcut:
  Presentation Layer (Flutter) → Router (monolitik 400+ satır iş mantığı)
                                  ├─ Doğrudan DB sorguları
                                  ├─ ClickHouse sorguları
                                  ├─ İş mantığı (heat score, eşik hesabı)
                                  └─ Öneri kural motoru
```

**İhlaller:**
- Use Case katmanı yok — tüm mantık `pro_insights()` fonksiyonunda
- Repository pattern yok — `db.execute(sql_text(...))` doğrudan router'da
- Veri dönüşümleri handler içinde gerçekleşiyor

### Bağımlılık Yönü

```
analytics.py (router)
  ├─ app.database (get_db) ← doğrudan bağımlılık
  ├─ app.database_clickhouse (get_clickhouse_client) ← doğrudan bağımlılık
  ├─ app.utils.redis_client ← doğrudan bağımlılık
  └─ app.models.listing ← doğrudan bağımlılık
```

Repository abstraction yok — test edilemez, mock edilemez.

### Flutter Tarafı

```
ProInsightsScreen
  └─ AnalyticsService (static class)
       └─ http.get (ham HTTP)
```

- Riverpod provider yok — test edilemez
- `Map<String, dynamic>` — typed model yok
- Dependency injection yok

---

## 12. Dosya Referans Haritası

| Bileşen | Dosya |
|---------|-------|
| Ana ekran | `mobile/lib/screens/pro_insights_screen.dart` |
| API çağrıları | `mobile/lib/services/analytics_service.dart` |
| Yardımcı ekranlar | `mobile/lib/screens/listing_analytics_screen.dart` |
| | `mobile/lib/screens/pro_stream_analytics_screen.dart` |
| Ana backend | `backend/app/routers/analytics.py` (L987–L2500) |
| Pro-insights | `analytics.py:987` |
| Pro metrics | `analytics.py:2252` |
| Demand radar | `analytics.py:2143` |
| Competitor radar | `analytics.py:2393` |
| Best stream time | `analytics.py:1452` |
| Listing model | `backend/app/models/listing.py` |
| ClickHouse client | `backend/app/database_clickhouse.py` |
| Redis client | `backend/app/utils/redis_client.py` |
| Mimari kararlar | `documents/architectural_decisions.md` |
| Findings | `documents/pro_insight/findings.md` |
