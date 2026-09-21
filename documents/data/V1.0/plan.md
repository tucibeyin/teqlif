# teqlif — Veri Yönetim Fazları

**Stack:** FastAPI + PostgreSQL + Redis + ClickHouse + MinIO | Flutter  
**Üretim:** node5 (4c EPYC, 16 GB RAM, 500 GB SSD, 1 Gbps) | node3 (staging + AI proxy + monitoring)  
**Referans:** `deploy/scale/V1.4/documents/05_final.md` · `documents/teqlif_architectural_decisions.md`

---

## Notasyon

`□` karar bekleniyor · `■` onaylandı · `✅` var, çalışıyor · `⚠️` eksik veya bozuk  
`🔴` kritik · `🟡` orta · `🟢` düşük · **BUG** mevcut kod hatası

---

## Bağımlılık Haritası (Fazları Okumadan Önce)

### Fazlar Arası Bağımlılık

```
Faz 1 (Lifecycle kararları)
  │
  ├──► Faz 2 (Schema) — Float→Numeric, JSONB
  │         │
  │         └──► Faz 3 (PG Altyapı) — PgBouncer, Index
  │                   │
  │                   └──► Faz 4 (CH + Redis) — ClickHouse fix, TTL
  │                             │
  │         ┌───────────────────┘
  │         │
  ├──► Faz 5 (Sorgu + Cache) — N+1, pagination, cache
  │
  ├──► Faz 6 (ARQ Zamanlama) — W1-W7 frekans değişiklikleri
  │         │
  │         └──► Faz 7 (ML Kalitesi) — BUG-1/2/3 fix, model frekansları
  │
  ├──► Faz 8 (Medya) — sıkıştırma, lifecycle, temizlik
  │
  ├──► Faz 9 (Güvenlik + KVKK) — hesap silme, anonimleştirme
  │
  └──► Faz 10 (Rename) — tuci → teqlik, sonra yapılır
```

### Kritik Retention-Kod Uyumsuzlukları (Mevcut Buglar)

Aşağıdaki üç sorun **Faz 1 kararlarıyla birlikte kapatılır** — retention uzatılmazsa kod davranışı bozuk kalmaya devam eder:

| # | Servis | Sorgulanan Pencere | Şu Anki TTL/Retention | Kayıp |
|---|--------|--------------------|----------------------|-------|
| **BUG-1** | `compute_trust_scores_task` | ClickHouse 90 gün | TTL **30 gün** | Son 60 gün trust sinyali yok |
| **BUG-2** | `train_bpr_task` | `user_interactions` 120 gün | Retention **90 gün** | Son 30 gün BPR eğitim verisi kayıp |
| **BUG-3** | `train_churn_model_task` | ClickHouse 44 gün | TTL **30 gün** | Son 14 gün churn sinyali yok |

### R3 → R5 CASCADE Tehlikesi

`gift_events.stream_id FK: ondelete="CASCADE"` → `live_streams` silinince `gift_events` de siliniyor.  
`gift_events` finansal transfer kaydıdır. R3 kararı verilmeden önce bu FK **SET NULL'a** çevrilmeli.

---

## Faz 1 — Veri Yaşam Döngüsü ve Zamanlama

> Bu fazın kararları alınmadan diğer fazlar başlamaz. □ satırlar tartışılacak.

### 1.1 — Retention Karar Tablosu

**Grup A: ML Veri Kalitesi — BUG-1/2/3 ile Bağlantılı (Önce Bunlar)**

| # | Tablo / Sistem | Şu Anki | Öneri | Endüstri Standardı | Etkilenen Sistem | Karar |
|---|----------------|---------|-------|-------------------|-----------------|-------|
| **R9** | `user_events` ClickHouse TTL | 30 gün | **90 gün** | Mixpanel 90g · Amplitude 12ay · Google 14ay | BUG-1 (trust 90g) · BUG-3 (churn 44g) · feed_als (30g sınırda) | □ |
| **R9b** | `user_interactions` PG | 90 gün | **120 gün** | Collaborative filtering: 3-6 ay (Netflix, Spotify) | BUG-2 (BPR 120g) · item2vec (90g) | □ |
| R9c | `feed_analytics` ClickHouse TTL | 30 gün | R9 ile aynı | — | feed sorguları | □ |
| R9d | `swipe_live_events` ClickHouse TTL | 30 gün | R9 ile aynı | — | SwipeLive ALS | □ |

> Disk etkisi: TTL 30→90 gün → ClickHouse disk yılda ~40 GB daha büyür. node5 bütçesi içinde kalır.

**Grup B: Canlı Yayın — Birlikte Karar Ver**

| # | Tablo | Şu Anki | Öneri | Endüstri Standardı | Bağımlılık | Karar |
|---|-------|---------|-------|-------------------|-----------|-------|
| **R3** | `live_streams` (biten) | Sonsuz | **1 yıl** | Marketplace: 1 yıl yeterli | R1 + R5 CASCADE bağımlı — **R3 ≤ R5 olmalı** | □ |
| **R1** | `live_stream_viewers` | ⚠️ Sonsuz | **90 gün** | Twitch/YT: bireysel log 30-90g, sonra aggregate | R3 CASCADE zaten siler | □ |
| **R5** | `gift_events` | Sonsuz | **Sonsuz + FK SET NULL** | Finansal transfer: TTK 82 → 10 yıl zorunlu | Önce `gift_events.stream_id` → SET NULL yapılmalı, sonra R3 | □ |
| **R4** | `bids` | Sonsuz | **2 yıl** | Açık artırma kaydı: 2 yıl (eBay/Amazon standardı) | `bids.stream_id` ondelete yok (restrict) → SET NULL yapılmalı | □ |

**Grup C: Mesajlaşma — Birlikte Karar Ver**

| # | Tablo | Şu Anki | Öneri | Endüstri Standardı | Bağımlılık | Karar |
|---|-------|---------|-------|-------------------|-----------|-------|
| **R7** | `direct_messages` (text) | Sonsuz | **Sonsuz** | WhatsApp/Telegram/Instagram DM: sonsuz. Pazar yeri: alışveriş geçmişi değerli | R8 bağımlı | □ |
| R8 | `message_threads` | Sonsuz | R7'ye bağlı | R7=sonsuz → sorun yok | R7=sonsuz → □ Sonsuz |

**Grup D: Ticaret — Yasal Zorunluluk**

| Tablo | Karar | Yasal Dayanak |
|-------|-------|--------------|
| `purchases` | ■ Sonsuz | TTK 82 + VUK 253: 10 yıl zorunlu |
| `tuci_transactions` | ■ Sonsuz | TTK 82 + VUK 253: 10 yıl zorunlu |
| `direct_sales` / `direct_sale_orders` | ■ Sonsuz | Ticaret kaydı |
| `auctions` | □ Sonsuz mu? | TTK 82: 10 yıl önerilir |

**Grup E: Diğer**

| # | Tablo | Şu Anki | Öneri | Endüstri Standardı | Karar |
|---|-------|---------|-------|-------------------|-------|
| R2 | `calls` (ended/missed) | Sonsuz | **1 yıl** | 5651 Kanunu: telekom log 2 yıl; app çağrısı 1 yıl yeterli | □ |
| R6 | `listing_offers` (declined) | Sonsuz | **60 gün** | Marketplace: 30-90 gün | □ |
| R10 | `exchange_rates` | Sonsuz | **2 yıl** | Vergi amaçlı: 7-10 yıl; uygulama gösterimi için 2 yıl yeterli | □ |
| R11 | Hesap silme → DM | Sonsuz | **Anonimleştir** | GDPR/KVKK: sender_id=NULL + "Silinmiş kullanıcı" | □ |

---

### 1.2 — Mevcut Temizleme Mekanizmaları (ARQ Cron)

Zaten çalışan cleanup görevleri — Faz 1 kararlarında referans olarak kullanılır:

| Görev | Zamanlama | Silen Veri | Durum |
|-------|-----------|-----------|-------|
| `cleanup_stale_streams_task` | Her 2 dk | `live_streams` stale (>3 dk) | ✅ |
| `cleanup_ghost_calls_task` | Her 15 dk | `calls` ghost (calling>5dk, active>1sa) | ✅ |
| `cleanup_expired_stories_task` | Saatlik | `stories` + MinIO `stories/` | ✅ |
| `cleanup_hype_highlights_task` | Saatlik | `highlights` (expired) + local disk | ✅ |
| `cleanup_old_stream_likes_task` | Günlük 01:00 | `stream_likes` >7 gün | ✅ |
| `cleanup_hidden_messages_task` | Günlük 02:30 | `direct_messages` (hidden + >60 gün) | ✅ |
| `cleanup_old_notifications_task` | Günlük 03:00 | `notifications` >30 gün | ✅ |
| `deactivate_expired_listings_task` | Günlük 04:00 | `listings` aktif >30 gün → pasif | ✅ |
| `delete_expired_inactive_listings_task` | Günlük 04:30 | `listings` pasif >60 gün → soft-delete + MinIO | ✅ |
| `cleanup_old_analytics_task` | Haftalık Pzt 04:00 | `analytics_events` >90 gün + VACUUM | ✅ |
| `cleanup_old_user_interactions_task` | Haftalık Sal 04:00 | `user_interactions` >90 gün + VACUUM | ✅ |
| `cleanup_old_impressions_task` | Günlük 05:00 | `listing_impressions` >30 gün | ✅ |
| `cleanup_old_media_messages_task` | Günlük 06:30 | `direct_messages` media >7 gün + MinIO | ✅ |

---

### 1.3 — Yeni GC Görevleri

R1-R10 kararları alındıktan sonra uygulanacak cleanup görevleri:

| # | Yeni Görev | Tablo | Silme Koşulu | Öneri Zamanlama | Öncelik |
|---|-----------|-------|-------------|----------------|---------|
| **GC1** | `cleanup_old_stream_viewers_task` | `live_stream_viewers` | `joined_at < 90 gün` (R1'e bağlı) | Haftalık Çar 04:00 | 🔴 |
| GC2 | `cleanup_old_calls_task` | `calls` (ended/missed) | `ended_at < 1 yıl` (R2'ye bağlı) | Haftalık Per 04:00 | 🟡 |
| GC3 | `cleanup_old_listing_offers_task` | `listing_offers` (declined/expired) | `created_at < 60 gün` (R6) | Haftalık Cum 04:00 | 🟡 |
| GC4 | `cleanup_old_exchange_rates_task` | `exchange_rates` | `date < 2 yıl` (R10) | Aylık 1. gün 05:00 | 🟢 |
| GC5 | `cleanup_old_streams_task` | `live_streams` (biten) | `ended_at < 1 yıl` (R3'e bağlı) | Aylık 1. gün 06:00 | 🟡 |
| GC6 | `cleanup_empty_message_threads_task` | `message_threads` | 0 mesaj + >30 gün (R8'e bağlı) | Haftalık Paz 05:00 | 🟢 |
| GC7 | `cleanup_old_gift_events_task` | `gift_events` | **Sadece R5 → SET NULL sonrası** | Aylık 1. gün 04:00 | 🟡 |
| GC8 | `cleanup_inactive_search_alerts_task` | `search_alerts` | `updated_at < 180 gün + status=active` | Haftalık Paz 06:00 | 🟢 |

---

### 1.4 — MinIO Lifecycle Policy

`mc ilm add` ile bucket başına S3 lifecycle kuralı — güvenlik ağı:

| Bucket | Lifecycle TTL | Gerekçe |
|--------|-------------|---------|
| `teqlif/listings/` | 365 gün | Uygulama silme çağrısı kaçırılırsa |
| `teqlif/stories/` | 2 gün | expires_at cleanup kaçırılırsa |
| `teqlif-dm/` | 14 gün | 7 günlük cron kaçırılırsa |

---

### 1.5 — ARQ Zamanlama Kararları

W1 ↔ W4 bağımlı — birlikte karar ver.

| # | Görev | Şu An | Öneri | Bağımlılık | Etki | Karar |
|---|-------|-------|-------|-----------|------|-------|
| **W1** | `compute_user_interests_task` | Her 15 dk (96x/gün) | **2x/gün** (08:00, 20:00) | → W4 ile birlikte | ClickHouse 94 sorgu/gün azalır | □ |
| **W4** | `populate_foryou_feed_task` | Saatlik (24x/gün) | **W1 ile: 2-4x/gün** | W1'e bağımlı | 18-22 hesaplama/gün azalır | □ W1 ile |
| W2 | `backfill_listing_embeddings_task` | Her 30 dk (gündüz) | Sadece gece (02:00–04:00) | Bağımsız | Gündüz CPU serbest | □ |
| W3 | `compute_user_condition_preferences_task` | Her 15 dk | 4x/gün | Bağımsız | Redis işlemi azalır | □ |
| W5 | `compute_trending_listings_task` | Her 30 dk | 4x/gün | Bağımsız | CH 44 sorgu/gün azalır | □ |
| W6 | `train_feed_als_task` | Günlük | Haftalık (ADR §3.3) | R9 bağımlı | Gece CPU azalır | □ |
| W7 | `train_swipe_live_als_task` | Günlük | Haftalık (ADR §3.3) | R9 bağımlı | Gece CPU azalır | □ |

---

### 1.6 — Faz 1 Başarı Kriterleri

```
□ Tüm R□ kararları onaylandı
□ GC1-GC8 görevleri hangileri uygulanacak belirlendi
□ MinIO lifecycle policy 3 bucket'ta aktif
□ W1-W7 kararları alındı (en az W1+W4)
□ R5 FK değişikliği (CASCADE → SET NULL) planlandı
```

---

## Faz 2 — PostgreSQL Veri Yapısı

> Bağımlılık: Faz 1 kararları alınmış olmalı. Schema düzeltilmeden index ve cache katmanı anlamsız.

### 2.1 — Finansal Tip Düzeltmeleri: Float → Numeric 🔴

Float IEEE 754 yuvarlama hatası taşır — finansal değerlerde kullanılamaz.

| Tablo | Kolon | Şu Anki | Olması Gereken |
|-------|-------|---------|----------------|
| `listings` | `price`, `buy_it_now_price`, `last_sold_price`, `last_start_price` | `Float` | `Numeric(12, 2)` |
| `auctions` | `start_price`, `buy_it_now_price`, `final_price` | `Float` | `Numeric(12, 2)` |
| `bids` | `amount` | `Float` | `Numeric(12, 2)` |
| `purchases` | `price` | `Float` | `Numeric(12, 2)` |
| `listing_offers` | `amount` | `Float` | `Numeric(12, 2)` |
| `search_alerts` | `max_price` | `Float` | `Numeric(12, 2)` |
| `users` | `max_budget` | `Float` | `Numeric(12, 2)` |
| `exchange_rates` | `usd_try`, `eur_try` | `Float` | `Numeric(10, 4)` |
| `direct_sales` | `price` | `Numeric(10, 2)` | ✅ Doğru |
| `tuci_transactions` | `amount` | `Integer` | ✅ Doğru (teqlik tamsayı) |

**Alembic kısıtı:** Her kolon ayrı `op.execute()` — asyncpg multi-statement prepared statement kabul etmez.  
**Pydantic:** API schema'da karşılık gelen `float` alanlar `Decimal` olacak.

---

### 2.2 — Model Hataları

| # | Tablo | Hata | Düzeltme |
|---|-------|------|---------|
| D1 | `listings.image_urls` | `Text` (JSON string) | `JSONB` — GIN index, doğrudan dizi sorgusu |
| D2 | `listings.active_room_id` | FK tanımsız | `ForeignKey("live_streams.id", ondelete="SET NULL")` ekle |
| D3 | `auctions.status` | `default="completed"` | `default="active"` — 🔴 yeni açık artırma tamamlanmış görünüyor |
| D4 | `reports.created_at` | `DateTime(tz=False) + utcnow()` | `DateTime(timezone=True), server_default=func.now()` |
| D5 | `app_configs.updated_at` | `DateTime(tz=False)` | `DateTime(timezone=True)` |
| D6-D7 | `analytics_events`, `user_interactions` | Legacy `Column()` API | `Mapped[]` (tutarlılık) |
| D8 | `app_configs.value` | `String` (unbounded) | `String(4096)` |

---

### 2.3 — JSONB Dönüşümleri

| Tablo | Kolon | Şu Anki | Öneri | Kazanım |
|-------|-------|---------|-------|---------|
| `listings` | `image_urls` | `Text` | `JSONB` | GIN index, `@>` sorgusu, ilk görseli DB'de al |
| `users` | `notification_prefs` | `JSON` | `JSONB` | İndekslenebilir |

---

### 2.4 — FK Düzeltmeleri (Faz 1'den)

Faz 1 kararlarıyla birlikte yapılacak FK değişiklikleri:

| Tablo | Kolon | Şu An | Düzeltme | Gerekçe |
|-------|-------|-------|---------|---------|
| `gift_events` | `stream_id` | CASCADE | **SET NULL** | Finansal kayıt — stream silinince kaybolmamalı |
| `bids` | `stream_id` | (ondelete yok = RESTRICT) | **SET NULL** | Stream silinince teklif kaydı takılmamalı |

---

### 2.5 — Faz 2 Başarı Kriterleri

```
□ Float → Numeric migration staging'de test edildi
□ D3: yeni açık artırma status = "active" başlıyor
□ listings.image_urls JSONB, GIN index var
□ gift_events + bids FK SET NULL yapıldı
□ API schema Decimal tipler güncellendi
```

---

## Faz 3 — PostgreSQL Bağlantı ve Index Altyapısı

> Bağımlılık: Faz 2 schema düzeltmeleri yapılmış olmalı.

### 3.1 — PgBouncer Aktivasyonu 🔴

**Sorun:** 4 ARQ worker × 30 bağlantı = 120 > PG `max_connections=100` → bağlantı sınırı aşılıyor.  
`config.py`'de `use_pgbouncer: bool = False` — kodlanmış, sadece True yapılması yeterli.

```
Şu An: API + ARQ → doğrudan PostgreSQL :5432
Hedef: API + ARQ → PgBouncer :5432 → PostgreSQL :5433
Pool: transaction mode, max 30 PG bağlantısı
```

Adımlar:
1. `pgbouncer.ini` yapılandırması — transaction mode, 30 server conn
2. `systemd/pgbouncer.service` + `WantedBy=teqlif.service`
3. `config.py`: `use_pgbouncer = True`
4. Staging test → prod deploy

---

### 3.2 — Composite Index Stratejisi

`CREATE INDEX CONCURRENTLY` transaction içinde yasak — env.py transaction kullandığı için `op.execute()` ile ayrı migration gerekli.

| Tablo | Index | Sorgu Amacı |
|-------|-------|------------|
| `live_streams` | `(stream_id, status)` | Aktif yayın sorgusu |
| `tuci_transactions` | `(user_id, created_at DESC)` | Cüzdan geçmişi |
| `listing_offers` | `(listing_id, status)` | Teklife göre filtre |
| `follows` | `(follower_id, followed_id)` UNIQUE | Takip kontrolü |
| `purchases` | `(buyer_id, created_at DESC)` | Alım geçmişi |
| `bids` | `(stream_id, created_at DESC)` | Açık artırma teklif geçmişi |
| `analytics_events` | `(user_id, created_at)` | ML sorgu hızı |
| `user_interactions` | `(user_id, created_at)` | ML sorgu hızı |

---

### 3.3 — Faz 3 Başarı Kriterleri

```
□ PgBouncer aktif: pg_stat_activity → max 30 bağlantı, wait = 0
□ Tüm composite index'ler CONCURRENTLY oluşturuldu
□ EXPLAIN ANALYZE: feed sorgusu Seq Scan yok
```

---

## Faz 4 — ClickHouse ve Redis Altyapısı

> Bağımlılık: Faz 1 R9 kararı alınmış olmalı.

### 4.1 — ClickHouse: init_clickhouse() Bug Düzeltmesi 🔴

```python
# Hatalı (database_clickhouse.py init_clickhouse):
_client = await clickhouse_connect.get_async_client(
    host=settings.clickhouse_host,
    port=settings.clickhouse_port,
    # database= eksik → tablolar "default" DB'ye yazılıyor
)

# Doğru:
_client = await clickhouse_connect.get_async_client(
    host=settings.clickhouse_host,
    port=settings.clickhouse_port,
    database=settings.clickhouse_db,  # "teqlif_prod_analytics"
)
```

`get_clickhouse_client()` doğru, sadece `init_clickhouse()` bozuk.

---

### 4.2 — ClickHouse TTL Güncellemesi (Faz 1 R9 Kararına Bağlı)

R9 = 90 gün onaylanırsa DDL TTL'leri güncellenir:

```sql
ALTER TABLE user_events MODIFY TTL timestamp + INTERVAL 90 DAY;
ALTER TABLE feed_analytics MODIFY TTL timestamp + INTERVAL 90 DAY;
ALTER TABLE search_events MODIFY TTL timestamp + INTERVAL 90 DAY;
ALTER TABLE swipe_live_events MODIFY TTL timestamp + INTERVAL 90 DAY;
-- direct_sale_events: 180 gün → değişmez
```

`ALTER TABLE ... MODIFY TTL` non-blocking, mevcut veri korunur.

---

### 4.3 — Redis Cache Taksonomisi

Mevcut DB0/DB1 ayrımı korunur (`05_final.md`). Yeni cache key'ler `cache:` prefix'iyle eklenir.

| Kategori (ADR §9) | Örnekler | TTL |
|-------------------|---------|-----|
| **SCHEMA_VERSIONED** | `/api/catalog`, `field-config` | Schema migration'da `bump_schema_version()` ile invalidate |
| **ALGORITHMIC** | Feed, trending, user_interests | 30 sn – 5 dk |
| **LIFECYCLE** | Auction state, stream state | Event-driven invalidate |
| **SECURITY_CRITICAL** | Session, token blacklist | Token ömrü — dokunulmaz |
| **EPHEMERAL** | Listing detay, user profil | 60 sn – 5 dk |

**Kural:** Faz 2'deki her migration sonuna `bump_schema_version()` çağrısı ekle.

---

### 4.4 — Faz 4 Başarı Kriterleri

```
□ D51b fix: analytics "teqlif_prod_analytics" DB'ye yazılıyor
□ CH TTL ALTER TABLE başarıyla çalıştı (staging önce)
□ Redis DB0/DB1 namespace bozulmadı
```

---

## Faz 5 — API ve Sorgu Optimizasyonu

> Bağımlılık: Faz 3 index'leri mevcut olmalı, Faz 4 cache altyapısı hazır olmalı.

### 5.1 — N+1 Sorgu Düzeltmeleri

**Feed sorgusu:**
```sql
-- Şu an: listing başına ayrı seller sorgusu (N+1)
SELECT * FROM listings LIMIT 20;
-- Her listing için: SELECT * FROM users WHERE id = ?

-- Düzeltme:
SELECT l.*, u.username, u.rating_avg,
       (SELECT COUNT(*) FROM favorites WHERE listing_id = l.id) AS fav_count
FROM listings l
JOIN users u ON u.id = l.user_id
WHERE l.status = 'active'
ORDER BY l.created_at DESC, l.id DESC LIMIT 20
```

| Sorun | Endpoint | Fix |
|-------|---------|-----|
| Satıcı bilgisi N+1 | Feed, arama | `JOIN users` |
| Favori durumu N+1 | Feed, detay | Toplu `IN (...)` |
| Teklif sayısı N+1 | Feed | `COUNT` subquery |

---

### 5.2 — Keyset (Cursor) Pagination

```sql
-- Şu an (OFFSET): 100 satır okur, 80'ini atar
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
| Mesaj geçmişi | 🟡 (thread_id sonrası) |

---

### 5.3 — Endpoint Cache Stratejisi

| Endpoint | TTL | Cache Kategorisi | Invalidate Tetikleyicisi |
|---------|-----|-----------------|------------------------|
| `GET /listings/{id}` | 60 sn | EPHEMERAL | Listing güncelleme |
| `GET /users/{id}` | 5 dk | EPHEMERAL | Profil güncelleme |
| `GET /catalog/categories` | 1 saat | SCHEMA_VERSIONED | `bump_schema_version()` |
| `GET /app-config` | 10 dk | SCHEMA_VERSIONED | Config güncelleme |
| `GET /listings/feed` | 30 sn | ALGORITHMIC | TTL expire |
| `GET /listings/{id}/offers` | 30 sn | LIFECYCLE | Teklif oluşturma/güncelleme |

---

### 5.4 — JSONB Sorgu Optimizasyonu

Faz 2'de `listings.image_urls` JSONB'ye çevrildikten sonra:

```sql
-- GIN index ile: belirli URL içeren ilanlar
SELECT id FROM listings WHERE image_urls @> '["https://..."]'::jsonb;

-- İlk görseli doğrudan al:
SELECT image_urls->0 AS first_image FROM listings WHERE id = :id;
```

---

### 5.5 — Faz 5 Başarı Kriterleri

```
□ Feed sorgusu: Seq Scan yok (EXPLAIN ANALYZE)
□ Listing feed p95 < 200 ms (cache hit)
□ Listing detay p95 < 150 ms (cache hit)
□ Cüzdan geçmişi p95 < 100 ms (keyset + index)
□ Redis hit rate > %80
```

---

## Faz 6 — ARQ Worker Optimizasyonu

> Bağımlılık: Faz 1 W□ kararları alınmış olmalı.

### 6.1 — Zamanlama Değişiklikleri

Faz 1.5'te onaylanan W□ kararları burada uygulanır — `worker.py` cron_jobs listesi güncellenir.

**W1 + W4 örneği:**
```python
# Önceki:
cron(compute_user_interests_task, minute={0, 15, 30, 45}),
cron(populate_foryou_feed_task, minute=0),

# Sonrası (W1+W4 onaylanırsa):
cron(compute_user_interests_task, hour={8, 20}, minute=0),
cron(populate_foryou_feed_task, hour={0, 6, 12, 18}, minute=15),
```

---

### 6.2 — Gece Yük Haritası (Şu An)

Değişikliklerin etkisini görmek için referans:

```
00:00  rebuild_faiss_index          CPU: yüksek
00:30  train_bpr (Pzt/Çar/Cmt)     CPU: çok yüksek
01:00  train_swipe_live_als         CPU: yüksek
01:30  train_feed_als               CPU: yüksek
02:00  calculate_user_budgets
02:15  compute_trust_scores
02:45  teqlif-backup                IO: yüksek
03:00–06:30  cleanup görevleri
```

W6+W7 haftalığa geçerse: 5 gece 01:00–01:30 arası CPU serbest kalır.

---

### 6.3 — Faz 6 Başarı Kriterleri

```
□ W1+W4: compute_user_interests gündüz CPU baskısı azaldı
□ W2: backfill_embeddings yalnızca 02:00-04:00 çalışıyor
□ node5 CPU gündüz < %60 ortalama
```

---

## Faz 7 — ML Veri Kalitesi

> Bağımlılık: Faz 4 ClickHouse TTL güncellemesi yapılmış + Faz 1 R9/R9b onaylanmış olmalı.

### 7.1 — BUG-1/2/3 Düzeltmeleri

**BUG-1 ve BUG-3: ClickHouse TTL (R9 ile kapatılır)**

R9 = 90 gün onaylanırsa:
- `compute_trust_scores_task`: 90 günlük pencere tam görünür → trust skor düzelir
- `train_churn_model_task`: 44 günlük pencere tam görünür → churn düzelir
- `feed_als`, `compute_user_interests`, `seller_badges`: 30 günlük pencereler tam görünür

**BUG-2: user_interactions retention (R9b ile kapatılır)**

R9b = 120 gün onaylanırsa:
- `cleanup_old_user_interactions_task` retention 90 → 120 güne güncellenir
- `train_bpr_task`: 120 günlük pencere tam görünür → BPR eğitim kalitesi artar
- `train_item2vec_task`: 90 günlük pencere içinde kalır ✅

---

### 7.2 — Model Eğitim Frekansları (ADR §3.3 ile Hizalama)

| Model | Şu An | ADR Önerisi | Karar (W6/W7) |
|-------|-------|------------|---------------|
| BPR | Pzt+Çar+Cmt | ✅ 3x/hafta | Değişmez |
| K-Means | Çar+Paz | ✅ 2x/hafta | Değişmez |
| Feed ALS | Günlük | Haftalık (ADR) | □ W6 |
| SwipeLive ALS | Günlük | Haftalık (ADR) | □ W7 |
| Item2Vec | Haftalık | ✅ Haftalık | Değişmez |
| Churn | Haftalık | ✅ Haftalık | Değişmez |
| Quality | Haftalık | ✅ Haftalık | Değişmez |

---

### 7.3 — ClickHouse Analytics Akışı

```
Flutter / API
    │
    ▼
buffer_user_event() → Redis ch_buf:user_events (DB0)
                           │
                      flush_loop() her 30 sn veya 5000 satır
                           │
                      ClickHouse INSERT (batch)
                      → teqlif_prod_analytics.user_events
                           │
                      MergeTree TTL (R9 kararına göre)
                      + MergeTree arka plan merge
```

---

### 7.4 — Faz 7 Başarı Kriterleri

```
□ trust_scores: günlük skor farklılığı gözlemleniyor (90 günlük veri aktif)
□ BPR: 120 günlük pencere training loss düştü
□ churn_model: 44 günlük pencere görünür
□ CH INSERT'ler "teqlif_prod_analytics" DB'ye gidiyor (D51b fix onayı)
```

---

## Faz 8 — Medya Optimizasyonu

> Bağımlılık: Faz 1 MinIO lifecycle policy aktif olmalı. M□ kararları alınmış olmalı.

### 8.1 — Mevcut Durum

| Medya | Limit | Mevcut İşleme | Sorun |
|-------|-------|-------------|-------|
| İlan fotoğrafı | 5 MB | Thumb 400×400 JPEG q85 | Kaynak orijinal boyutta saklanıyor |
| İlan videosu | 50 MB, 60 sn | ffmpeg `-c:v copy` (video dokunulmaz) + AAC 128k | Video yeniden kodlanmıyor |
| DM fotoğrafı | 5 MB | Thumb 400×400 JPEG q85 | — |
| DM videosu | 30 MB, 90 sn | ffmpeg `-c:v copy` + AAC | Video yeniden kodlanmıyor |
| Profil fotoğrafı | 5 MB | JPEG q85 | Eski avatar güncellenmede siliniyor |
| Hikaye | — | ffmpeg H.264 re-encode | ✅ |

---

### 8.2 — Sıkıştırma Kararları (Faz 1.5'ten M□)

| # | Değişiklik | Önce | Sonra | Etki |
|---|-----------|------|-------|------|
| M1 | İlan fotoğrafı formatı | JPEG as-is | WebP q80, max 1920px | ~%35 küçük |
| M2 | İlan videosu | `-c:v copy` | CRF 28, max 1080p, AAC 96k | ~%50 küçük |
| M3 | DM medya limitleri | Foto 5MB, Video 30MB | Foto 3MB, Video 20MB | Bandwidth azalır |
| M4 | Profil fotoğrafı | JPEG q85, 5MB | WebP q75, max 800px | ~%40 küçük |

---

### 8.3 — Medya Silme Boşlukları

| Durum | Şu An | Düzeltme |
|-------|-------|---------|
| Kullanıcı hesabı silinince avatar | ⚠️ Silinmiyor | Hesap silme akışına `storage.delete_object(avatar_url)` ekle |
| Listing owner silinince listing fotoğrafları | ⚠️ `user_id FK` SET NULL, dosyalar kalır | MinIO lifecycle güvenlik ağı (Faz 1.4) |

---

### 8.4 — Faz 8 Başarı Kriterleri

```
□ Yeni ilan fotoğrafları WebP formatında MinIO'da
□ İlan videosu ortalama boyutu < 25 MB
□ Profil fotoğrafı ortalama boyutu < 200 KB
□ Hesap silme akışı avatarı MinIO'dan siliyor
```

---

## Faz 9 — Güvenlik ve Uyumluluk

> Bağımlılık: Faz 2 schema, Faz 1 R11 onaylanmış olmalı.

### 9.1 — Hesap Silme ve Anonimleştirme (KVKK)

Kullanıcı hesabı silindiğinde:

| Veri | Şu Anki Durum | Hedef Davranış |
|------|--------------|---------------|
| `users` satırı | Yok (hard delete mi?) | Soft-delete: `status='deleted'`, PII alanları null |
| `users.email` | Saklanıyor | → `deleted_{id}@teqlif.com` |
| `users.full_name` | Saklanıyor | → `Silinmiş Kullanıcı` |
| `users.profile_image_url` | Saklanıyor | MinIO'dan sil + null |
| `direct_messages` içeriği | Saklanıyor | `sender_id = NULL`, content: `[Silinmiş mesaj]` |
| `analytics_events` | `user_id SET NULL` (FK var) | ✅ Anonim kalır |
| `purchases`, `transactions` | FK | Saklanır — yasal zorunluluk |
| MinIO avatar | — | Silme akışına ekle |

---

### 9.2 — KVKK Öncelikli Düzeltmeler

| # | Sorun | Düzeltme |
|---|-------|---------|
| KV1 | `analytics_events.ip_address` saklanıyor | Son oktet mask: `192.168.1.x` — kayıt sırasında maskeleme |
| KV2 | Kullanıcı veri silme talebi için endpoint yok | `DELETE /users/me` → soft-delete akışı |
| KV3 | Analytics opt-out yok | `notification_prefs` JSON'a `analytics_opt_out: bool` ekle |

---

### 9.3 — Mesajlaşma Gizliliği

`direct_messages` thread yapısı:

```
message_threads (konuşma)
    │
    └── direct_messages (mesajlar)
           ├── content_type = text   → R7 kararına göre retention
           ├── content_type = media  → ✅ 7 gün + MinIO cleanup
           ├── is_hidden = true      → ✅ 60 gün cleanup
           └── is_shadowbanned       → görünmez, R7 kararına göre

Thread → sender hesabı silinince → sender_id = NULL, içerik [Silinmiş mesaj]
```

---

### 9.4 — Faz 9 Başarı Kriterleri

```
□ ip_address: tüm yeni kayıtlar masked
□ DELETE /users/me: PII null, MinIO temizlendi
□ Hesap silme sonrası DM thread'i açılabilir (anonimleştirilmiş)
```

---

## Faz 10 — tuci → teqlik Yeniden Adlandırma

> Bağımlılık: Tüm önceki fazlar tamamlanmış olmalı. Bu faz pure rename — veri yapısı değişikliği yok.

### 10.1 — Kapsam

| Katman | Değişiklik |
|--------|-----------|
| PostgreSQL | `tuci_transactions` → `teqlik_transactions`, `tuci_balance` → `teqlik_balance` |
| Python | Model, repository, use_case, schema sınıf/alan adları |
| API JSON | Response field: `tuci_balance` → `teqlik_balance` |
| Flutter | ViewModel, DTO, widget, i18n ARB anahtarları |

### 10.2 — Deploy Stratejisi

```
1. Alembic: sütun rename migration (ALTER TABLE ... RENAME COLUMN)
2. Python: çift okuma — hem eski hem yeni field name geçici dönem
3. API: geçiş döneminde dual-key response (teqlik_balance + tuci_balance)
4. Flutter: dual-key okuma → yeni field öncelikli
5. Eski field'lar kaldırılır
```

---

### 10.3 — Faz 10 Başarı Kriterleri

```
□ DB: tuci_transactions → teqlik_transactions migration başarılı
□ API: sadece teqlik_balance dönüyor (tuci_balance kaldırıldı)
□ Flutter: balance gösterimi çalışıyor
□ i18n: ARB dosyalarında tuci referansı kalmadı
```

---

## Ek A — Node Kaynak Bütçesi

### node5 — Production Core

**Donanım:** 4 core EPYC 7282, 16 GB RAM, 500 GB SSD, 1 Gbps unmetered

| Servis | RAM | Disk |
|--------|-----|------|
| PostgreSQL | ~3 GB | ~50 GB (+1 GB/ay) |
| Redis | 4 GB (maxmemory) | ~500 MB (AOF+RDB) |
| ClickHouse | ~2 GB | ~20 GB/yıl (TTL=30g) → ~60 GB/yıl (TTL=90g) |
| MinIO | ~500 MB | ~200 GB |
| FastAPI (4 worker) | ~2 GB | — |
| ARQ workers (2) | ~1 GB | — |
| ML modeller | ~2 GB | ~5 GB |
| **Toplam** | **~14.5 GB / 16 GB** | **~315 GB / 500 GB** |

> ClickHouse TTL 90 güne çıkarsa disk büyümesi +40 GB/yıl eklenir. 500 GB bütçe içinde.  
> RAM %90 dolu → Faz 3 PgBouncer + Faz 6 W1/W4 azaltımı öncelikli.

### node3 — Staging + AI Proxy + Monitoring

**Donanım:** 4 core, ~4 GB RAM (Zap-Hosting, panel girişi 90 günde bir: son tarih 2026-12-10)

| Servis | RAM |
|--------|-----|
| FastAPI + ARQ (staging) | ~800 MB |
| PostgreSQL (staging) | ~600 MB |
| AI Proxy (production trafiği) | ~400 MB |
| Redis (staging) | ~300 MB |
| Prometheus + Grafana | ~400 MB |
| Loki + Promtail | ~300 MB |
| ClickHouse (staging) | ~500 MB |
| **Toplam** | **~3.3 GB / ~4 GB** |

---

## Ek B — Öncelik Matrisi

### Kritik — Beklemez

| # | İş | Faz | Etki |
|---|---|-----|------|
| P1 | PgBouncer aktivasyonu | 3.1 | 🔴 Bağlantı limiti aşılıyor |
| P2 | D51b: init_clickhouse() DB fix | 4.1 | 🔴 Analytics yanlış DB'ye yazıyor |
| P3 | D3: auction status default="active" | 2.2 | 🔴 Yeni açık artırma bozuk görünüyor |
| P4 | GC1: live_stream_viewers cleanup | 1.3 | 🔴 Sınırsız büyüme |
| P5 | MinIO lifecycle policy | 1.4 | 🔴 Yetim dosya riski |
| P6 | Float → Numeric (finansal) | 2.1 | 🔴 Yuvarlama hatası |

### Yüksek — 1. Sprint

| # | İş | Faz | Etki |
|---|---|-----|------|
| P7 | R9: ClickHouse TTL 30→90g (BUG-1/3 fix) | 4.2 | BUG-1/3 kapanır |
| P8 | R9b: user_interactions 90→120g (BUG-2 fix) | 1.1 | BUG-2 kapanır |
| P9 | gift_events + bids FK → SET NULL | 2.4 | R3 kararı güvenli hale gelir |
| P10 | W1+W4: interests+feed frekans azaltımı | 6.1 | node5 CPU azalır |
| P11 | W2: backfill gündüz → gece | 6.1 | node5 gündüz CPU azalır |
| P12 | Composite index'ler | 3.2 | ML sorgu hızı |
| P13 | GC3: listing_offers cleanup | 1.3 | Birikim durur |
| P14 | GC4: exchange_rates cleanup | 1.3 | Günlük birikim durur |

### Orta — 2. Sprint

| # | İş | Faz | Etki |
|---|---|-----|------|
| P15 | Keyset pagination (feed + cüzdan) | 5.2 | p95 düşer |
| P16 | Endpoint cache stratejisi | 5.3 | DB baskısı azalır |
| P17 | Feed N+1 fix | 5.1 | DB sorgu sayısı azalır |
| P18 | GC2: calls cleanup | 1.3 | Birikim durur |
| P19 | W3-W5 frekans azaltımları | 6.1 | CPU tasarrufu |
| P20 | KV1: ip_address maskeleme | 9.2 | KVKK uyumu |
| P21 | D1: listings.image_urls → JSONB | 2.3 | Sorgu optimizasyonu |

### Düşük — 3. Sprint

| # | İş | Faz | Etki |
|---|---|-----|------|
| P22 | Medya WebP + video re-encode (M1-M4) | 8.2 | Storage + bandwidth |
| P23 | W6-W7: ALS haftalığa geçiş | 6.1 | Gece CPU |
| P24 | Hesap silme akışı (KVKK) | 9.1 | Uyumluluk |
| P25 | GC5-GC8 diğer cleanup görevleri | 1.3 | Uzun vadeli |
| P26 | D4-D8 diğer model hataları | 2.2 | Kalite |
| P27 | tuci → teqlik rename | 10 | Sistem geneli |
