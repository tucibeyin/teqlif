# teqlif — Veri Yönetim Fazları

**Stack:** FastAPI (uvicorn 4w, uvloop) + PostgreSQL 16 + Redis 7 + ClickHouse + ARQ  
**Prod:** node5 — 4c EPYC, **7.8 GB RAM + 8 GB Swap**, **50 GB SSD**, 1 Gbps unmetered  
**Monitoring/Staging:** node3 — 4c EPYC, ~4 GB RAM + 4 GB Swap, Ashburn VA  
**Medya:** node1 + node4 — MinIO + LiveKit (node5'te MinIO yok)  
**Kaynak:** `deploy/scale/V1.4/documents/05_final.md` · `documents/teqlif_architectural_decisions.md`

---

## Notasyon

`□` karar bekleniyor · `■` onaylandı · `✅` var, çalışıyor · `⚠️` eksik/bozuk  
`🔴` kritik · `🟡` orta · `🟢` düşük  

---

## Bağımlılık Haritası

```
Faz 1 (Retention kararları)
  │
  ├──► Faz 2 (Schema)   → Float→Numeric, JSONB, FK düzeltmeleri
  │         │
  │         └──► Faz 3 (PG Altyapı) → PgBouncer, Index
  │                   │
  │                   └──► Faz 4 (ClickHouse + Redis)
  │                             │
  │         ┌───────────────────┘
  │         └──► Faz 5 (Sorgu + Cache)
  │
  ├──► Faz 6 (ARQ Zamanlama) → W1-W7 frekans kararları
  │         │
  │         └──► Faz 7 (ML Kalitesi) → BUG-1/2/3 fix
  │
  ├──► Faz 8 (Medya) → sıkıştırma kararları
  │
  └──► Faz 9 (Güvenlik/KVKK) → hesap silme, IP maskeleme
       │
       └──► Faz 10 (tuci→teqlik) — en son
```

### Kritik Retention-Kod Uyumsuzlukları

| # | Servis | Kod Penceresi | Şu Anki TTL/Retention | Kayıp |
|---|--------|--------------|-----------------------|-------|
| **BUG-1** | `compute_trust_scores_task` (worker.py:3118) | ClickHouse **90 gün** | TTL **30 gün** | 60 günlük trust sinyali yok |
| **BUG-2** | `train_bpr_task` (bpr_service.py:144) | `user_interactions` **120 gün** | Retention **90 gün** | 30 günlük BPR eğitim verisi kayıp |
| **BUG-3** | `train_churn_model_task` (churn_ml_service.py:84) | ClickHouse **44 gün** | TTL **30 gün** | 14 günlük churn sinyali yok |

### CASCADE Tehlikesi

`gift_events.stream_id FK: ondelete="CASCADE"` — `live_streams` silinince finansal kayıt da siliniyor.  
R3 (live_streams temizliği) uygulanmadan önce bu FK **SET NULL'a** çevrilmeli.

`bids.stream_id FK: ondelete tanımsız` — live_stream silinmeye çalışılırsa FK violation.

---

## Faz 1 — Veri Yaşam Döngüsü ve Zamanlama

> Bu fazın kararları alınmadan diğer fazlar uygulanmaz.

### 1.1 — ClickHouse Tabloları (Mevcut TTL)

| Tablo | TTL | Buffer |
|-------|-----|--------|
| `user_events` | **30 gün** | Redis `ch_buf:user_events` → flush 30s / 5000 satır |
| `feed_analytics` | **30 gün** | Doğrudan batch INSERT |
| `search_events` | **30 gün** | Redis `ch_buf:search_events` → flush |
| `swipe_live_events` | **30 gün** | Doğrudan batch INSERT |
| `direct_sale_events` | **180 gün** | Redis `ch_buf:direct_sale_events` → flush |

---

### 1.2 — Retention Karar Tablosu

**Grup A — ML Kalitesiyle Bağlantılı (BUG-1/2/3) — Önce Bunlar**

| # | Tablo/TTL | Şu An | Öneri | Endüstri | Etki | Karar |
|---|-----------|-------|-------|---------|------|-------|
| **R9** | `user_events` ClickHouse TTL | 30 gün | **90 gün** | Mixpanel 90g · Amplitude 12ay | BUG-1 + BUG-3 kapanır | □ |
| **R9b** | `user_interactions` PG retention | 90 gün | **120 gün** | Netflix/Spotify CF: 3-6 ay | BUG-2 kapanır | □ |

> **Disk uyarısı (node5 50 GB SSD):** R9 kararından önce mevcut boyutu ölç:
> ```sql
> SELECT table, sum(bytes_on_disk)/1024/1024 AS mb
> FROM system.parts WHERE database='teqlif_prod_analytics' AND active=1
> GROUP BY table ORDER BY mb DESC;
> ```

**Grup B — Canlı Yayın (Birlikte Karar Ver)**

| # | Tablo | Şu An | Öneri | Bağımlılık | Karar |
|---|-------|-------|-------|-----------|-------|
| **R3** | `live_streams` (biten) | Sonsuz | **1 yıl** | R5 CASCADE fix yapılmadan uygulanmaz | □ |
| **R1** | `live_stream_viewers` | ⚠️ Sonsuz | **90 gün** | R3 CASCADE zaten siler | □ |
| **R5** | `gift_events` | Sonsuz | Sonsuz + FK SET NULL | TTK 82: finansal kayıt 10 yıl zorunlu | □ |
| **R4** | `bids` | Sonsuz | **2 yıl** | `bids.stream_id` ondelete fix gerekli | □ |

**Grup C — Mesajlaşma**

| # | Tablo | Şu An | Öneri | Karar |
|---|-------|-------|-------|-------|
| **R7** | `direct_messages` (text) | Sonsuz | Sonsuz önerilir | □ |
| R8 | `message_threads` | Sonsuz | R7=sonsuz ise sonsuz | □ |

**Grup D — Ticaret (Yasal Zorunluluk)**

| Tablo | Karar | Yasal Dayanak |
|-------|-------|--------------|
| `purchases` | ■ Sonsuz | TTK 82 + VUK 253: 10 yıl |
| `tuci_transactions` | ■ Sonsuz | TTK 82 + VUK 253: 10 yıl |
| `direct_sales` / `direct_sale_orders` | ■ Sonsuz | Ticaret kaydı |
| `auctions` | □ Sonsuz? | TTK 82 kapsamı değerlendirilmeli |

**Grup E — Diğer**

| # | Tablo | Şu An | Öneri | Endüstri | Karar |
|---|-------|-------|-------|---------|-------|
| R2 | `calls` (ended/missed) | Sonsuz | **1 yıl** | 5651 Kanunu: telekom 2 yıl; app çağrısı 1 yıl | □ |
| R6 | `listing_offers` (declined/expired) | Sonsuz | **60 gün** | Marketplace: 30-90 gün | □ |
| R10 | `market_index` (kur verileri) | Sonsuz | **2 yıl** | Vergi: 10 yıl; uygulama için 2 yıl yeterli | □ |
| R11 | Hesap silme → DM | Sonsuz | Anonimleştir | GDPR/KVKK: sender_id=NULL, `[Silinmiş mesaj]` | □ |

---

### 1.3 — Mevcut ARQ Cleanup Mekanizmaları (Değişmez)

| Görev | Zamanlama | Silen Veri |
|-------|-----------|-----------|
| `cleanup_stale_streams_task` | Her 2 dk | `live_streams` stale >3 dk |
| `cleanup_ghost_calls_task` | Her 15 dk | `calls` ghost (calling>5dk, active>1sa) |
| `cleanup_expired_stories_task` | Saatlik :00 | `stories` expired + MinIO stories/ |
| `cleanup_hype_highlights_task` | Saatlik :00 | `highlights` expired + local disk |
| `cleanup_old_stream_likes_task` | Günlük 01:00 | `stream_likes` >7 gün |
| `cleanup_hidden_messages_task` | Günlük 02:30 | `direct_messages` hidden + >60 gün |
| `cleanup_old_notifications_task` | Günlük 03:00 | `notifications` >30 gün |
| `deactivate_expired_listings_task` | Günlük 04:00 | `listings` aktif >30 gün → pasif |
| `delete_expired_inactive_listings_task` | Günlük 04:30 | `listings` pasif >60 gün → sil + MinIO |
| `cleanup_old_impressions_task` | Günlük 05:00 | `listing_impressions` >30 gün |
| `cleanup_old_media_messages_task` | Günlük 06:30 | `direct_messages` media >7 gün + MinIO |
| `cleanup_old_analytics_task` | Haftalık Pzt 04:00 | `analytics_events` >90 gün + VACUUM |
| `cleanup_old_user_interactions_task` | Haftalık Sal 04:00 | `user_interactions` >90 gün + VACUUM |

---

### 1.4 — Yeni GC Görevleri (R□ Kararlarına Bağlı)

| # | Görev | Tablo | Koşul | Zamanlama | Öncelik |
|---|-------|-------|-------|----------|---------|
| **GC1** | `cleanup_old_stream_viewers_task` | `live_stream_viewers` | `joined_at < R1` | Haftalık Çar 04:00 | 🔴 |
| GC2 | `cleanup_old_calls_task` | `calls` ended/missed | `ended_at < R2` | Haftalık Per 04:00 | 🟡 |
| GC3 | `cleanup_old_listing_offers_task` | `listing_offers` declined | `created_at < R6` | Haftalık Cum 04:00 | 🟡 |
| GC4 | `cleanup_old_market_index_task` | `market_index` | `date < R10` | Aylık 1. gün 05:00 | 🟢 |
| GC5 | `cleanup_old_streams_task` | `live_streams` ended | `ended_at < R3` | Aylık 1. gün 06:00 | 🟡 |
| GC6 | `cleanup_empty_message_threads_task` | `message_threads` | 0 mesaj + >30 gün | Haftalık Paz 05:00 | 🟢 |
| GC7 | `cleanup_inactive_search_alerts_task` | `search_alerts` | `updated_at < 180 gün` | Haftalık Paz 06:00 | 🟢 |

---

### 1.5 — MinIO Lifecycle Policy (node1 + node4)

| Bucket | TTL | Gerekçe |
|--------|-----|---------|
| `teqlif/listings/` | 365 gün | Uygulama silme kaçırılırsa güvenlik ağı |
| `teqlif/stories/` | 2 gün | expired cleanup kaçırılırsa |
| `teqlif-dm/` | 14 gün | 7 günlük cron kaçırılırsa |

---

### 1.6 — ARQ Zamanlama Kararları

W1 ↔ W4 birlikte karar ver.

| # | Görev | Şu An | Öneri | Karar |
|---|-------|-------|-------|-------|
| **W1** | `compute_user_interests_task` | 15 dk'da bir (96x/gün) | 2x/gün (08:00, 20:00) | □ |
| **W4** | `populate_foryou_feed_task` | Saatlik (24x/gün) | W1 ile 2-4x/gün | □ |
| W2 | `backfill_listing_embeddings_task` | 30 dk'da bir (gece gündüz) | Yalnızca 02:00-04:00 | □ |
| W3 | `compute_user_condition_preferences_task` | 15 dk'da bir | 4x/gün | □ |
| W5 | `compute_trending_listings_task` | 30 dk'da bir | 4x/gün | □ |
| **W6** | `train_feed_als_task` | Günlük 01:30 | Haftalık | □ |
| **W7** | `train_swipe_live_als_task` | Günlük 01:00 | Haftalık | □ |

---

### 1.7 — Faz 1 Başarı Kriterleri

```
□ Tüm R□ kararları onaylandı
□ GC1-GC7 hangileri uygulanacak belirlendi
□ MinIO lifecycle policy node1+node4'ta aktif
□ W1-W7 kararları alındı
□ R5 FK (CASCADE → SET NULL) planlandı
```

---

## Faz 2 — PostgreSQL Veri Yapısı

> Bağımlılık: Faz 1 kararları alınmış olmalı.

### 2.1 — Float → Numeric Düzeltmesi 🔴

| Tablo | Kolon | Şu An | Hedef |
|-------|-------|-------|-------|
| `listings` | `price`, `buy_it_now_price`, `last_sold_price`, `last_start_price` | `Float` | `Numeric(12, 2)` |
| `auctions` | `start_price`, `buy_it_now_price`, `final_price` | `Float` | `Numeric(12, 2)` |
| `bids` | `amount` | `Float` | `Numeric(12, 2)` |
| `purchases` | `price` | `Float` | `Numeric(12, 2)` |
| `listing_offers` | `amount` | `Float` | `Numeric(12, 2)` |
| `search_alerts` | `max_price` | `Float` | `Numeric(12, 2)` |
| `users` | `max_budget` | `Float` | `Numeric(12, 2)` |
| `market_index` | `usd_try`, `eur_try` | `Float` | `Numeric(10, 4)` |
| `direct_sales` | `price` | `Numeric(10, 2)` | ✅ Doğru |
| `tuci_transactions` | `amount` | `Integer` | ✅ Doğru (teqlik tamsayı) |

**Alembic kısıtı:** Her kolon ayrı `op.execute()` — asyncpg multi-statement kabul etmez.

---

### 2.2 — Model Hataları

| # | Tablo | Hata | Düzeltme |
|---|-------|------|---------|
| **D3** | `auctions.status` | `default="completed"` | `default="active"` — 🔴 yeni açık artırma tamamlanmış görünüyor |
| D1 | `listings.image_urls` | `Text` (JSON string) | `JSONB` + GIN index |
| D2 | `listings.active_room_id` | FK tanımsız | `ForeignKey("live_streams.id", ondelete="SET NULL")` ekle |
| D4 | `reports.created_at` | `DateTime(tz=False)` | `DateTime(timezone=True), server_default=func.now()` |
| D5 | `app_configs.updated_at` | `DateTime(tz=False)` | `DateTime(timezone=True)` |

---

### 2.3 — FK Düzeltmeleri (Faz 1'den)

| Tablo | Kolon | Şu An | Düzeltme |
|-------|-------|-------|---------|
| `gift_events` | `stream_id` | `ondelete="CASCADE"` | **SET NULL** |
| `bids` | `stream_id` | ondelete tanımsız | **SET NULL** |

---

### 2.4 — Faz 2 Başarı Kriterleri

```
□ Float → Numeric migration staging'de test edildi, prod'da uygulandı
□ D3: yeni açık artırma status = "active" ile başlıyor
□ listings.image_urls JSONB, GIN index var
□ gift_events + bids FK SET NULL yapıldı
□ Pydantic schema Decimal tiplere güncellendi
```

---

## Faz 3 — PostgreSQL Bağlantı ve Index Altyapısı

> Bağımlılık: Faz 2 schema düzeltilmiş olmalı.

### 3.1 — PgBouncer Aktivasyonu 🔴

**Sorun:** 4 uvicorn worker × (pool_size=20 + overflow=10) = max **120 bağlantı**.  
2 ARQ worker da bağlantı kullanır → PostgreSQL default `max_connections=100` aşılıyor.  
`config.py`: `use_pgbouncer: bool = False` — kodlanmış, aktif değil.

```
Hedef:
  API + ARQ → PgBouncer :5432 (transaction mode)
            → PostgreSQL :5433
  max 30 server bağlantısı
```

Adımlar:
1. `pgbouncer.ini`: transaction mode, DB teqlif → 127.0.0.1:5433
2. `postgresql.conf`: `port = 5433`
3. `systemd/pgbouncer.service` + bağımlılık teqlif.service'e
4. `config.py`: `use_pgbouncer = True`
5. Staging test → prod deploy

---

### 3.2 — Composite Index Stratejisi

`CREATE INDEX CONCURRENTLY` transaction içinde yasak → `op.execute()` ile ayrı migration.

| Tablo | Index | Sorgu Amacı |
|-------|-------|------------|
| `tuci_transactions` | `(user_id, created_at DESC)` | Cüzdan geçmişi |
| `purchases` | `(buyer_id, created_at DESC)` | Alım geçmişi |
| `bids` | `(stream_id, created_at DESC)` | ✅ `ix_bids_stream_created` — zaten var |
| `analytics_events` | `(user_id, created_at)` | ML sorgu hızı |
| `user_interactions` | `(user_id, created_at)` | ML sorgu hızı |
| `listing_offers` | `(listing_id, status)` | Teklif filtresi |
| `follows` | `(follower_id, followed_id)` UNIQUE | Takip kontrolü |

---

### 3.3 — Faz 3 Başarı Kriterleri

```
□ PgBouncer aktif: pg_stat_activity max 30 bağlantı
□ Composite index'ler CONCURRENTLY oluşturuldu
□ EXPLAIN ANALYZE: feed sorgusu Seq Scan yok
```

---

## Faz 4 — ClickHouse ve Redis Altyapısı

> Bağımlılık: Faz 1 R9 kararı alınmış + disk boyutu ölçülmüş olmalı.

### 4.1 — ClickHouse TTL Güncellemesi

R9 = 90 gün onaylanırsa:

```sql
ALTER TABLE user_events MODIFY TTL timestamp + INTERVAL 90 DAY;
ALTER TABLE feed_analytics MODIFY TTL timestamp + INTERVAL 90 DAY;
ALTER TABLE search_events MODIFY TTL timestamp + INTERVAL 90 DAY;
ALTER TABLE swipe_live_events MODIFY TTL timestamp + INTERVAL 90 DAY;
-- direct_sale_events: 180 gün → değişmez
```

`ALTER TABLE ... MODIFY TTL` non-blocking, mevcut veri korunur.

---

### 4.2 — ClickHouse `init_clickhouse()` Durumu

`init_clickhouse()` (database_clickhouse.py:211) **doğru çalışıyor:**
- Bootstrap bağlantı (database= yok) → `CREATE DATABASE IF NOT EXISTS teqlif_prod_analytics`
- Ana `_client` → `database=settings.clickhouse_db` ile bağlanır, tablolar doğru DB'de oluşur

05_final.md §14 "önemli bug" notu ve V1.5 item #4 **artık geçersiz** — kod düzeltilmiş.

---

### 4.3 — Redis Cache Taksonomisi (ADR §9)

| Kategori | Örnekler | TTL | Invalidate |
|----------|---------|-----|-----------|
| **SCHEMA_VERSIONED** | `/api/catalog`, `field-config` | Schema version'a bağlı | `bump_schema_version()` |
| **ALGORITHMIC** | Feed, trending, interests | 30 sn – 5 dk | TTL expire |
| **LIFECYCLE** | Auction state, stream state | Event süresi | Event-driven |
| **SECURITY_CRITICAL** | Session, token blacklist | Token ömrü | Logout |
| **EPHEMERAL** | Listing detay, user profil | 60 sn – 5 dk | Update event |

**Kural:** Her Faz 2 migration sonuna `bump_schema_version()` çağrısı ekle.

---

### 4.4 — Faz 4 Başarı Kriterleri

```
□ ClickHouse disk boyutu ölçüldü (R9 kararı öncesi)
□ R9 onaylandıysa ALTER TABLE TTL başarıyla uygulandı
□ CH tablolar teqlif_prod_analytics'te: clickhouse-client --database teqlif_prod_analytics ile doğrulandı
```

---

## Faz 5 — API ve Sorgu Optimizasyonu

> Bağımlılık: Faz 3 index'leri var, Faz 4 cache altyapısı hazır.

### 5.1 — N+1 Sorgu Düzeltmeleri

```sql
-- Feed: her listing için ayrı seller sorgusu → JOIN
SELECT l.*, u.username, u.rating_avg,
       (SELECT COUNT(*) FROM favorites WHERE listing_id = l.id) AS fav_count
FROM listings l
JOIN users u ON u.id = l.user_id
WHERE l.status = 'active'
ORDER BY l.created_at DESC, l.id DESC LIMIT 20
```

---

### 5.2 — Keyset (Cursor) Pagination

```sql
-- Şu an (OFFSET): 80 satır boşa okur
SELECT * FROM listings ORDER BY created_at DESC LIMIT 20 OFFSET 80

-- Hedef (Keyset):
SELECT * FROM listings
WHERE status = 'active'
  AND (created_at, id) < (:last_seen_at, :last_seen_id)
ORDER BY created_at DESC, id DESC LIMIT 20
```

| Endpoint | Öncelik |
|---------|---------|
| Listing feed | 🔴 |
| Cüzdan geçmişi | 🔴 |
| Bildirimler | 🟡 |

---

### 5.3 — Endpoint Cache

| Endpoint | TTL | Kategori |
|---------|-----|---------|
| `GET /listings/{id}` | 60 sn | EPHEMERAL |
| `GET /users/{id}` | 5 dk | EPHEMERAL |
| `GET /catalog/categories` | 1 saat | SCHEMA_VERSIONED |
| `GET /app-config` | 10 dk | SCHEMA_VERSIONED |
| `GET /listings/feed` | 30 sn | ALGORITHMIC |

---

### 5.4 — Faz 5 Başarı Kriterleri

```
□ Feed: Seq Scan yok (EXPLAIN ANALYZE)
□ Listing feed p95 < 200 ms (cache hit)
□ Cüzdan p95 < 100 ms (keyset + index)
□ Redis cache hit rate > %80
```

---

## Faz 6 — ARQ Worker Optimizasyonu

> Bağımlılık: Faz 1 W□ kararları alınmış olmalı.

### 6.1 — Tam ARQ Cron Listesi (Mevcut)

**teqlif-worker** (default queue, CPUWeight=50):

| Görev | Zamanlama | Not |
|-------|-----------|-----|
| `cleanup_stale_streams_task` | Her 2 dk | — |
| `cleanup_ghost_calls_task` | Her 15 dk | — |
| `flush_interactions_to_db` | Her 5 dk | Redis → PG sync |
| `sync_swipelive_interests_task` | Her 20 dk | — |
| `invalidate_swipe_live_configs_task` | Her 15 dk | Redis cache |
| `sync_ad_campaigns_task` | Her 10 dk | — |
| `compute_user_interests_task` | Her 15 dk **(W1)** | — |
| `compute_user_condition_preferences_task` | Her 15 dk **(W3)** | — |
| `compute_trending_listings_task` | Her 30 dk **(W5)** | — |
| `backfill_listing_embeddings_task` | Her 30 dk **(W2)** | — |
| `backfill_listing_quality_scores_task` | Saatlik :45 | — |
| `cleanup_expired_stories_task` | Saatlik :00 | — |
| `cleanup_hype_highlights_task` | Saatlik :00 | — |
| `populate_foryou_feed_task` | Saatlik :00 **(W4)** | — |
| `rebuild_faiss_index_task` | 2x/gün 00:00, 12:00 | CPU yüksek |
| `compute_trending_categories_task` | 4x/gün 00:06:12:18 | — |
| `cleanup_old_stream_likes_task` | Günlük 01:00 | — |
| `compute_seller_badges_task` | Günlük 01:30 | CH 30g pencere |
| `train_swipe_live_als_task` | Günlük 01:00 **(W7)** | CPU yüksek |
| `train_feed_als_task` | Günlük 01:30 **(W6)** | CPU yüksek |
| `calculate_user_budgets_task` | Günlük 02:00 | — |
| `compute_trust_scores_task` | Günlük 02:15 | CH **90g** → **BUG-1** |
| `cleanup_hidden_messages_task` | Günlük 02:30 | — |
| `cleanup_old_notifications_task` | Günlük 03:00 | — |
| `process_churn_and_airdrop` | Günlük 03:30 | — |
| `optimize_notification_timing_task` | Günlük 04:00 | CH 14g |
| `hesitation_retarget_task` | Günlük 06:00 | CH 14g |
| `deactivate_expired_listings_task` | Günlük 04:00 | — |
| `delete_expired_inactive_listings_task` | Günlük 04:30 | MinIO dahil |
| `cleanup_old_impressions_task` | Günlük 05:00 | — |
| `nsfw_backfill_task` | Günlük 05:15 | — |
| `backfill_phash_task` | Günlük 05:30 | — |
| `cleanup_old_media_messages_task` | Günlük 06:30 | MinIO dahil |
| `train_bpr_task` | Pzt+Çar+Cmt 00:30 | PG **120g** → **BUG-2** |
| `cleanup_old_analytics_task` | Haftalık Pzt 04:00 | PG >90g + VACUUM |
| `train_churn_model_task` | Haftalık Pzt 02:30 | CH **44g** → **BUG-3** |
| `cleanup_old_user_interactions_task` | Haftalık Sal 04:00 | PG >90g + VACUUM |
| `train_kmeans_cold_start_task` | Çar+Paz 02:15 | — |
| `compute_influence_scores_task` | Haftalık Paz 05:30 | — |
| `train_item2vec_task` | Haftalık Paz 02:00 | PG 90g |
| `train_listing_quality_model_task` | Haftalık Paz 02:30 | — |

**teqlif-worker-critical** (critical queue):  
Push notifications, email, webhook, ödeme görevleri.

---

### 6.2 — Gece Yük Haritası (Şu An)

```
00:00  rebuild_faiss_index + compute_trending_categories   CPU yüksek
00:30  train_bpr (Pzt/Çar/Cmt)                            CPU çok yüksek
01:00  train_swipe_live_als (W7)                           CPU yüksek
01:30  train_feed_als (W6) + compute_seller_badges         CPU yüksek
02:00  calculate_user_budgets
02:15  compute_trust_scores (BUG-1)
02:30  cleanup_hidden_messages (+ train_churn Pzt)
02:45  teqlif-backup                                       IO yüksek
03:00  cleanup_notifications + process_churn_and_airdrop
04:00  cleanup_analytics (Pzt) / optimize_notif
04:30  delete_expired_inactive_listings
05-07  nsfw_backfill, phash_backfill, cleanup tasks
```

W6+W7 haftalığa geçerse: Sal-Cmt 01:00-01:30 CPU serbest kalır.

---

### 6.3 — Faz 6 Başarı Kriterleri

```
□ W1+W4 uygulandıysa gündüz CPU baskısı azaldı
□ node5 gündüz CPU < %60 ortalama
□ Gece ML görevleri 02:45 backup'tan önce bitiyor
```

---

## Faz 7 — ML Veri Kalitesi

> Bağımlılık: Faz 4 ClickHouse TTL + R9/R9b onaylanmış.

### 7.1 — BUG-1/2/3 Düzeltmeleri

| Bug | Etkilenen Görev | Çözüm A (tercih) | Çözüm B |
|-----|----------------|-----------------|---------|
| BUG-1 | `compute_trust_scores` (CH 90g) | R9=90g → TTL artar | Pencereyi 30g'ye indir |
| BUG-2 | `train_bpr` (PG 120g) | R9b=120g → retention artar | Pencereyi 90g'ye indir |
| BUG-3 | `train_churn_model` (CH 44g) | R9=90g → TTL artar | Pencereyi 30g'ye indir |

---

### 7.2 — Tüm ML Query Window Özeti

| Görev | Kaynak | Pencere | Şu Anki Limit | Durum |
|-------|--------|---------|---------------|-------|
| `compute_user_interests` | PG analytics_events/likes/favs | 30 gün | 90g retention | ✅ |
| `train_bpr` | PG user_interactions | **120 gün** | 90g retention | ❌ BUG-2 |
| `train_item2vec` | PG user_interactions | 90 gün | 90g retention | ⚠️ Sınırda |
| `train_feed_als` | CH user_events | 30 gün | 30g TTL | ⚠️ Sınırda |
| `compute_trust_scores` | CH user_events | **90 gün** | 30g TTL | ❌ BUG-1 |
| `train_churn_model` | CH user_events | **44 gün** | 30g TTL | ❌ BUG-3 |
| `optimize_notification_timing` | CH user_events | 14 gün | 30g TTL | ✅ |
| `hesitation_retarget` | CH user_events | 14 gün | 30g TTL | ✅ |
| `compute_seller_badges` | CH user_events | 30 gün | 30g TTL | ⚠️ Sınırda |

---

### 7.3 — Faz 7 Başarı Kriterleri

```
□ trust_scores: günlük skor değişimi gözlemleniyor (90g veri aktif)
□ train_bpr: training loss düştü (120g veri aktif)
□ train_churn: 44g pencere tam doldu
```

---

## Faz 8 — Medya Optimizasyonu

> Bağımlılık: Faz 1 MinIO lifecycle policy node1+node4'ta aktif.

### 8.1 — Mevcut Durum

| Medya | Limit | Mevcut İşleme |
|-------|-------|-------------|
| İlan fotoğrafı | 5 MB | Thumb 400×400 JPEG q85; kaynak orijinal boyutta MinIO'ya |
| İlan videosu | 50 MB, 60 sn | ffmpeg `-c:v copy` (video dokunulmaz) + AAC 128k |
| DM fotoğrafı | 5 MB | Thumb 400×400 JPEG q85 |
| DM videosu | 30 MB, 90 sn | ffmpeg `-c:v copy` + AAC 128k |
| Profil fotoğrafı | 5 MB | JPEG q85 |
| Hikaye | — | H.264 re-encode ✅ |

---

### 8.2 — Sıkıştırma Kararları

| # | Değişiklik | Önce | Sonra | Karar |
|---|-----------|------|-------|-------|
| M1 | İlan fotoğrafı | JPEG as-is | WebP q80, max 1920px | □ |
| M2 | İlan videosu | `-c:v copy` | CRF 28, max 1080p, AAC 96k | □ |
| M3 | DM medya limitleri | Foto 5MB, Video 30MB | Foto 3MB, Video 20MB | □ |
| M4 | Profil fotoğrafı | JPEG q85 | WebP q75, max 800px | □ |

> M2 CPU yoğun — upload sırasında sıralı işleme zorunlu (node5 7.8 GB RAM).

---

### 8.3 — Medya Silme Boşlukları

| Durum | Şu An | Düzeltme |
|-------|-------|---------|
| Hesap silme → avatar | ⚠️ Silinmiyor | Silme akışına MinIO delete ekle (node1/node4) |
| Listing soft-delete | ✅ `delete_listing_files()` var | — |

---

### 8.4 — Faz 8 Başarı Kriterleri

```
□ Yeni ilan fotoğrafları WebP (M1 onaylandıysa)
□ Video upload ortalama < 25 MB (M2 onaylandıysa)
□ Hesap silme: avatar node1+node4'tan silindi
```

---

## Faz 9 — Güvenlik ve Uyumluluk

> Bağımlılık: Faz 2 schema, Faz 1 R11 onaylanmış.

### 9.1 — Hesap Silme ve Anonimleştirme

| Veri | Hedef |
|------|-------|
| `users.email` | `deleted_{id}@teqlif.com` |
| `users.full_name` | `Silinmiş Kullanıcı` |
| `users.profile_image_url` | MinIO delete + NULL |
| `direct_messages` içeriği | `sender_id=NULL`, `[Silinmiş mesaj]` |
| `analytics_events.user_id` | FK var → SET NULL (anonim kalır) |
| `purchases`, `transactions` | Korunur — TTK 82 zorunlu |

---

### 9.2 — KVKK Düzeltmeleri

| # | Sorun | Düzeltme |
|---|-------|---------|
| KV1 | `analytics_events.ip_address` saklanıyor | Kayıt sırasında son oktet mask: `x.x.x.0` |
| KV2 | Kullanıcı silme endpoint yok | `DELETE /users/me` → soft-delete |
| KV3 | Analytics opt-out yok | `notification_prefs`'e `analytics_opt_out: bool` ekle |

---

### 9.3 — Faz 9 Başarı Kriterleri

```
□ ip_address: yeni kayıtlar masked
□ DELETE /users/me çalışıyor, PII null
□ Hesap silme sonrası DM açılabilir (anonim)
```

---

## Faz 10 — tuci → teqlik Yeniden Adlandırma

> Bağımlılık: Tüm önceki fazlar tamamlanmış. Pure rename, veri yapısı değişikliği yok.

| Katman | Değişiklik |
|--------|-----------|
| PostgreSQL | `tuci_transactions` → `teqlik_transactions`, `tuci_balance` → `teqlik_balance` |
| Python | Model, repository, use_case, schema |
| API JSON | `tuci_balance` → `teqlik_balance` |
| Flutter | ViewModel, DTO, widget, i18n ARB |

Geçiş döneminde çift okuma → Flutter güncellendikten sonra eski kaldırılır.

---

## Ek A — node5 Kaynak Bütçesi

### RAM (7.8 GB + 8 GB Swap)

| Servis | Tahmin |
|--------|--------|
| Redis (maxmemory) | **4.0 GB** |
| FastAPI 4 worker (uvicorn) | ~1.2 GB |
| ARQ workers (2 instance) | ~400 MB |
| ClickHouse | ~500 MB |
| PostgreSQL (shared_buffers + connections) | ~500 MB |
| ML model dosyaları (FAISS, BPR, ALS) | ~800 MB – 1.5 GB |
| OS + misc | ~500 MB |
| **Toplam** | **~8–8.5 GB → Swap kullanımı normal** |

> ML eğitim görevleri (BPR, ALS, K-Means) çalışırken Swap kullanılır. W6+W7 haftalığa geçerse gece Swap baskısı azalır.

### Disk (50 GB SSD) — MinIO node5'te yok

| Depolama | Tahmin |
|---------|--------|
| OS + paketler | ~5 GB |
| Kod + Python venv | ~3 GB |
| PostgreSQL veri | değişken |
| ClickHouse (30g TTL) | VPS'te ölçülmeli |
| Redis AOF+RDB | ~200 MB |
| ML model dosyaları | ~1-3 GB |
| Yedek (local 2 gün) | ~2× günlük pg_dump + CH boyutu |
| **Serbest** | **50 GB'tan gerisi** |

> **Kritik:** R9 kararından önce `system.parts` sorgusuyla ClickHouse disk boyutunu ölç.  
> **Alarm eşiği:** node5 disk %80 → Prometheus `DiskSpaceLow` uyarı verir.

### node3 (Monitoring + Staging)

| Kaynak | Değer |
|--------|-------|
| CPU | 4c EPYC |
| RAM | ~4 GB + 4 GB Swap |
| Bant genişliği | 5 TB/ay (10 Mbit sonrası throttle) |
| Public IP | 5.249.165.10 |
| Panel zorunluluğu | 90 günde bir → son giriş: 2026-09-11, **sonraki deadline: 2026-12-10** |

---

## Ek B — Öncelik Matrisi

### Kritik — Beklemez

| # | İş | Faz |
|---|---|-----|
| P1 | PgBouncer aktivasyonu | 3.1 |
| P2 | D3: auction status default="active" | 2.2 |
| P3 | GC1: live_stream_viewers cleanup | 1.4 |
| P4 | Float → Numeric finansal kolonlar | 2.1 |
| P5 | gift_events + bids FK → SET NULL | 2.3 |

### Yüksek — 1. Sprint

| # | İş | Faz |
|---|---|-----|
| P6 | ClickHouse disk ölç → R9 kararı | 1.2 / 4.1 |
| P7 | R9b: user_interactions 90→120g kararı | 1.2 |
| P8 | MinIO lifecycle policy (node1+node4) | 1.5 |
| P9 | W1+W4: interests+feed frekans kararı | 1.6 |
| P10 | Composite index'ler | 3.2 |
| P11 | GC3: listing_offers cleanup | 1.4 |
| P12 | GC4: market_index cleanup | 1.4 |

### Orta — 2. Sprint

| # | İş | Faz |
|---|---|-----|
| P13 | Keyset pagination (feed + cüzdan) | 5.2 |
| P14 | Endpoint cache stratejisi | 5.3 |
| P15 | Feed N+1 düzeltmesi | 5.1 |
| P16 | W2: backfill gündüz → gece | 6.1 |
| P17 | W3+W5 frekans azaltımı | 6.1 |
| P18 | KV1: ip_address maskeleme | 9.2 |
| P19 | GC2: calls cleanup | 1.4 |
| P20 | D1: listings.image_urls → JSONB | 2.2 |

### Düşük — 3. Sprint

| # | İş | Faz |
|---|---|-----|
| P21 | Medya WebP + video re-encode (M1-M4) | 8.2 |
| P22 | W6+W7: ALS haftalığa geçiş | 6.1 |
| P23 | Hesap silme akışı (KVKK) | 9.1 |
| P24 | GC5-GC7 diğer cleanup | 1.4 |
| P25 | tuci → teqlik rename | 10 |
