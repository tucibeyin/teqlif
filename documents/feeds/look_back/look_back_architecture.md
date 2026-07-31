# Geri Bak (Look Back) Feed — Mimari Dokümantasyonu

**Son güncelleme:** Temmuz 2026  
**Durum:** Production  
**İlgili commit'ler:** `c6172812` (FAISS fix), `75fcf5d8` (kapsamlı iyileştirme)

---

## 1. Genel Bakış

"Geri Bak" (Look Back), kullanıcının yakın geçmişte incelediği ama satın almadığı ilanları yeniden yüzeyine çıkaran davranışsal bir retargeting feed'idir. İki güçlü sinyal üzerine inşa edilmiştir:

| Sinyal | Tetiklenme Koşulu | Anlamı |
|--------|-------------------|--------|
| `detail_dwell` | İlan detay sayfasında ≥ 30 saniye | Derin ilgi — kullanıcı inceledi ama karar vermedi |
| `bid_hesitation` | Teklif alanına yazıp göndermeme | Intent sinyali — fiyat engeli veya kararsızlık |

Feed, `home_screen.dart`'ta yatay kaydırmalı bir shelf olarak gösterilir. Sadece giriş yapmış kullanıcılara görünür; misafirlerde hiç render edilmez.

---

## 2. Katmanlı Mimari

```
┌─────────────────────────────────────────────────────────────────┐
│  FLUTTER CLIENT                                                  │
│                                                                  │
│  listing_detail_screen.dart                                      │
│    dispose() → ≥30s? → logInteraction(detail_dwell)             │
│    dispose() → bid field touched? → logInteraction(bid_hesit.)  │
│                        │                                         │
│  home_screen.dart      │                                         │
│    _loadHesitated()    │  ApiService.get (SWR)                   │
│    shelf card          │  cache: feed_hesitated / 15dk           │
└────────────────────────┼────────────────────────────────────────┘
                         │ POST /api/analytics/interaction
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│  BACKEND — INGEST                                                │
│                                                                  │
│  analytics.py — POST /api/analytics/interaction                 │
│    ├─ record → interaction_queue (Redis list)                   │
│    ├─ hesitated:{uid} Redis set'ine ekle (14 gün TTL)           │
│    └─ spike_key incr → 3. hit'te notify_hot_listing_task        │
└────────────────────────┬────────────────────────────────────────┘
                         │ her 5 dakikada (ARQ cron)
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│  BACKEND — ETL (worker.py)                                       │
│                                                                  │
│  flush_interactions_to_db()                                      │
│    ├─ Redis LRANGE → batch oku                                   │
│    ├─ PostgreSQL user_interactions bulk insert                   │
│    ├─ Redis LTRIM (PG commit sonrası — kayıp önlemi)            │
│    ├─ ClickHouse user_events bulk insert                        │
│    ├─ update_user_preference_embedding (listing user'ları için) │
│    └─ Thompson Sampling Beta parametreleri güncelle              │
└────────────────────────┬────────────────────────────────────────┘
                         │ sorgu
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│  BACKEND — SERVE                                                 │
│                                                                  │
│  feed.py — GET /api/feed/hesitated                              │
│    ├─ Redis cache: feed:hesitated:{uid} / 15dk                  │
│    ├─ ClickHouse: 14 günlük sinyal penceresi                    │
│    ├─ not_interested:{uid} Redis filtresi                       │
│    ├─ PostgreSQL: aktif ilan + offer_count JOIN                  │
│    ├─ Diversity: kategori başına maks 3                          │
│    ├─ price_dropped / price_near_offer bayrakları               │
│    └─ Maks 12 ilan                                               │
│                                                                  │
│  feed.py — DELETE /api/feed/hesitated/{id}                      │
│    ├─ not_interested:{uid} set'ine ekle                          │
│    └─ feed:hesitated:{uid} cache'ini temizle                     │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. Veri Akışı — Sinyal Toplama

### 3.1 detail_dwell Sinyali

**Dosya:** [mobile/lib/screens/listing_detail_screen.dart](../../../mobile/lib/screens/listing_detail_screen.dart#L449-L458)

```dart
// dispose() içinde — sayfa kapatılınca
if (listingId != null && durationSec >= 30) {
  AnalyticsService.logInteraction(
    itemId: listingId,
    itemType: 'listing',
    interactionType: 'detail_dwell',
    durationSeconds: durationSec,
    pricePoint: pricePoint,       // İlanın O ANKİ liste fiyatı
    subcategory: listing['subcategory'],
  );
}
```

`pricePoint` burada ilanın listing fiyatıdır (kullanıcının teklif tutarı değil). Bu değer sonraki servede `price_dropped` bayrağı hesaplamasında kullanılır: eğer mevcut fiyat o anki fiyattan ≥%1 düşmüşse bayrak `true` döner.

### 3.2 bid_hesitation Sinyali

**Dosya:** [mobile/lib/screens/listing_detail_screen.dart](../../../mobile/lib/screens/listing_detail_screen.dart#L503-L513)

```dart
// dispose() içinde — teklif alanına yazıldı ama submit edilmedi
if (_offerFieldTouched) {
  AnalyticsService.logInteraction(
    itemId: id,
    itemType: 'listing',
    interactionType: 'bid_hesitation',
    pricePoint: _offerTypedAmount,  // Kullanıcının yazdığı tutar
    subcategory: listing['subcategory'],
  );
}
```

`pricePoint` burada kullanıcının teklif alanına yazdığı tutardır. Bu değer servede `price_near_offer` hesaplamasında kullanılır: eğer mevcut fiyat ≤ kullanıcının yazdığı × 1.05 ise bayrak `true` döner.

### 3.3 logInteraction Transport

**Dosya:** [mobile/lib/services/analytics_service.dart](../../../mobile/lib/services/analytics_service.dart#L329-L368)

Fire-and-forget HTTP POST — ağ hatası sessizce görmezden gelinir, UI bloke olmaz.

```
POST /api/analytics/interaction
{
  item_id, item_type, interaction_type,
  duration_seconds, price_point,
  metadata: { subcategory },
  user_id  // JWT expire durumunda kayıp önlemi
}
```

---

## 4. Veri Akışı — İngest Katmanı

### 4.1 analytics.py — İngest Endpoint

**Dosya:** [backend/app/routers/analytics.py](../../../backend/app/routers/analytics.py)

```
POST /api/analytics/interaction
  │
  ├─ payload → record dict (subcategory dahil)
  ├─ record → Redis RPUSH interaction_queue
  │
  ├─ bid_hesitation VEYA detail_dwell mi?
  │    ├─ EVET: SADD hesitated:{user_id} {item_id}
  │    │         EXPIRE hesitated:{user_id} 14*86400
  │    │         spike_key = hes_spike:{item_id}
  │    │         INCR spike_key → spike_count
  │    │         spike_count == 3? → notify_hot_listing_task()
  │    └─ HAYIR: geç
  │
  └─ Cold start kontrol (yeni kullanıcı mı?)
       → flush_interactions_to_db + update_user_preference_embedding
```

> **Not:** `hesitated:{uid}` Redis set'i ilanı hemen işaretler. `flush_interactions_to_db` çalışana kadar ClickHouse'a ulaşmaz. Bu 5 dakikaya kadar gecikme demektir — kabul edilmiş trade-off.

### 4.2 worker.py — Flush Görevi

**Dosya:** [backend/app/worker.py](../../../backend/app/worker.py#L371-L548)  
**Frekans:** Her 5 dakikada bir (ARQ cron, tüm dakikaların 0/5/10/.../55 saniyesinde)

```python
# Atomic okuma garantisi:
raw_items = await redis.lrange(QUEUE_KEY, 0, BATCH_LIMIT - 1)
# PostgreSQL INSERT — başarısız olursa Redis LTRIM yapılmaz
async with AsyncSessionLocal() as db:
    await db.execute(sa_insert(UserInteraction), pg_rows)
    await db.commit()
# PG commit sonrası kuyruğu kısalt — kayıp olmaz
await redis.ltrim(QUEUE_KEY, BATCH_LIMIT, -1)
# ClickHouse insert — PG akışını engellememeli
await ch.insert("user_events", ch_data, column_names=[...])
```

Flush sonrası ek görevler tetiklenir:
- `update_user_preference_embedding` — listing etkileşimi olan her user için
- Thompson Sampling Beta parametreleri güncelleme

---

## 5. ClickHouse Şema

### user_events Tablosu

```sql
CREATE TABLE user_events (
  user_id        Nullable(UInt32),
  item_id        UInt32,
  item_type      LowCardinality(String),   -- 'listing'
  event_type     LowCardinality(String),   -- 'bid_hesitation' | 'detail_dwell'
  price_point    Nullable(Float64),         -- bağlama göre farklı anlam (§3.1/§3.2)
  duration_seconds Nullable(Float64),
  metadata       String,                    -- JSON
  subcategory    LowCardinality(String),    -- ALTER TABLE ile eklendi
  timestamp      DateTime
) ENGINE = MergeTree()
  PARTITION BY toYYYYMM(timestamp)
  ORDER BY (user_id, timestamp);
```

> **Kritik:** `subcategory` sütunu `ALTER TABLE ... ADD COLUMN` ile eklendi (Temmuz 2026). Eski satırlar boş string alır — backfill gereksizdi çünkü eski sinyaller zaten `metadata.subcategory` alanında tutuluyordu.

### Look Back Query Mantığı

```sql
SELECT
    item_id,
    argMax(event_type, timestamp)   AS top_signal,
    MAX(timestamp)                  AS last_seen,
    argMax(price_point, timestamp)  AS last_price_point
FROM user_events
WHERE event_type IN ('bid_hesitation', 'detail_dwell')
  AND item_type = 'listing'
  AND user_id   = {uid}
  AND timestamp >= now() - INTERVAL 14 DAY
GROUP BY item_id
ORDER BY
    multiIf(top_signal = 'bid_hesitation', 0, 1),  -- bid_hesitation önce
    last_seen DESC
LIMIT 40
```

`argMax(event_type, timestamp)` — bir ilan için hem `bid_hesitation` hem `detail_dwell` varsa en son sinyali baz alır. `bid_hesitation` intent açısından daha güçlü kabul edilir ve önce sıralanır.

---

## 6. Serve Katmanı — /api/feed/hesitated

**Dosya:** [backend/app/routers/feed.py](../../../backend/app/routers/feed.py#L188-L340)

### 6.1 Cache Stratejisi

```
İstek geldi
  │
  ├─ Redis GET feed:hesitated:{uid}
  │   ├─ HIT → JSON deserialize → return
  │   └─ MISS → ClickHouse + PG sorgusu
  │               └─ Redis SETEX feed:hesitated:{uid} 900
  │
  ▼
DELETE /feed/hesitated/{id} geldi
  ├─ SADD not_interested:{uid} {lid}   [14 gün TTL]
  └─ DEL feed:hesitated:{uid}          [cache invalidate]
```

TTL değerleri:
- `feed:hesitated:{uid}` → **900 saniye (15 dakika)**
- `not_interested:{uid}` → **14 gün**
- `hesitated:{uid}` → **14 gün**

### 6.2 Sıralama ve Filtreleme Pipeline'ı

```
ClickHouse 40 aday
  │
  ├─ not_interested:{uid} Redis filtresi (kaldırılmış ilanlar)
  │
  ├─ PostgreSQL JOIN: aktif ilan kontrolü + offer_count
  │   WHERE l.status = 'active'
  │   GROUP BY ... COUNT(listing_offers)
  │
  ├─ Diversity: kategori başına max 3
  │   category_counts[cat] >= 3 → atla
  │
  ├─ price_dropped hesaplama:
  │   signal == 'detail_dwell'
  │   AND current_price < stored_pp * 0.99   (≥%1 düşüş)
  │
  ├─ price_near_offer hesaplama:
  │   signal == 'bid_hesitation'
  │   AND current_price <= stored_pp * 1.05  (fiyat yazılanın ≤%5 üstünde)
  │
  └─ Maks 12 ilan → cache → return
```

### 6.3 Response Payload

```json
[
  {
    "id": 1234,
    "title": "iPhone 14 Pro",
    "price": 42000.0,
    "image_url": "/uploads/listings/...",
    "signal": "bid_hesitation",
    "offer_count": 3,
    "price_dropped": false,
    "price_near_offer": true
  }
]
```

---

## 7. Flutter Client — Shelf Gösterimi

**Dosya:** [mobile/lib/screens/home_screen.dart](../../../mobile/lib/screens/home_screen.dart)

### 7.1 Veri Yükleme (SWR)

```dart
void _loadHesitated({bool bypassCache = false}) {
  ApiService.get<List<dynamic>>(
    url: '$kBaseUrl/feed/hesitated',
    cacheKey: 'feed_hesitated',
    cacheTtl: const Duration(minutes: 15),
    bypassCache: bypassCache,
    fromJson: (raw) => raw as List,
  ).listen((data) {
    if (mounted) setState(() => _hesitatedListings = data);
  });
}
```

SWR davranışı: Hive cache varsa anında göster → arka planda API → taze veriyle güncelle. TTL eşleşmesi: client 15 dk, server cache 15 dk.

Şelf yalnızca `_hesitatedListings.isNotEmpty` olduğunda render edilir. Misafir kullanıcılarda `_loadHesitated()` hiç çağrılmaz.

### 7.2 Shelf Kartı — Badge Sistemi

| Badge | Koşul | Renk | Pozisyon |
|-------|-------|------|----------|
| `↓` (fiyat düştü) | `price_dropped == true` | Kırmızı | Sol üst |
| `✓` (teklife yaklaştı) | `price_near_offer == true` | Yeşil | Sol üst |
| `{n}` (teklif sayısı) | `offer_count > 0` | Yarı şeffaf siyah | Sağ üst |

`price_dropped` ve `price_near_offer` aynı anda `true` olamaz — signal'ın doğasından kaynaklı: bir ilan ya `detail_dwell` ya `bid_hesitation` sinyaliyle işaretlenir.

### 7.3 Etkileşimler

**Tap:**
```dart
AnalyticsService.logInteraction(
  itemId: lid,
  itemType: 'listing',
  interactionType: 'hesitated_shelf_tap',
);
Navigator.push(ListingDetailScreen(...));
```

**Long-press (dismiss):**
```dart
// 1. Optimistik UI güncelle
setState(() => _hesitatedListings.removeWhere((e) => e['id'] == lid));
// 2. Backend'e bildir (fire-and-forget)
http.delete('/api/feed/hesitated/$lid');
// 3. Snackbar
ScaffoldMessenger.showSnackBar(loc.t('hesitatedDismissed'));
```

Backend dismiss endpoint'i `not_interested:{uid}` set'ine ekler ve `feed:hesitated:{uid}` cache'ini temizler — bir sonraki yükleme temiz gelir.

---

## 8. Arka Plan Görevleri

### 8.1 Hot Listing Bildirimi (Satıcıya)

**Dosya:** [backend/app/worker.py](../../../backend/app/worker.py#L2845-L2878)  
**Tetiklenme:** 24 saat içinde bir ilanda 3. `bid_hesitation` geldiğinde

```
Redis: hes_spike:{listing_id} INCR → TTL 24h
spike_count == 3?
  → notify_hot_listing_task(listing_id, count)
    → listing sahibine FCM push:
       "İlanın ilgi görüyor! {count} kişi teklif vermek üzereydi."
```

`_job_id` dedup ile 24h içinde yalnızca bir kez gönderilir.

### 8.2 Fiyat Düşüşü Retarget (Alıcıya)

**Dosya:** [backend/app/worker.py](../../../backend/app/worker.py#L2883-L2978)  
**Frekans:** Her gün 06:00 (ARQ cron)

```
ClickHouse: son 7 günde bid_hesitation → user+listing+avg_price
PostgreSQL: aktif ilanların güncel fiyatı
  current_price <= avg_hesitation_price * 0.92?
    (kullanıcının yazduğundan ≥%8 düşüş)
    → Redis dedup: retarget:hes:{uid}:{lid} (7 gün TTL)
    → push_notification(uid, type="price_drop_alert")
```

Bu görev API endpoint'indeki `price_near_offer` bayrağından bağımsızdır. Endpoint kullanıcı uygulamayı açtığında anlık fiyatı kontrol eder; bu görev kullanıcı uygulamayı açmadan önce bildirim gönderir.

---

## 9. Redis Anahtar Envanteri

| Anahtar | Tip | TTL | İçerik | Yazıldığı Yer |
|---------|-----|-----|--------|---------------|
| `interaction_queue` | List | yok | Ham event JSON'ları | analytics.py |
| `hesitated:{uid}` | Set | 14 gün | listing_id'ler (string) | analytics.py |
| `feed:hesitated:{uid}` | String | 15 dk | Serve JSON (12 ilan) | feed.py |
| `not_interested:{uid}` | Set | 14 gün | listing_id'ler | feed.py (dismiss) |
| `hes_spike:{listing_id}` | String | 24 saat | INCR sayacı | analytics.py |
| `retarget:hes:{uid}:{lid}` | String | 7 gün | Dedup flag | worker.py |

> **Dikkat:** `hesitated:{uid}` set'i ingest anında yazılır ama şu an hiçbir endpoint tarafından okunmamaktadır. `feed.py` doğrudan ClickHouse'u sorgular. Bu set `hes_spike` mantığı için bir yan etki olarak tutulmaktadır.

---

## 10. Pro Insights Entegrasyonu

Satıcı analytics ekranında (`/api/analytics/pro-insights`) Look Back sinyalleri kullanılır:

| Metrik | ClickHouse Query | Kullanım |
|--------|-----------------|----------|
| `hesitations` | `countDistinctIf(user_id, event_type = 'bid_hesitation')` | İlana kaç farklı kullanıcı teklif yazmak üzereydi |
| `avg_detail_dwell_seconds` | `AVG(duration_seconds) WHERE event_type = 'detail_dwell'` | Ortalama detay inceleme süresi |
| `hesitation_count` (ilan bazlı) | İlan listesinde `hesitations_30d` kolonu | "Sıcak ilanlar" tespiti |
| Peak hours | `event_type IN ('view','detail_dwell','bid_hesitation')` | En yoğun saatler |

Satıcıya gösterilen öneri metni (`_build_recommendation`): `hesitation_count >= 10` → fiyat indirimi önerisi.

---

## 11. Mimari Kararlar (Architectural Decisions.md ile Bağlantı)

### §3.1 ClickHouse Şema Değişikliği
`subcategory` sütunu `ALTER TABLE ... ADD COLUMN` ile eklendi — yeni tablo açmak gerekmedi. Mevcut satırlar `''` (boş string) aldı; yeni INSERT'ler dolu geliyor.

### §3.3 Veri Önce Prensibi
`subcategory` verisi birikmeden ML modelleri güncellenmedi. İlk 2-4 haftalık sinyal birikmesi bekleniyor.

### SWR Pattern
Client-side cache `ApiService.get` + Hive üzerinden yönetilir. Sunucu cache Redis'te. İkisi bağımsızdır; client TTL = server TTL = 15 dk.

### Fire-and-forget Analytics
`logInteraction` ağ hatasında UI'ı bloke etmez. Veri kaybı olabilir — intent sinyalleri için kabul edilmiş trade-off.

### Dismiss = not_interested (Kalıcı Filtre)
Dismiss, `hesitated:{uid}` set'inden kaldırmaz; `not_interested:{uid}` set'ine ekler. Bu, kullanıcının kapatma sinyalinin 14 gün boyunca korunacağı anlamına gelir.

---

## 12. Dosya Referans Haritası

| Katman | Dosya | Satırlar |
|--------|-------|----------|
| Signal Collection | `mobile/lib/screens/listing_detail_screen.dart` | `L430–L518` |
| Analytics Client | `mobile/lib/services/analytics_service.dart` | `L329–L368` |
| Shelf UI | `mobile/lib/screens/home_screen.dart` | `L123–L133`, `L454–L620` |
| Ingest API | `backend/app/routers/analytics.py` | `L145–L185` |
| ETL Worker | `backend/app/worker.py` | `L371–L548` |
| Serve API | `backend/app/routers/feed.py` | `L70–L340` |
| Hot Listing Task | `backend/app/worker.py` | `L2845–L2878` |
| Retarget Task | `backend/app/worker.py` | `L2883–L2978` |
| Pro Insights | `backend/app/routers/analytics.py` | `L1085–L1400` |
| ARB Keys | `documents/language/app_*.arb` | `hesitatedSectionTitle`, `hesitatedPriceDrop`, vb. |
