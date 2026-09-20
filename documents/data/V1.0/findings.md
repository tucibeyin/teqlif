# Veritabanı ve Mimari Optimizasyon Bulguları

**Hedef:** CPU/RAM/disk dostu, sade, uzun ömürlü veri katmanı.  
**Bağlam:** Sistem henüz kullanıcısız — DB sıfırdan kurulabilir. Şimdi yapılan her düzeltme ilerleyen dönemde downtime veya karmaşık migration gerektirmez.

Son güncelleme: 2026-09-20

---

## 1. PostgreSQL

### 1.1 [KRİTİK] direct_messages — int4 PK + Sonsuz Büyüme

**Mevcut kod:** `message.py:16` — `id: Mapped[int]` → PostgreSQL `INTEGER` (int4), max **2,147,483,647**

**Sorun:** `worker.py:408` — cleanup koşulu `is_hidden=TRUE AND created_at < 60 gün`. Normal mesajlar hiç silinmiyor. Tablo sonsuz büyür.

Büyüme tahmini:
- 100K kullanıcı × 5 mesaj/gün = 500K satır/gün → limit: ~11.7 yıl
- Büyüme hızlanırsa (1M/gün) → ~5.9 yıl
- `ALTER COLUMN id TYPE BIGINT` = tam tablo yeniden yazımı. 15MB'da ~1 saniye; 50M satırda ~20 dakika downtime.

**Düzeltme (şimdi — sıfırdan başlarken):**

```python
# message.py
from sqlalchemy import BigInteger
id: Mapped[int] = mapped_column(BigInteger, primary_key=True, index=True)
sender_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("users.id", ondelete="CASCADE"), ...)
receiver_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("users.id", ondelete="CASCADE"), ...)
```

**Ayrıca:** Normal mesajlar için retention policy eklenmeli:
```python
# worker.py — cleanup_hidden_messages_task'e ek kural:
# deleted_for_sender=TRUE AND deleted_for_receiver=TRUE AND created_at < 365 gün → sil
DELETE FROM direct_messages
WHERE deleted_for_sender = TRUE
  AND deleted_for_receiver = TRUE
  AND created_at < NOW() - INTERVAL '365 days'
```

Bu eklenmezse int8'e geçmek bile yalnızca limite uzayan bir erteleme olur.

---

### 1.2 [KRİTİK] direct_messages — OR Sorgusu + Yanlış İndeks

**Mevcut kod:** `get_messages_query.py:63-74`

```python
or_(
    and_(sender_id == uid, receiver_id == other_user_id),
    and_(sender_id == other_user_id, receiver_id == uid, is_shadowbanned == False),
)
```

Mevcut indeks: `(sender_id, receiver_id, created_at)`. PostgreSQL bu OR sorgusunu **iki ayrı Index Scan → BitmapOr → Heap Fetch** ile çalıştırır.

**`message_threads` zaten canonical pair tutuyor** (`user_a_id < user_b_id`, composite PK). Eksik olan: `direct_messages`'da `thread_id` kolonu yok.

**Düzeltme (sıfırdan — en temiz yol):**

```python
# message_thread.py — sequential PK ekle
id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
# Mevcut composite unique: (user_a_id, user_b_id) UNIQUE constraint olarak tut
```

```python
# message.py — thread_id ekle
thread_id: Mapped[int] = mapped_column(
    BigInteger, ForeignKey("message_threads.id", ondelete="CASCADE"), nullable=False, index=True
)
```

```python
# Alembic migration
Index("ix_dm_thread_id", "thread_id", "id")  # pagination için (thread_id, id DESC)
```

```python
# get_messages_query.py — OR kaldır
base_where = [
    DirectMessage.thread_id == thread_id,
    ...
]
```

Sonuç: tek equality check → perfect B-tree index → O(log n) + sequential read.

**`get_conversations_query.py`'deki `func.least()/func.greatest()` sorusu:** Bu sorgu `message_threads` tablosunu zaten PK üzerinden çekiyor (`user_a_id, user_b_id`). `direct_messages` thread_id'ye geçince bu sorgu da düzelir çünkü son mesajı `thread_id` üzerinden çekebiliriz.

---

### 1.3 [ORTA] notifications — int4 PK

**Mevcut kod:** `notification.py:14` — `id: Mapped[int]` → int4

**Gerçek risk:** `worker.py:280` — 30 günde siliniyor → bounded growth. Günde 1M notification üretilse bile 30 gün × 1M = 30M satır → int4 için sorun yok (**max 2.1B**).

**Ama:** Temiz başlangıçta BigInteger'a geçmek maliyetsiz.

```python
# notification.py
id: Mapped[int] = mapped_column(BigInteger, primary_key=True, index=True)
```

**Karar:** Direct messages migrasyonuyla birlikte hepsini BigInteger'a çevir — ileride ayrı migration maliyeti ödemezsin.

---

### 1.4 [BİLGİ] PostgreSQL Analytics Tablolarının Neden Burada Olduğu

`analytics_events` ve `user_interactions` tabloları PostgreSQL'de hem ClickHouse ile overlap görünüyor hem de ayrı amaçları var:

- `analytics_events` — ClickHouse `swipe_live_events`'ten 22 dakika gecikmeli PG'ye kopyalanıyor (`worker.py:658`). Öneri motoru (`update_feed_foryou_task`, her 15 dakika) PG likes/favorites/messages ile JOIN yapması gerektiği için ClickHouse'dan değil PG'den çekiyor.
- `user_interactions` — Redis kuyruğundan bulk-insert edilen dwell time sinyalleri. Benzer şekilde PG'de kalıyor çünkü JOIN gerekiyor.

**Her ikisi de 90 günde siliniyor → bounded.** Bu çift yazma kasıtlı bir mimari karar; öneri motoru cross-DB JOIN yapamaz.

**Aksiyon gerekmez.** Ama tablolar temiz indekse sahip:
- `analytics_events`: `ix_analytics_events_user_created (user_id, created_at)` ✓
- `user_interactions`: `ix_user_interactions_user_item (user_id, item_id)` ✓

---

### 1.5 [GELECEK] Tablo Bölümleme

`direct_messages` sonsuz büyüme riski nedeniyle ileride aylık partition gerektirecek. Ama 50M+ satırdan önce premature optimization.

**Tetikleyici:** 50M satır veya tek ay silinmesi 10 dakikayı geçmeye başlarsa.

---

## 2. Redis

### 2.1 [ONAYLANDI] Redis Streams — Zaten Uygulandı

`ws_manager.py` zaten `redis.xadd` ile Stream kullanıyor. **Bu bulgu eskimiş.**

---

### 2.2 [DÜŞÜK] Redis Pool Yapısı

**Mevcut:** `redis_client.py` — 4 ayrı pool:

| Pool | max_connections | Amaç |
|------|----------------|-------|
| `_redis` | 50 | Ana işlemler |
| `_redis_stream` | 20 | XREAD BLOCK (socket_timeout=10s) |
| `_redis_blpop` | 20 | BLPOP (socket_timeout=None) |
| `_redis_binary` | 20 | decode_responses=False (numpy vektörler) |

4 worker × 110 = **440 max bağlantı**. Redis default maxclients=10,000 → sunucu tarafında sorun yok.

**Blocking pool'ların ayrılması doğru mimari** — XREAD/BLPOP main pool'u doldursa non-blocking işlemler bekler. Bu değiştirilmemeli.

`_redis_binary` sadece `preference_embedding` Vector(384) cache için. `decode_responses` farkı nedeniyle main pool ile birleştirilemez. Olduğu gibi kalmalı.

**Aksiyon gerekmez.**

---

### 2.3 [BİLGİ] Redis Key Envanteri

Mevcut key pattern'leri:

| Pattern | Amaç | TTL |
|---------|------|-----|
| `session:{session_id}` | Auth session | — |
| `refresh:{token}` | Refresh token | — |
| `blacklist:{jti}` | Revoked JWT | — |
| `presign:{user_id}:{key}` | S3 presigned URL cache | 6 gün |
| `live:viewers:{stream_id}` | Anlık izleyici sayısı | — |
| `live:viewer_set:{stream_id}` | İzleyici set | — |
| `feed:session:{user_id}` | For-you feed cursor | — |
| `bpr:rec:{uid}` | BPR öneri cache | — |
| `msg:unread:request:{receiver_id}` | Okunmamış istek | — |
| `ad_campaign_budget:{campaign_id}` | Reklam bütçe cache | — |
| `condition_pref:{user_id}` | Durum filtre tercihi | — |
| `ch_buf:{table}` | ClickHouse batch buffer | — |

Kritik boşluk: `session:{session_id}` ve `refresh:{token}` için TTL var mı kontrol edilmeli. TTL yoksa Redis maxmemory dolduğunda eviction policy devreye girer.

---

## 3. ClickHouse

### 3.1 [ONAYLANDI] Redis Streams Pub/Sub → Zaten Değiştirildi

Bkz. **2.1**. Eski bulgu — silinebilir.

### 3.2 [GEREKLİ] Materialized Views — Reklam ve İzlenim Sorguları

**Mevcut:** `ads.py:338,352,375` ve `listings.py:414` — her sorguda `SELECT ... FROM user_events WHERE ...` tam tablo taraması.

`user_events` TTL 30 gün. Üst sınır: 100K kullanıcı × 50 event/gün × 30 = 150M satır. ClickHouse sütunlu okuma ile 150M satırda COUNT ~100-200ms tolere edilebilir.

Ama **reklam dashboard büyüdükçe** (kampanya başına günlük/saatlik toplam gösterim/tıklama), her API isteğinde full scan kabul edilemez hale gelir.

**Eklenecek:**

```sql
-- AggregatingMergeTree ile günlük reklam istatistikleri
CREATE MATERIALIZED VIEW mv_user_events_daily
ENGINE = AggregatingMergeTree()
PARTITION BY toYYYYMM(day)
ORDER BY (item_type, item_id, event_type, day)
AS
SELECT
    item_type,
    item_id,
    event_type,
    toDate(timestamp) AS day,
    countState() AS cnt
FROM user_events
GROUP BY item_type, item_id, event_type, day;
```

MV bir kez oluşturulduktan sonra yeni yazılan veriyi otomatik toplar. Geçmiş veri için ayrıca `INSERT INTO mv_user_events_daily SELECT ...` backfill gerekir.

**Tetikleyici:** Reklam özelliği büyüdüğünde veya `user_events` 20M+ satır geçtiğinde.

---

## 4. Veri Modeli Düzeltmeleri (Küçük ama Önemli)

### 4.1 message_threads — Sequential PK Eksikliği

`message_threads` şu an composite PK `(user_a_id, user_b_id)`. 1.2'deki `thread_id` çözümü için sequential `id BIGINT` eklenmeli.

Alternatif (daha hafif): `direct_messages`'a `conversation_id TEXT GENERATED ALWAYS AS (LEAST(sender_id,receiver_id)::text || '_' || GREATEST(sender_id,receiver_id)::text) STORED` eklenebilir. Ama `thread_id FK` daha temiz çünkü zaten `message_threads` var.

### 4.2 listing_impressions — PK Yeterli

Composite PK `(user_id, listing_id)` — sequential id yok, gerekmiyor. 30 günde siliniyor. Sorun yok.

### 4.3 story_views — Cascade ile Temiz

Story silinince `CASCADE` ile view'lar silinir. Sorun yok.

---

## Öncelik Sırası

| # | Bulgu | Öncelik | Aksiyon |
|---|-------|---------|---------|
| 1 | 1.1 direct_messages int4 PK | **Hemen** | Model → BigInteger; retention policy ekle |
| 2 | 1.2 OR sorgusu → thread_id | **Hemen** | message_threads'e id ekle; DM'e thread_id ekle; query güncelle |
| 3 | 1.3 notifications int4 PK | **Hemen** | BigInteger (1.1 ile birlikte) |
| 4 | 3.2 CH Materialized Views | Orta | Reklam büyüyünce / 20M+ satır |
| 5 | 1.5 Partitioning | Gelecek | 50M+ satır |
| — | 2.1 Redis Streams | **Eskimiş** | Zaten yapılmış |
| — | 2.2 Redis Pool | İzleme | Aksiyon gerekmez |
| — | 3.1 CH Dictionaries | Gereksiz | LowCardinality zaten var |
