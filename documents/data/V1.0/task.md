# teqlif — Task Listesi

**Plan:** `documents/data/V1.0/plan.md`  
**Mimari:** `documents/teqlif_architectural_decisions.md`  
**Prensipler:** Clean Architecture (Router → Use Case → Repository) · Clean Code · MVVM (Flutter)

---

## Workflow (Her Task İçin)

```
1. Uygula         — kodu yaz, migration/config değişikliklerini hazırla
2. Review onayı   — kullanıcı kodu inceler, "onaylıyorum" der
3. Test onayı     — kullanıcı staging/local'de test eder, "test geçti" der
4. Commit + push  — git commit + git push
5. Node ops       — VPS adımları varsa her adımı ayrı ver, çıktı bekle
6. Task kapatma   — kullanıcı "task tamam" der
7. İşaretle       — status güncelle: [x] TAMAMLANDI · commit: XXXXXXXX · tarih: YYYY-MM-DD
8. Sonraki task
```

---

## Durum Göstergesi

```
[ ] BEKLEMEDE
[>] DEVAMEDİYOR
[x] TAMAMLANDI · commit: XXXXXXXX · tarih: YYYY-MM-DD
```

---

## Kritik Sprint — P1–P5

---

### TASK-01 · P2 · 🔴 D3: auction.status default="active"

**Plan:** Faz 2.2  
**Sorun:** `auctions.status default="completed"` → yeni açık artırma tamamlanmış görünüyor.

**Etkilenen dosyalar:**
- `backend/app/models/auction.py` — Model katmanı
- `backend/alembic/versions/` — Yeni migration

**Uygulama:**
1. `auction.py` modeli: `default="completed"` → `default="active"`
2. Alembic migration:
   ```python
   op.execute("ALTER TABLE auctions ALTER COLUMN status SET DEFAULT 'active'")
   op.execute("UPDATE auctions SET status = 'active' WHERE status = 'completed' AND winner_id IS NULL AND ended_at IS NULL")
   ```
   > Her satır ayrı `op.execute()` — asyncpg multi-statement kabul etmez.

**Test:**
- Yeni açık artırma oluştur → `status = "active"` olduğunu kontrol et
- Mevcut açık artırmaların status'u değişmedi

**Node ops:** Yok (deploy = git pull + alembic upgrade head + restart)

**Status:** [ ] BEKLEMEDE

---

### TASK-02 · P5 · 🔴 FK Düzeltmesi: gift_events + bids + direct_sales → SET NULL

**Plan:** Faz 2.3  
**Sorun:**
- `gift_events.stream_id ondelete="CASCADE"` — live_stream silinince finansal hediye kaydı siliniyor
- `bids.stream_id` — ondelete tanımsız → FK violation riski
- `direct_sales.stream_id ondelete="CASCADE"` — **YENİ BULGU** live_stream silinince tüm direct_sales + direct_sale_orders (CASCADE zinciri) siliniyor

**Etkilenen dosyalar:**
- `backend/app/models/gift_event.py` — CASCADE → SET NULL
- `backend/app/models/bid.py` — ondelete="SET NULL" ekle
- `backend/app/models/direct_sale.py` — CASCADE → SET NULL
- `backend/alembic/versions/` — Yeni migration

**Uygulama:**
1. `gift_event.py`: `ondelete="CASCADE"` → `ondelete="SET NULL"`
2. `bid.py`: `stream_id` FK'ya `ondelete="SET NULL"` ekle
3. `direct_sale.py`: `ondelete="CASCADE"` → `ondelete="SET NULL"`
4. Alembic migration (her satır ayrı `op.execute()`):
   ```python
   op.execute("""
       ALTER TABLE gift_events
       DROP CONSTRAINT gift_events_stream_id_fkey,
       ADD CONSTRAINT gift_events_stream_id_fkey
           FOREIGN KEY (stream_id) REFERENCES live_streams(id) ON DELETE SET NULL
   """)
   op.execute("""
       ALTER TABLE bids
       DROP CONSTRAINT IF EXISTS bids_stream_id_fkey,
       ADD CONSTRAINT bids_stream_id_fkey
           FOREIGN KEY (stream_id) REFERENCES live_streams(id) ON DELETE SET NULL
   """)
   op.execute("""
       ALTER TABLE direct_sales
       DROP CONSTRAINT direct_sales_stream_id_fkey,
       ADD CONSTRAINT direct_sales_stream_id_fkey
           FOREIGN KEY (stream_id) REFERENCES live_streams(id) ON DELETE SET NULL
   """)
   ```

**Test:**
- Test live_stream sil → gift_events/bids/direct_sales stream_id NULL oldu, kayıtlar korundu
- direct_sale_orders da korundu (direct_sales var olmaya devam ettiği için)

**Node ops:** Yok

**Status:** [ ] BEKLEMEDE

---

### TASK-03 · P3 · 🔴 GC1: live_stream_viewers cleanup görevi

**Plan:** Faz 1.4 · R1=10 yıl  
**Bağımlılık:** TASK-02 tamamlanmış olmalı.

**Etkilenen dosyalar:**
- `backend/app/repositories/` veya `backend/app/services/` — Repository method
- `backend/app/worker.py` — Yeni cron görev

**Uygulama:**
1. Repository'ye (veya doğrudan worker use-case'e) sorgu ekle:
   ```python
   # R1 = 10 yıl = 3650 gün
   DELETE FROM live_stream_viewers
   WHERE joined_at < NOW() - INTERVAL '3650 days'
   ```
2. `worker.py`'de yeni cron görevi:
   ```python
   async def cleanup_old_stream_viewers_task(ctx):
       async with get_db() as db:
           result = await db.execute(
               text("DELETE FROM live_stream_viewers WHERE joined_at < NOW() - INTERVAL '3650 days'")
           )
           await db.commit()
           logger.info(f"Deleted {result.rowcount} old stream viewer records")

   # Cron: Haftalık Çarşamba 04:00
   cron(cleanup_old_stream_viewers_task, weekday=3, hour=4, minute=0)
   ```

**Clean Architecture notu:** Görev iş mantığı basitse doğrudan worker.py içinde query kabul edilebilir. Karmaşıklaşırsa ayrı use case fonksiyonu.

**Test:**
- `worker.py` syntax hatası yok
- Test verisi ekleyip görevi manuel tetikle: `await cleanup_old_stream_viewers_task(ctx)`

**Node ops:** Yok (restart yeterli)

**Status:** [ ] BEKLEMEDE

---

### TASK-04 · P4 · 🔴 Float → Numeric finansal kolonlar

**Plan:** Faz 2.1  
**Sorun:** Float, para hesaplamalarında yuvarlama hatası üretir.

**Etkilenen dosyalar:**
- `backend/app/models/listing.py` — price, buy_it_now_price, last_sold_price, last_start_price
- `backend/app/models/auction.py` — start_price, buy_it_now_price, final_price
- `backend/app/models/bid.py` — amount
- `backend/app/models/purchase.py` — price
- `backend/app/models/listing_offer.py` — amount
- `backend/app/models/search_alert.py` — max_price
- `backend/app/models/user.py` — max_budget
- `backend/app/models/market_index.py` — usd_try, eur_try
- `backend/app/schemas/` — İlgili Pydantic schema'lar (float → Decimal)
- `backend/alembic/versions/` — Yeni migration

**Uygulama:**

1. Model güncellemeleri:
   ```python
   # ÖNCE: Float
   from sqlalchemy import Float
   price: Mapped[float] = mapped_column(Float)
   
   # SONRA: Numeric
   from sqlalchemy import Numeric
   from decimal import Decimal
   price: Mapped[Decimal] = mapped_column(Numeric(12, 2))
   # market_index için: Numeric(10, 4)
   ```

2. Alembic migration — her ALTER ayrı `op.execute()`:
   ```python
   op.execute("ALTER TABLE listings ALTER COLUMN price TYPE NUMERIC(12,2) USING price::NUMERIC(12,2)")
   op.execute("ALTER TABLE listings ALTER COLUMN buy_it_now_price TYPE NUMERIC(12,2) USING buy_it_now_price::NUMERIC(12,2)")
   op.execute("ALTER TABLE listings ALTER COLUMN last_sold_price TYPE NUMERIC(12,2) USING last_sold_price::NUMERIC(12,2)")
   op.execute("ALTER TABLE listings ALTER COLUMN last_start_price TYPE NUMERIC(12,2) USING last_start_price::NUMERIC(12,2)")
   op.execute("ALTER TABLE auctions ALTER COLUMN start_price TYPE NUMERIC(12,2) USING start_price::NUMERIC(12,2)")
   op.execute("ALTER TABLE auctions ALTER COLUMN buy_it_now_price TYPE NUMERIC(12,2) USING buy_it_now_price::NUMERIC(12,2)")
   op.execute("ALTER TABLE auctions ALTER COLUMN final_price TYPE NUMERIC(12,2) USING final_price::NUMERIC(12,2)")
   op.execute("ALTER TABLE bids ALTER COLUMN amount TYPE NUMERIC(12,2) USING amount::NUMERIC(12,2)")
   op.execute("ALTER TABLE purchases ALTER COLUMN price TYPE NUMERIC(12,2) USING price::NUMERIC(12,2)")
   op.execute("ALTER TABLE listing_offers ALTER COLUMN amount TYPE NUMERIC(12,2) USING amount::NUMERIC(12,2)")
   op.execute("ALTER TABLE search_alerts ALTER COLUMN max_price TYPE NUMERIC(12,2) USING max_price::NUMERIC(12,2)")
   op.execute("ALTER TABLE users ALTER COLUMN max_budget TYPE NUMERIC(12,2) USING max_budget::NUMERIC(12,2)")
   op.execute("ALTER TABLE market_index ALTER COLUMN usd_try TYPE NUMERIC(10,4) USING usd_try::NUMERIC(10,4)")
   op.execute("ALTER TABLE market_index ALTER COLUMN eur_try TYPE NUMERIC(10,4) USING eur_try::NUMERIC(10,4)")
   ```

3. Pydantic schema'lar: `float` → `Decimal` (ilgili response ve request model'ler)

4. `bump_schema_version()` migration sonunda çağrılmalı (ADR §9 kuralı — Faz 3 index migration ile birleştirilebilir)

**Test:**
- Staging'de `alembic upgrade head` çalıştır
- Yeni ilan oluştur: price float değeri ile POST → DB'de NUMERIC(12,2) olarak saklandığını kontrol et
- Cüzdan görüntüle: tuci_balance/teqlik_balance Integer olduğu için etkilenmez

**Node ops:** Staging önce, sonra prod.

**Status:** [ ] BEKLEMEDE

---

### TASK-05 · P1 · 🔴 PgBouncer Aktivasyonu

**Plan:** Faz 3.1  
**Sorun:** 4 uvicorn + 2 ARQ = max 120 bağlantı talebi; PostgreSQL max_connections=100.

**Etkilenen dosyalar:**
- `deploy/scale/V1.4/node5/pgbouncer/pgbouncer.ini` — Yeni dosya
- `deploy/scale/V1.4/node5/pgbouncer/userlist.txt` — Yeni dosya (şifre hash)
- `deploy/scale/V1.4/node5/systemd/pgbouncer.service` — Yeni systemd birimi
- `deploy/scale/V1.4/node5/systemd/teqlif.service` — PgBouncer bağımlılığı ekle
- `backend/app/config.py` — `use_pgbouncer = True`
- node5 `/etc/postgresql/postgresql.conf` — `port = 5433` (PgBouncer 5432 alır)

**Uygulama:**

1. `pgbouncer.ini`:
   ```ini
   [databases]
   teqlif = host=127.0.0.1 port=5433 dbname=teqlif
   
   [pgbouncer]
   listen_addr = 127.0.0.1
   listen_port = 5432
   auth_type = md5
   auth_file = /etc/pgbouncer/userlist.txt
   pool_mode = transaction
   max_client_conn = 200
   default_pool_size = 30
   reserve_pool_size = 5
   server_reset_query = DISCARD ALL
   log_connections = 0
   log_disconnections = 0
   ```

2. `config.py`: `use_pgbouncer: bool = True`

3. `teqlif.service`'e `Requires=pgbouncer.service` + `After=pgbouncer.service` ekle

4. `.env.production` DB_PORT değişiklik gerektirmez (PgBouncer 5432'yi karşılar, PostgreSQL 5433'e geçer)

**Test:**
- **Staging önce** — `pg_stat_activity` ile bağlantı sayısı max 30
- `SELECT count(*) FROM pg_stat_activity WHERE datname='teqlif'` — 30'un altında
- Transaction pool mode ile `SET search_path` çalışmıyor olabilir; test et

**Node ops (staging → prod sırası):**
1. node3'te pgbouncer.ini yerleştir
2. `sudo systemctl enable pgbouncer && sudo systemctl start pgbouncer`
3. PostgreSQL port'unu 5433'e al: `postgresql.conf` → `port=5433` → restart
4. `sudo teqlif-restart` → log izle
5. `SELECT count(*) FROM pg_stat_activity` çalıştır

**Status:** [ ] BEKLEMEDE

---

## Yüksek Öncelik Sprint — P6–P12

---

### TASK-06 · P6 · 🟡 ClickHouse TTL → 365 gün

**Plan:** Faz 4.1 · R9=■1 yıl  
**Bağımlılık:** Yok (non-blocking ALTER, production'da çalıştırılabilir)

**Uygulama (node5 ClickHouse — VPS komutu):**
```sql
ALTER TABLE user_events MODIFY TTL timestamp + INTERVAL 365 DAY;
ALTER TABLE feed_analytics MODIFY TTL timestamp + INTERVAL 365 DAY;
ALTER TABLE search_events MODIFY TTL timestamp + INTERVAL 365 DAY;
ALTER TABLE swipe_live_events MODIFY TTL timestamp + INTERVAL 365 DAY;
ALTER TABLE direct_sale_events MODIFY TTL created_at + INTERVAL 365 DAY;
```

**Backend kod değişikliği:** Yok — `database_clickhouse.py`'da TTL tanımları create-table sırasında kullanılır; mevcut tabloları doğrudan ALTER ile değiştir.

**Test:**
```sql
SELECT table, ttl_expression
FROM system.tables
WHERE database = 'teqlif_prod_analytics';
```
Her tabloda `365 DAY` görünmeli.

**Node ops:**
1. `clickhouse-client --database teqlif_prod_analytics` ile bağlan
2. Her ALTER TABLE komutunu sırayla çalıştır, çıktısını paylaş
3. `system.tables` sorgusu ile doğrula

**Status:** [ ] BEKLEMEDE

---

### TASK-07 · P7 · 🟡 R9b: user_interactions retention 90→365 gün

**Plan:** Faz 1.2 R9b=■1 yıl  
**Dosya:** `backend/app/worker.py`

**Uygulama:**
```python
# ÖNCE (worker.py içindeki cleanup_old_user_interactions_task):
# DELETE FROM user_interactions WHERE created_at < NOW() - INTERVAL '90 days'

# SONRA:
# DELETE FROM user_interactions WHERE created_at < NOW() - INTERVAL '365 days'
```

Görevin içindeki INTERVAL değerini 90 → 365 gün olarak güncelle.

**Test:**
- `user_interactions`'da 90-365 gün arası veri varsa silinmediğini kontrol et (SELECT COUNT)

**Node ops:** Yok (restart yeterli)

**Status:** [ ] BEKLEMEDE

---

### TASK-08 · P8 · 🟡 MinIO Lifecycle Policy (node1 + node4)

**Plan:** Faz 1.5

**Uygulama (VPS komutları — node1'de, sonra node4'te):**
```bash
# listings/ — 365 gün
mc ilm add --expiry-days 365 teqlif/teqlif/listings/

# stories/ — 2 gün
mc ilm add --expiry-days 2 teqlif/teqlif/stories/

# dm/ — 14 gün
mc ilm add --expiry-days 14 teqlif/teqlif-dm/
```

**Doğrulama:**
```bash
mc ilm ls teqlif/teqlif/listings/
mc ilm ls teqlif/teqlif/stories/
mc ilm ls teqlif/teqlif-dm/
```

**Node ops:**
1. node1'de mc alias kontrol: `mc alias ls`
2. Lifecycle rule'ları ekle (yukarıdaki komutlar)
3. node4'te tekrarla

**Status:** [ ] BEKLEMEDE

---

### TASK-09 · P9 · 🟡 W1/W3/W4/W5 ARQ Frekans Değişikliği

**Plan:** Faz 6.1 · W1=■ W3=■ W4=■ W5=■  
**Dosya:** `backend/app/worker.py`

**Mevcut → Hedef:**
| Görev | Mevcut | Hedef |
|-------|--------|-------|
| `compute_user_interests_task` | Her 15 dk | 4x/gün: 00:00, 06:00, 12:00, 18:00 |
| `compute_user_condition_preferences_task` | Her 15 dk | 4x/gün: 00:10, 06:10, 12:10, 18:10 |
| `populate_foryou_feed_task` | Saatlik :00 | 4x/gün: 00:20, 06:20, 12:20, 18:20 |
| `compute_trending_listings_task` | Her 30 dk | 4x/gün: 00:30, 06:30, 12:30, 18:30 |

**Uygulama:** ARQ `cron()` tanımlarını güncelle. Her görevin mevcut `cron(...)` satırını bul:
```python
# ÖNCE
cron(compute_user_interests_task, minute={0, 15, 30, 45})

# SONRA
cron(compute_user_interests_task, hour={0, 6, 12, 18}, minute=0)
cron(compute_user_condition_preferences_task, hour={0, 6, 12, 18}, minute=10)
cron(populate_foryou_feed_task, hour={0, 6, 12, 18}, minute=20)
cron(compute_trending_listings_task, hour={0, 6, 12, 18}, minute=30)
```

**Test:**
- Bir sonraki 00:00'da: 4 görevin de çalıştığı log görünüyor
- 6 saatte toplam 4 çalışma

**Node ops:** `sudo teqlif-restart`

**Status:** [ ] BEKLEMEDE

---

### TASK-10 · P9b · 🟡 W2/W6/W7 ARQ Frekans Değişikliği

**Plan:** Faz 6.1 · W2=■ W6=■ W7=■  
**Dosya:** `backend/app/worker.py`

**Mevcut → Hedef:**
| Görev | Mevcut | Hedef |
|-------|--------|-------|
| `backfill_listing_embeddings_task` | Her 30 dk | Gece: 02:00, 03:00 |
| `train_feed_als_task` | Günlük 01:30 | Haftalık Paz 01:30 |
| `train_swipe_live_als_task` | Günlük 01:00 | Haftalık Paz 01:00 |

```python
# ÖNCE
cron(backfill_listing_embeddings_task, minute={0, 30})
cron(train_feed_als_task, hour=1, minute=30)
cron(train_swipe_live_als_task, hour=1, minute=0)

# SONRA
cron(backfill_listing_embeddings_task, hour={2, 3}, minute=0)
cron(train_feed_als_task, weekday=6, hour=1, minute=30)    # Paz
cron(train_swipe_live_als_task, weekday=6, hour=1, minute=0)   # Paz
```

**Test:**
- Gündüz `backfill_listing_embeddings_task` çalışmıyor (log kontrol)
- 02:00 ve 03:00'de çalışıyor

**Node ops:** `sudo teqlif-restart`

**Status:** [ ] BEKLEMEDE

---

### TASK-11 · P10 · 🟡 Composite Index'ler

**Plan:** Faz 3.2  
**Not:** `CREATE INDEX CONCURRENTLY` yasak (teqlif env.py transaction kullanır).

**Etkilenen dosyalar:**
- `backend/alembic/versions/` — Yeni migration
- Model `__table_args__` güncellemesi (yeni index tanımları)

**Mevcut duruma göre gerçek eksik listesi:**
```
✅ analytics_events (user_id, created_at)    — ix_analytics_events_user_created MEVCUT, ekleme
✅ bids (stream_id, created_at)              — ix_bids_stream_created MEVCUT, ekleme
✅ follows (follower_id, followed_id)        — UniqueConstraint implicit index MEVCUT, ekleme

⚠️ tuci_transactions (user_id, created_at)  — EKSIK (sadece user_id tek-kolon var)
⚠️ purchases (buyer_id, created_at)         — EKSIK
⚠️ user_interactions (user_id, created_at) — EKSIK (user_id+item_id var ama ML queries için created_at composite yok)
⚠️ listings (user_id, status)               — EKSIK (satıcının aktif ilanları için)
⚠️ listing_offers (listing_id, status)      — EKSIK (D7 sonrası, status alanı eklendikten sonra)
```

**Uygulama:**
```python
# Alembic migration — her index ayrı op.execute()
op.execute("CREATE INDEX ix_tuci_transactions_user_created ON tuci_transactions (user_id, created_at DESC)")
op.execute("CREATE INDEX ix_purchases_buyer_created ON purchases (buyer_id, created_at DESC)")
op.execute("CREATE INDEX ix_user_interactions_user_created ON user_interactions (user_id, created_at)")
op.execute("CREATE INDEX ix_listings_user_status ON listings (user_id, status)")
# listing_offers index: D7 (TASK yeni) tamamlandıktan SONRA ayrı migration ile:
# op.execute("CREATE INDEX ix_listing_offers_listing_status ON listing_offers (listing_id, status)")
```

Model dosyalarına da `Index(...)` tanımı eklenmeli:
- `tuci_transaction.py` → `__table_args__` ekle
- `purchase.py` → `__table_args__` ekle
- `analytics.py` → `ix_user_interactions_user_created` ekle
- `listing.py` → `ix_listings_user_status` ekle

**Test:**
- `\d tuci_transactions` ile index listesi kontrol
- `EXPLAIN SELECT * FROM tuci_transactions WHERE user_id=$1 ORDER BY created_at DESC LIMIT 20` → Index Scan görünmeli
- `EXPLAIN SELECT * FROM user_interactions WHERE user_id=$1 ORDER BY created_at DESC LIMIT 120` → Index Scan

**Node ops:** Staging önce, prod sonra.

**Status:** [ ] BEKLEMEDE

---

### TASK-12 · P11/P12 · 🟢 GC3/GC4/GC5: listing_offers + exchange_rates + live_streams cleanup

**Plan:** Faz 1.4  
**Bağımlılık:** TASK yeni-A (D7: listing_offers.status eklendi) tamamlandıktan sonra GC3'te status filtresi çalışır.

**Dosya:** `backend/app/worker.py`

**Uygulama — 3 yeni görev:**
```python
async def cleanup_old_listing_offers_task(ctx):
    # R6 = 1 yıl — declined/expired veya eski aktif teklifler
    # D7 tamamlandıktan sonra: status IN ('declined','expired') filtresi eklenebilir
    # Şimdilik: tüm 1 yılı geçmiş teklifler temizlenir
    async with get_db() as db:
        result = await db.execute(text(
            "DELETE FROM listing_offers "
            "WHERE created_at < NOW() - INTERVAL '365 days'"
        ))
        await db.commit()
        logger.info(f"[GC3] Deleted {result.rowcount} old listing offers")

async def cleanup_old_exchange_rates_task(ctx):
    # R10 = 10 yıl — TABLO ADI: exchange_rates (market_index değil!)
    async with get_db() as db:
        result = await db.execute(text(
            "DELETE FROM exchange_rates WHERE date < CURRENT_DATE - INTERVAL '3650 days'"
        ))
        await db.commit()
        logger.info(f"[GC4] Deleted {result.rowcount} old exchange rate records")

async def cleanup_old_streams_task(ctx):
    # R3 = 10 yıl — biten live_streams
    # BAĞIMLILIK: TASK-02 (FK SET NULL) tamamlanmış olmalı
    async with get_db() as db:
        result = await db.execute(text(
            "DELETE FROM live_streams WHERE status = 'ended' "
            "AND ended_at < NOW() - INTERVAL '3650 days'"
        ))
        await db.commit()
        logger.info(f"[GC5] Deleted {result.rowcount} old live streams")

# Cron:
cron(cleanup_old_listing_offers_task, weekday=5, hour=4, minute=0)    # Cuma 04:00
cron(cleanup_old_exchange_rates_task, day=1, hour=5, minute=0)        # Ayın 1'i 05:00
cron(cleanup_old_streams_task, day=1, hour=6, minute=0)               # Ayın 1'i 06:00
```

**Test:**
- Her görevi manuel tetikle, rowcount logunu kontrol et
- `SELECT MIN(date) FROM exchange_rates` → 10 yıldan eski kayıt yok

**Status:** [ ] BEKLEMEDE

---

## Orta Öncelik Sprint — P13–P20

---

### TASK-13 · P13 · 🟡 Keyset Pagination — Feed + Cüzdan

**Plan:** Faz 5.2  
**Etkilenen dosyalar:**
- `backend/app/routers/listings.py` — Router: yeni query param `cursor`
- `backend/app/use_cases/listing_use_cases.py` (veya benzeri) — Use Case: keyset sorgu
- `backend/app/repositories/listing_repository.py` — Repository: SQL değişikliği
- `mobile/lib/` — Feed ViewModel + Pagination logic (MVVM)

**Uygulama özeti:**

Backend:
```python
# Query: (created_at, id) tuple cursor
WHERE status = 'active'
  AND (created_at, id) < (:cursor_at, :cursor_id)
ORDER BY created_at DESC, id DESC
LIMIT 20
```

Flutter (MVVM):
- ViewModel'de `_cursor` state tutulur
- `fetchMore()` metodu cursor'ı günceller
- View sadece `ref.watch(feedViewModel)` ile render eder

**Test:**
- 3 sayfalık veri yükle: offset'te "kayıp/tekrar" yok
- p95 < 200 ms

**Status:** [ ] BEKLEMEDE

---

### TASK-14 · P14 · 🟡 Endpoint Cache Stratejisi

**Plan:** Faz 5.3  
**Etkilenen dosyalar:**
- `backend/app/routers/listings.py`, `users.py`, `catalog.py`, `app_config.py`
- `backend/app/cache.py` (veya mevcut fastapi-cache decorator'ları)

**ADR §9 cache taksonomisi uygulaması:**

| Endpoint | TTL | Kategori | Invalidasyon |
|---------|-----|---------|-------------|
| `GET /listings/{id}` | 60 sn | EPHEMERAL | Listing update |
| `GET /users/{id}` | 5 dk | EPHEMERAL | Profile update |
| `GET /catalog/categories` | 1 saat | SCHEMA_VERSIONED | bump_schema_version() |
| `GET /app-config` | 10 dk | SCHEMA_VERSIONED | bump_schema_version() |
| `GET /listings/feed` | 30 sn | ALGORITHMIC | TTL expire |

**Status:** [ ] BEKLEMEDE

---

### TASK-15 · P15 · 🟡 Feed N+1 Düzeltmesi

**Plan:** Faz 5.1  
**Etkilenen dosyalar:**
- `backend/app/repositories/listing_repository.py`

**Uygulama:**
```sql
SELECT l.*, u.username, u.rating_avg,
       (SELECT COUNT(*) FROM favorites WHERE listing_id = l.id) AS fav_count
FROM listings l
JOIN users u ON u.id = l.user_id
WHERE l.status = 'active'
ORDER BY l.created_at DESC, l.id DESC LIMIT 20
```

**Test:** `EXPLAIN ANALYZE` — tek sorgu, N+1 yok

**Status:** [ ] BEKLEMEDE

---

### TASK-yeni-A · P5c · 🔴 D7: listing_offers — status alanı ekle

**Plan:** Faz 2.2 D7  
**Sorun:** `listing_offers` tablosunda `status` alanı yok. GC3 cleanup'ı `WHERE status IN ('declined','expired')` filtresini kullanamıyor. Ayrıca ilana gelen tekliflerin kabul/reddedilme durumu takip edilemiyor.

**Etkilenen dosyalar:**
- `backend/app/models/listing_offer.py` — status alanı ekle
- `backend/alembic/versions/` — Migration
- `backend/app/use_cases/listings/commands/create_offer.py` — default status
- İlgili komutlar: accept_offer, decline_offer use case (varsa)

**Uygulama:**
1. Model güncelle:
   ```python
   from sqlalchemy import String
   status: Mapped[str] = mapped_column(String(20), nullable=False, default="active", server_default="active")
   updated_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True, onupdate=func.now())
   ```
2. Alembic migration:
   ```python
   op.execute("ALTER TABLE listing_offers ADD COLUMN status VARCHAR(20) NOT NULL DEFAULT 'active'")
   op.execute("ALTER TABLE listing_offers ADD COLUMN updated_at TIMESTAMPTZ")
   ```
3. GC3 cleanup sorgusunu güncelle (`WHERE status IN ('declined','expired') AND created_at < ...`)

**Test:**
- Yeni teklif → status="active"
- Reddedilen teklif → status="declined"
- GC3: sadece declined/expired/active-ve-eski teklifler temizleniyor

**Status:** [ ] BEKLEMEDE

---

### TASK-yeni-B · P5d · 🟡 D8: user_interests UNIQUE constraint düzelt

**Plan:** Faz 2.2 D8 · ADR §3.2  
**Sorun:** `UNIQUE(user_id, category)` subcategory-level kayıt eklenmesini engelliyor. `compute_user_interests_task`'ın upsert SQL'i de sadece `ON CONFLICT (user_id, category)` kullanıyor — subcategory desteği bozuk.

**Etkilenen dosyalar:**
- `backend/app/models/user_interest.py` — UniqueConstraint değiştir
- `backend/app/worker.py` — upsert SQL güncelle (subcategory dahil)
- `backend/alembic/versions/` — Migration

**Uygulama:**
1. Migration:
   ```python
   # Eski constraint'i düşür
   op.execute("ALTER TABLE user_interests DROP CONSTRAINT uq_user_interest")
   # Yeni: (user_id, category, subcategory) — subcategory NULL için NULLS NOT DISTINCT
   op.execute("""
       ALTER TABLE user_interests
       ADD CONSTRAINT uq_user_interest
       UNIQUE NULLS NOT DISTINCT (user_id, category, subcategory)
   """)
   ```
   > `NULLS NOT DISTINCT` (PG 15+): NULL değerler eşit sayılır → `(uid, 'cat', NULL)` ile `(uid, 'cat', NULL)` çakışır ama `(uid, 'cat', NULL)` ile `(uid, 'cat', 'phones')` çakışmaz.
   > PG 15 öncesi: partial index (`WHERE subcategory IS NULL`) + normal unique index (`WHERE subcategory IS NOT NULL`) kombinasyonu gerekir.

2. Model güncelle:
   ```python
   UniqueConstraint("user_id", "category", "subcategory", name="uq_user_interest")
   ```

3. Worker.py upsert için subcategory parametresi opsiyonel olarak ekle (mevcut category-level upsert korunur, subcategory entryler için ayrı upsert).

**Test:**
- `(user_id=1, category='electronics', subcategory=NULL)` ve `(user_id=1, category='electronics', subcategory='phones')` aynı anda tabloda olabiliyor
- Aynı kategori/subcategory çifti tekrar eklenince UPDATE yapıyor (insert değil)

**Node ops:** `alembic upgrade head` — migration non-blocking

**Status:** [ ] BEKLEMEDE

---

### TASK-16 · P16 · 🟢 GC2: calls cleanup görevi

**Plan:** Faz 1.4 · R2=2 yıl

**Uygulama:**
```python
async def cleanup_old_calls_task(ctx):
    async with get_db() as db:
        result = await db.execute(text(
            "DELETE FROM calls WHERE status IN ('ended','missed') "
            "AND ended_at < NOW() - INTERVAL '730 days'"
        ))
        await db.commit()

cron(cleanup_old_calls_task, weekday=4, hour=4, minute=0)  # Perşembe 04:00
```

**Status:** [ ] BEKLEMEDE

---

### TASK-17 · P18 · 🟡 KV1: ip_address Maskeleme (KVKK)

**Plan:** Faz 9.2  
**Etkilenen dosyalar:**
- `backend/app/routers/analytics.py` veya middleware — IP kaydı yapılan yer

**Uygulama:**
```python
def mask_ip(ip: str) -> str:
    parts = ip.split(".")
    if len(parts) == 4:
        return f"{parts[0]}.{parts[1]}.{parts[2]}.0"
    return ip  # IPv6 için şimdilik saklama

# analytics event kaydedilmeden önce:
masked = mask_ip(request.client.host)
```

**Test:**
- Yeni analytics event kaydı → ip_address son okteti 0

**Status:** [ ] BEKLEMEDE

---

### TASK-18 · P19/P20 · 🟢 GC6/GC7 + D1 image_urls JSONB

**Plan:** Faz 1.4 (GC6/GC7) + Faz 2.2 (D1)

**GC6/GC7 (worker.py):**
```python
async def cleanup_empty_message_threads_task(ctx):
    async with get_db() as db:
        # message_threads tablosunda (user_a_id, user_b_id) PK var — thread_id kolonu yok
        await db.execute(text(
            "DELETE FROM message_threads mt "
            "WHERE NOT EXISTS ("
            "  SELECT 1 FROM direct_messages dm "
            "  WHERE (dm.sender_id = mt.user_a_id AND dm.receiver_id = mt.user_b_id) "
            "     OR (dm.sender_id = mt.user_b_id AND dm.receiver_id = mt.user_a_id)"
            ") AND mt.created_at < NOW() - INTERVAL '30 days'"
        ))
        await db.commit()

async def cleanup_inactive_search_alerts_task(ctx):
    # search_alerts'ta updated_at YOKTUR — created_at kullanılmalı
    async with get_db() as db:
        await db.execute(text(
            "DELETE FROM search_alerts WHERE created_at < NOW() - INTERVAL '180 days'"
        ))
        await db.commit()

cron(cleanup_empty_message_threads_task, weekday=6, hour=5, minute=0)  # Paz 05:00
cron(cleanup_inactive_search_alerts_task, weekday=6, hour=6, minute=0) # Paz 06:00
```

**D1: listings.image_urls → JSONB:**
```python
# Alembic migration
op.execute("ALTER TABLE listings ALTER COLUMN image_urls TYPE JSONB USING image_urls::JSONB")
op.execute("CREATE INDEX ix_listings_image_urls_gin ON listings USING GIN (image_urls)")
```
- Model: `image_urls: Mapped[list] = mapped_column(JSONB)`
- Pydantic schema: `image_urls: list[str]`
- `bump_schema_version()` ekle

**Status:** [ ] BEKLEMEDE

---

## Düşük Öncelik Sprint — P21–P25

---

### TASK-18b · P20b · 🟡 listings.updated_at — Write Path Düzeltmesi

**Plan:** Faz 2.5  
**Sorun:** `listings.updated_at` her zaman NULL. `onupdate` yok, hiçbir update use case bu kolonu set etmiyor. API yanıtı `updated_at: null` dönüyor — yanıltıcı.

**Etkilenen dosyalar:**
- `backend/app/models/listing.py` — `onupdate=func.now()` ekle
- `backend/app/use_cases/listings/commands/update_listing.py` — explicit set ekle
- `backend/alembic/versions/` — Backfill migration

**Uygulama:**
1. Model:
   ```python
   updated_at: Mapped[Optional[datetime]] = mapped_column(
       DateTime(timezone=True), nullable=True,
       onupdate=func.now()
   )
   ```
2. `update_listing.py`'de update sonrası `listing.updated_at = func.now()` veya ORM flush tetikler.
3. Backfill migration:
   ```python
   op.execute("UPDATE listings SET updated_at = created_at WHERE updated_at IS NULL")
   ```

**Test:**
- İlan güncelle → `updated_at` NULL değil, şu anki zaman

**Status:** [ ] BEKLEMEDE

---

### TASK-18c · P20c · 🟢 Dead Kolon Migration

**Plan:** Faz 2.5  
**Kapsam:** Kod incelemesinde hiç kullanılmadığı doğrulanan kolonlar.

**Etkilenen dosyalar:**
- `backend/app/models/message.py` — `flag_reason` kaldır
- `backend/app/models/call.py` — `CallParticipant.ringing_at` kaldır
- `backend/app/models/state.py` — `country_code` kaldır
- `backend/alembic/versions/` — Migration

**Uygulama:**
```python
op.execute("ALTER TABLE direct_messages DROP COLUMN flag_reason")
op.execute("ALTER TABLE call_participants DROP COLUMN ringing_at")
op.execute("ALTER TABLE states DROP COLUMN country_code")
```

> Dikkat: drop öncesi `SELECT COUNT(*) FROM direct_messages WHERE flag_reason IS NOT NULL` ile veri yok olduğunu doğrula.

**Test:**
- Staging'de migration çalıştır, uygulama hatası yok
- DM gönder/al, çağrı başlat — çalışıyor

**Status:** [ ] BEKLEMEDE

---

### TASK-18d · P20d · 🟢 countries Tablosu Temizliği

**Plan:** Faz 2.5  
**Sorun:** `countries` tablosu hiçbir router/service/worker tarafından kullanılmıyor. `states.country_code` FK değil, plain VARCHAR.

**Etkilenen dosyalar:**
- `backend/app/models/country.py` — Sil
- `backend/app/models/__init__.py` — Country import'unu kaldır
- `backend/alembic/versions/` — Migration

**Uygulama:**
```python
# Migration
op.execute("DROP TABLE IF EXISTS countries")
```
Ardından `models/country.py` dosyasını sil.

**Test:**
- `alembic upgrade head` sonrası `\dt` ile tablo yok
- Uygulama normal başlıyor

**Status:** [ ] BEKLEMEDE

---

### TASK-18e · P20e · 🟡 Flutter User Model — Sosyal URL Typed Alanlar

**Plan:** Faz 2.5  
**Sorun:** `website_url`, `instagram_url`, `kick_url`, `twitch_url`, `facebook_url`, `youtube_url`, `tiktok_url` — `User` model sınıfında tip güvensiz `Map<String, dynamic>` erişimi ile kullanılıyor. `User.fromJson` kapsamı dışında.

**Etkilenen dosyalar:**
- `mobile/lib/models/user.dart` — Yeni opsiyonel alanlar
- `mobile/lib/screens/profile_screen.dart` — raw map erişimini typed alanlara taşı
- `mobile/lib/screens/public_profile_screen.dart` — aynı

**Uygulama:**
```dart
// User class'ına ekle
final String? websiteUrl;
final String? instagramUrl;
final String? kickUrl;
final String? twitchUrl;
final String? facebookUrl;
final String? youtubeUrl;
final String? tiktokUrl;

// fromJson:
websiteUrl: json['website_url'] as String?,
instagramUrl: json['instagram_url'] as String?,
// ...
```

**Test (MVVM):**
- Profil ekranında sosyal URL'ler doğru parse ediliyor
- `dart analyze` 0 hata

**Status:** [ ] BEKLEMEDE

---

### TASK-18f · P20f · 🟢 Flutter Dead Code Temizliği

**Plan:** Faz 2.5

**Kapsam:**
1. `mobile/lib/screens/teq_test_screen.dart` — Sil; `main.dart`'tan `/teq-test` route'unu kaldır
2. `mobile/lib/services/analytics_service.dart` — `getFeedStats()` metodunu kaldır

**Dikkat:** `teq_test_screen.dart` içeriğini önce oku — üretim debug verisi/credential içermiyor olduğundan emin ol.

**Test:**
- `dart analyze` 0 hata
- Uygulama normal başlıyor

**Status:** [ ] BEKLEMEDE

---

### TASK-19 · P21 · 🟢 Medya Optimizasyonu (M1-M4)

**Plan:** Faz 8.2  
**Karar bekleniyor:** M1-M4 her biri ayrı onay gerektirir.

**Kararlar:**

| # | Değişiklik | Onay |
|---|-----------|------|
| M1 | İlan fotoğrafı: JPEG → WebP q80, max 1920px | [ ] |
| M2 | İlan videosu: `-c:v copy` → CRF 28 (CPU yoğun) | [ ] |
| M3 | DM medya limitleri: Foto 5→3 MB, Video 30→20 MB | [ ] |
| M4 | Profil fotoğrafı: JPEG q85 → WebP q75, max 800px | [ ] |

**Not:** M2 node5'te (7.8 GB RAM) upload sırasında yüksek CPU — önce staging'de yük testi yapılacak.

**Etkilenen dosyalar:**
- `backend/app/services/media_processor.py`
- `backend/app/utils/media_limits.py`

**Status:** [ ] BEKLEMEDE (M1-M4 kararları alındıktan sonra başla)

---

### TASK-20 · P22 · 🟢 Hesap Silme Akışı (KVKK/GDPR)

**Plan:** Faz 9.1 + R11=■

**Etkilenen dosyalar:**
- `backend/app/routers/users.py` — `DELETE /users/me` endpoint (yeni)
- `backend/app/use_cases/user_use_cases.py` — Anonimleştirme use case (Clean Architecture)
- `backend/app/repositories/user_repository.py` — Soft-delete + NULL set
- `backend/app/services/storage_service.py` — MinIO avatar silme (node1/node4)

**Anonimleştirme use case:**
```python
async def delete_account_use_case(user_id: UUID, db, minio):
    # 1. PII null/anonymize
    await user_repo.anonymize(user_id, db)
    # 2. DM: sender_id=NULL
    await dm_repo.anonymize_sender(user_id, db)
    # 3. MinIO: avatar sil
    await storage_service.delete_avatar(user_id, minio)
    # 4. analytics_events: user_id=NULL (FK → SET NULL varsa otomatik)
    # 5. purchases/transactions: KORUNUR (TTK 82)
```

**Flutter (MVVM):**
- `ProfileViewModel.deleteAccount()` → `DELETE /users/me`
- View: onay dialog → ViewModel çağrısı → logout

**Status:** [ ] BEKLEMEDE

---

### TASK-21 · P23 · 🟢 D2/D4/D5 Model Düzeltmeleri

**Plan:** Faz 2.2

| # | Düzeltme |
|---|---------|
| D2 | `listings.active_room_id`: FK `ForeignKey("live_streams.id", ondelete="SET NULL")` ekle |
| D4 | `reports.created_at`: `DateTime(timezone=True), server_default=func.now()` |
| D5 | `app_configs.updated_at`: `DateTime(timezone=True)` |

**Etkilenen dosyalar:**
- `backend/app/models/listing.py`
- `backend/app/models/report.py`
- `backend/app/models/app_config.py`
- `backend/alembic/versions/` — Migration

**Status:** [ ] BEKLEMEDE

---

### TASK-22 · P24 · 🟢 KV2/KV3 — KVKK Tamamlama

**Plan:** Faz 9.2

| # | Değişiklik |
|---|-----------|
| KV2 | `DELETE /users/me` — TASK-20 ile birlikte |
| KV3 | `notification_prefs`'e `analytics_opt_out: bool` ekle |

**KV3 uygulama:**
- Migration: `notification_prefs JSONB` alanına yeni key ekle veya users tablosuna `analytics_opt_out BOOLEAN DEFAULT FALSE`
- Analytics event kaydında kontrol: `if not user.analytics_opt_out`
- Flutter: Ayarlar ekranında toggle (MVVM — `SettingsViewModel.toggleAnalyticsOptOut()`)

**Status:** [ ] BEKLEMEDE

---

### TASK-23 · P25 · 🟢 tuci → teqlik Yeniden Adlandırma

**Plan:** Faz 10  
**Bağımlılık:** Tüm önceki tasklar tamamlanmış olmalı.

**Kapsam:**
- `tuci_transactions` → `teqlik_transactions` (Alembic migration: RENAME TABLE)
- `users.tuci_balance` → `users.teqlik_balance` (Alembic: RENAME COLUMN)
- Python: model, repository, use_case, schema, worker.py
- API JSON response: `tuci_balance` → `teqlik_balance`
- Flutter: DTO, ViewModel, widget, i18n ARB (4 dil)

**Geçiş stratejisi:**
1. Backend: Eski alan adlarını Pydantic `alias` ile 1 sprint geç destekle
2. Flutter güncellendikten sonra alias kaldır

**Status:** [ ] BEKLEMEDE

---

## Özet Tablosu

| Task | Öncelik | Sprint | Faz | Status |
|------|---------|--------|-----|--------|
| TASK-01 · D3 auction status | 🔴 P2 | Kritik | 2.2 | [ ] |
| TASK-02 · FK SET NULL (gift+bids+**direct_sales**) | 🔴 P5 | Kritik | 2.3 | [ ] |
| TASK-03 · GC1 stream viewers | 🔴 P3 | Kritik | 1.4 | [ ] |
| TASK-04 · Float→Numeric | 🔴 P4 | Kritik | 2.1 | [ ] |
| TASK-05 · PgBouncer | 🔴 P1 | Kritik | 3.1 | [ ] |
| TASK-yeni-A · D7 listing_offers status | 🔴 P5c | Kritik | 2.2 | [ ] |
| TASK-yeni-B · D8 user_interests constraint | 🟡 P5d | Kritik | 2.2 | [ ] |
| TASK-06 · ClickHouse TTL 365g | 🟡 P6 | Yüksek | 4.1 | [ ] |
| TASK-07 · user_interactions 365g | 🟡 P7 | Yüksek | 1.2 | [ ] |
| TASK-08 · MinIO lifecycle | 🟡 P8 | Yüksek | 1.5 | [ ] |
| TASK-09 · W1/W3/W4/W5 4x/gün | 🟡 P9 | Yüksek | 6.1 | [ ] |
| TASK-10 · W2/W6/W7 frekans | 🟡 P9b | Yüksek | 6.1 | [ ] |
| TASK-11 · Composite index'ler (gerçek eksikler) | 🟡 P10 | Yüksek | 3.2 | [ ] |
| TASK-12 · GC3/GC4/GC5 (exchange_rates fix) | 🟢 P11/P12 | Yüksek | 1.4 | [ ] |
| TASK-13 · Keyset pagination | 🟡 P13 | Orta | 5.2 | [ ] |
| TASK-14 · Endpoint cache | 🟡 P14 | Orta | 5.3 | [ ] |
| TASK-15 · Feed N+1 fix | 🟡 P15 | Orta | 5.1 | [ ] |
| TASK-16 · GC2 calls cleanup | 🟢 P16 | Orta | 1.4 | [ ] |
| TASK-17 · KV1 ip maskeleme | 🟡 P18 | Orta | 9.2 | [ ] |
| TASK-18 · GC6/GC7 + D1 JSONB (sorgu fix) | 🟢 P19/P20 | Orta | 1.4/2.2 | [ ] |
| TASK-18b · listings.updated_at write path | 🟡 P20b | Orta | 2.5 | [ ] |
| TASK-18c · Dead kolon migration (flag_reason, ringing_at, country_code) | 🟢 P20c | Orta | 2.5 | [ ] |
| TASK-18d · countries tablosu temizliği | 🟢 P20d | Orta | 2.5 | [ ] |
| TASK-18e · Flutter User model sosyal URL typed | 🟡 P20e | Orta | 2.5 | [ ] |
| TASK-18f · Flutter dead code (teq_test + getFeedStats) | 🟢 P20f | Orta | 2.5 | [ ] |
| TASK-19 · Medya M1-M4 | 🟢 P21 | Düşük | 8.2 | [ ] |
| TASK-20 · Hesap silme KVKK | 🟢 P22 | Düşük | 9.1 | [ ] |
| TASK-21 · D2/D4/D5 model fix | 🟢 P23 | Düşük | 2.2 | [ ] |
| TASK-22 · KV2/KV3 opt-out | 🟢 P24 | Düşük | 9.2 | [ ] |
| TASK-23 · tuci→teqlik rename | 🟢 P25 | Düşük | 10 | [ ] |
