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
4. `auction.py`: `stream_id` FK'ya `ondelete="SET NULL"` ekle — **yeni bulgu:** tanımsız bırakılmış, GC5 live_stream silince FK violation fırlatır
5. Alembic migration (her satır ayrı `op.execute()`):
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
   op.execute("""
       ALTER TABLE auctions
       DROP CONSTRAINT IF EXISTS auctions_stream_id_fkey,
       ADD CONSTRAINT auctions_stream_id_fkey
           FOREIGN KEY (stream_id) REFERENCES live_streams(id) ON DELETE SET NULL
   """)
   ```

**Test:**
- Test live_stream sil → gift_events/bids/direct_sales/auctions stream_id NULL oldu, kayıtlar korundu
- direct_sale_orders da korundu (direct_sales var olmaya devam ettiği için)

**Node ops:** Yok

**Status:** [ ] BEKLEMEDE

---

### TASK-03 · P3 · 🔴 GC1: live_stream_viewers cleanup görevi

**Plan:** Faz 1.4 · R1=10 yıl  
**Bağımlılık:** TASK-02 tamamlanmış olmalı.

> ⚠️ **KIRILMA UYARISI (Impact Analizi):** `live_stream_viewers` tablosunda hem `joined_at` hem `left_at` kolonu var. `left_at IS NULL` = aktif izleyici. Sorgu `left_at IS NOT NULL` filtresi olmadan çalıştırılırsa aktif yayın izleyicileri silinebilir.

**Etkilenen dosyalar:**
- `backend/app/repositories/` veya `backend/app/services/` — Repository method
- `backend/app/worker.py` — Yeni cron görev

**Uygulama:**
1. Repository'ye (veya doğrudan worker use-case'e) sorgu ekle:
   ```python
   # R1 = 10 yıl = 3650 gün
   # left_at IS NOT NULL filtresi şart — aktif izleyicileri silmemek için
   DELETE FROM live_stream_viewers
   WHERE left_at IS NOT NULL
     AND joined_at < NOW() - INTERVAL '3650 days'
   ```
2. `worker.py`'de yeni cron görevi:
   ```python
   async def cleanup_old_stream_viewers_task(ctx):
       async with get_db() as db:
           result = await db.execute(
               text("DELETE FROM live_stream_viewers WHERE left_at IS NOT NULL AND joined_at < NOW() - INTERVAL '3650 days'")
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

4. **Zorunlu serialization düzeltmesi:** FastAPI 0.115.0'da `jsonable_encoder` Decimal'i `str`'e çevirir. `response_model` tanımlı olmayan tüm listing endpoint'leri bozulur. Aşağıdaki dosyalarda Decimal kolonları için `float(value) if value is not None else None` wrap edilmeli:
   - `backend/app/use_cases/listings/queries/listing_utils.py:95,107,113` — `price`, `buy_it_now_price`, `last_sold_price`
   - `backend/app/use_cases/listings/queries/search_listings_query.py:125` — `price`
   - `backend/app/routers/listings.py:349` — similar endpoint `price`
   - `backend/app/use_cases/listings/queries/get_listing_offers.py:22` — `amount`
   > Auction ve Direct Sale endpoint'leri `response_model=AuctionStateOut/DirectSaleStateOut` olduğu için Pydantic coerce yapar — güvenli.

5. `bump_schema_version()` migration sonunda çağrılmalı (ADR §9 kuralı — Faz 3 index migration ile birleştirilebilir)

**Test:**
- Staging'de `alembic upgrade head` çalıştır
- `GET /api/listings` → response'da `"price": 99.99` (number, string değil) doğrula
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

5. **Zorunlu asyncpg `statement_cache_size=0`:** PgBouncer transaction mode ile asyncpg prepared statement cache uyumsuz — `InvalidSQLStatementNameError` hatası alınır. `backend/app/database.py`'de engine oluşturulurken eklenmeli:
   ```python
   # PgBouncer transaction mode: prepared statement cache devre dışı bırakılmalı
   engine = create_async_engine(
       DATABASE_URL,
       poolclass=NullPool,
       connect_args={"statement_cache_size": 0},  # ← ZORUNLU
   )
   ```

**Test:**
- **Staging önce** — `pg_stat_activity` ile bağlantı sayısı max 30
- `SELECT count(*) FROM pg_stat_activity WHERE datname='teqlif'` — 30'un altında
- `EXPLAIN` gibi hazırlıklı sorgu içeren endpoint'ler hata vermiyor (`InvalidSQLStatementNameError` yok)
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

> ⚠️ **3 Kritik Bug Bu Task'ta Düzeltilmeli (Impact Analizi):**
> 1. **W4 Redis key mismatch** — `populate_foryou_feed_task` `feed:{uid}:foryou` (LIST) yazıyor, API `feed:foryou:{uid}` (String) okuyor → W4 çıktısı hiçbir yerde tüketilmiyor.
> 2. **W3 TTL uyumsuzluğu** — `condition_pref:{uid}` TTL=1500s (25dk), 4x/gün = 6h aralık → 5.5 saatin condition scoring'i eksik.
> 3. **W5 TTL uyumsuzluğu** — `trending:listings:velocity` TTL=1800s (30dk), 4x/gün = 6h aralık → trending 5.5 saat boş kalır.

**Mevcut → Hedef:**
| Görev | Mevcut | Hedef |
|-------|--------|-------|
| `compute_user_interests_task` | Her 15 dk | 4x/gün: 00:00, 06:00, 12:00, 18:00 |
| `compute_user_condition_preferences_task` | Her 15 dk | 4x/gün: 00:10, 06:10, 12:10, 18:10 |
| `populate_foryou_feed_task` | Saatlik :00 | 4x/gün: 00:20, 06:20, 12:20, 18:20 |
| `compute_trending_listings_task` | Her 30 dk | 4x/gün: 00:30, 06:30, 12:30, 18:30 |

**Uygulama:** ARQ `cron()` tanımlarını güncelle + 3 bug düzelt:
```python
# ÖNCE
cron(compute_user_interests_task, minute={0, 15, 30, 45})

# SONRA — frekans değişikliği
cron(compute_user_interests_task, hour={0, 6, 12, 18}, minute=0)
cron(compute_user_condition_preferences_task, hour={0, 6, 12, 18}, minute=10)
cron(populate_foryou_feed_task, hour={0, 6, 12, 18}, minute=20)
cron(compute_trending_listings_task, hour={0, 6, 12, 18}, minute=30)
```

**W4 key mismatch düzeltmesi** (`foryou_worker.py`):
```python
# populate_foryou_feed_task içinde:
# ÖNCE (hatalı): await redis.rpush(f"feed:{uid}:foryou", ...)
#                await redis.expire(f"feed:{uid}:foryou", _FORYOU_TTL)
# SONRA (doğru): await redis.set(f"feed:foryou:{uid}", json.dumps(feed_ids), ex=_FORYOU_TTL)
# Not: FeedQueries.get_foryou_feed() redis.get(f"feed:foryou:{user_id}") okuyor
```

**W3 TTL düzeltmesi** (`worker.py`'de `compute_user_condition_preferences_task`):
```python
# ÖNCE: await redis.set(f"condition_pref:{uid}", ..., ex=1500)  # 25 dk
# SONRA: await redis.set(f"condition_pref:{uid}", ..., ex=21600)  # 6 saat
```

**W5 TTL düzeltmesi** (`worker.py`'de `compute_trending_listings_task`):
```python
# ÖNCE: await redis.set("trending:listings:velocity", ..., ex=1800)  # 30 dk
# SONRA: await redis.set("trending:listings:velocity", ..., ex=21600)  # 6 saat
```

**Test:**
- Bir sonraki 00:00'da: 4 görevin de çalıştığı log görünüyor
- 6 saatte toplam 4 çalışma
- `redis-cli GET feed:foryou:1` → değer var (W4 key mismatch düzeltildi)
- `redis-cli TTL condition_pref:1` → ~21600 s
- `redis-cli TTL trending:listings:velocity` → ~21600 s

**Node ops:** `sudo teqlif-restart`

**Status:** [ ] BEKLEMEDE

---

### TASK-10 · P9b · 🟡 W2/W6/W7 ARQ Frekans Değişikliği

**Plan:** Faz 6.1 · W2=■ W6=■ W7=■  
**Dosya:** `backend/app/worker.py`

> ⚠️ **ALS/BPR TTL Kritik Uyumsuzluğu (Impact Analizi):** W6/W7 haftalık eğitime geçince ALS/BPR vektörlerinin TTL'i de uzatılmalı. Mevcut TTL=90000s (25 saat) — haftalık eğitimde 6 gün boyunca ALS cache'i boş kalır, feed kişiselleştirmesinin ~%20'si kaybolur. `bpr:rec:{uid}` için 7 gün TTL ayarlanmalı.

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

**ALS/BPR TTL uzatması** (`bpr_service.py` veya worker içinde cache yazan yer):
```python
# ÖNCE: await redis.set(f"bpr:rec:{uid}", ..., ex=90000)   # 25 saat
# SONRA: await redis.set(f"bpr:rec:{uid}", ..., ex=604800)  # 7 gün — haftalık eğitimle uyumlu
# seller:badge, trust_score, influence_rank gibi diğer ML key'leri de haftalık eğitim varsa 7 güne çıkar
```

**Test:**
- Gündüz `backfill_listing_embeddings_task` çalışmıyor (log kontrol)
- 02:00 ve 03:00'de çalışıyor
- Pazar sabahı train sonrası `redis-cli TTL bpr:rec:1` → ~604800 s

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
**Bağımlılık:**
- GC3: **TASK-yeni-A tamamlanmadan çalıştırma** — status alanı olmadan aktif teklifler de silinir (`feed.py:292` LEFT JOIN ile teklif sayısı gösteriliyor)
- GC5: **TASK-02 tamamlanmadan çalıştırma** — `auctions.stream_id` FK tanımsız; stream silinince FK violation fırlatır ve görev başarısız olur

**Dosya:** `backend/app/worker.py`

**Uygulama — 3 yeni görev:**
```python
async def cleanup_old_listing_offers_task(ctx):
    # R6 = 1 yıl — TASK-yeni-A tamamlandıktan sonra çalıştır
    # status IN ('declined','expired') filtresi şart — aktif teklifler korunmalı
    # (feed.py:292 listing_offers LEFT JOIN ile teklif sayısı gösteriyor)
    async with get_db() as db:
        result = await db.execute(text(
            "DELETE FROM listing_offers "
            "WHERE status IN ('declined', 'expired') "
            "AND created_at < NOW() - INTERVAL '365 days'"
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
- `backend/app/routers/listings.py` — Router: yeni query param `cursor` (additive)
- `backend/app/routers/feed.py` — `GET /feed`, `GET /feed/for-you`
- `backend/app/routers/search.py` — search offset parametreleri
- `backend/app/use_cases/listing_use_cases.py` (veya benzeri) — Use Case: keyset sorgu
- `backend/app/repositories/listing_repository.py` — Repository: SQL değişikliği
- `mobile/lib/` — Feed ViewModel + Pagination logic (MVVM) + Hive cache format

> ⚠️ **Koordinasyon Zorunlu (Impact Analizi):**
> 1. **`page`/`offset` parametreleri kaldırılmamalı** — Flutter tüm sayfalama için offset-based kullanıyor. `cursor` parametresi ADDITIVELY eklenmeli, eski parametreler deprecated period olmadan silinmemeli.
> 2. **Hive `homeCache` box güncellenmeli** — Mevcut format `raw JSON + page offset` saklıyor. Keyset'e geçince Hive'daki eski format geçersiz kalır; `cacheVersion` bump ile eski cache temizlenmeli.
> 3. **`GET /api/feed/recent` zaten cursor-benzeri** — `since_id` + `max_id` parametreleri var (feed.py:105-106); bu endpoint için additive değil, zaten uyumlu.

**Uygulama özeti:**

Backend:
```python
# Query: (created_at, id) tuple cursor
WHERE status = 'active'
  AND (created_at, id) < (:cursor_at, :cursor_id)
ORDER BY created_at DESC, id DESC
LIMIT 20
# Eski offset parametresini de koru (deprecated ama bozma)
```

Flutter (MVVM):
- ViewModel'de `_cursor` state tutulur
- `fetchMore()` metodu cursor'ı günceller
- View sadece `ref.watch(feedViewModel)` ile render eder
- Hive cache: `cacheVersion` artır → eski offset-based cache otomatik temizlenir

**Test:**
- 3 sayfalık veri yükle: offset'te "kayıp/tekrar" yok
- p95 < 200 ms
- Eski `?page=2` isteği hâlâ çalışıyor (backward compat)

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

### TASK-yeni-C · P5e · 🟡 DM Raporlama — flag_reason Aktivasyonu

**Plan:** Faz 2.2  
**Sorun:** `direct_messages.flag_reason VARCHAR(255)` kolonu var ama hiçbir endpoint bu kolonu set etmiyor. Kullanıcılar mesajları raporlayamıyor; moderasyon sırası oluşturulamıyor.

**Mevcut altyapı:** `backend/app/routers/reports.py` — ilan raporlama için mevcut. DM raporlama bu router'a endpoint olarak eklenir.

**Etkilenen dosyalar:**
- `backend/app/routers/messages.py` — `POST /{message_id}/flag` endpoint ekle
- `backend/app/models/message.py` — `flag_reason` zaten var, değişiklik yok
- `backend/alembic/versions/` — Migration yok (kolon zaten mevcut)
- `mobile/lib/` — DM ekranında mesaj uzun basma menüsüne "Raporla" seçeneği (MVVM)

**Backend uygulama:**
```python
# messages.py — yeni endpoint
@router.post("/{message_id}/flag", status_code=204)
async def flag_message(
    message_id: int,
    reason: str,   # "spam" | "harassment" | "inappropriate" | "scam" | "other"
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    msg = await db.get(DirectMessage, message_id)
    if not msg:
        raise AppException(status_code=404, code="NOT_FOUND")
    # Sadece mesajı alan kişi raporlayabilir
    if msg.receiver_id != current_user.id:
        raise AppException(status_code=403, code="FORBIDDEN")
    msg.flag_reason = reason
    await db.commit()
```

**Flutter (MVVM):**
- `DirectMessageViewModel.flagMessage(messageId, reason)` — `POST /messages/{id}/flag`
- DM ekranında mesaj baloncusuna uzun basınca: "Raporla" seçeneği → reason seçici bottom sheet
- `mobile/lib/services/message_service.dart` veya ViewModel'e method ekle

**Test:**
- Mesaj al → uzun bas → Raporla → reason seç → 204 döner
- `SELECT flag_reason FROM direct_messages WHERE id=...` → reason kaydedildi
- Başka kullanıcının mesajını raporlamaya çalış → 403

**Status:** [ ] BEKLEMEDE

---

### TASK-yeni-D · P5f · 🟡 Search Alert Trigger + Flutter Feed Stats

**Plan:** Faz 2.2  
**Sorun:**
1. `search_alerts` tablosu ve CRUD endpoint'leri var, kullanıcılar alert oluşturabiliyor — ama yeni ilan eklenince bildirim gönderen mekanizma hiç implemente edilmemiş.
2. `analytics_service.dart:getFeedStats()` tanımlı, backend `GET /analytics/my-feed-stats` aktif — ama Flutter'da hiçbir ekran bu metodu çağırmıyor.

---

**1. Search Alert ARQ Worker Task (Backend):**

Etkilenen dosyalar:
- `backend/app/worker.py` — yeni cron görev

```python
async def check_search_alerts_task(ctx: dict) -> None:
    """
    Son 15 dakikada eklenen ilanları aktif search_alert'larla eşleştirir.
    Eşleşen alert sahibine push bildirim gönderir.
    """
    from app.services.notification_service import push_notification

    async with get_db() as db:
        # Son 15 dakikada aktif olan yeni ilanlar
        since = datetime.now(timezone.utc) - timedelta(minutes=15)
        new_listings = await db.execute(
            select(Listing).where(
                Listing.status == "active",
                Listing.created_at >= since,
            )
        )
        listings = new_listings.scalars().all()
        if not listings:
            return

        # Tüm aktif alert'ları çek
        alerts = (await db.execute(
            select(SearchAlert).where(SearchAlert.status == SearchAlertStatus.ACTIVE)
        )).scalars().all()

        for listing in listings:
            for alert in alerts:
                if alert.user_id == listing.user_id:
                    continue  # Kendi ilanı için bildirim gönderme
                # Kategori eşleşmesi
                if alert.category and alert.category != listing.category:
                    continue
                # Fiyat filtresi
                if alert.max_price and listing.price and listing.price > alert.max_price:
                    continue
                # Metin eşleşmesi (title)
                if alert.query and alert.query.lower() not in (listing.title or "").lower():
                    continue
                # Eşleşti — bildirim gönder
                await push_notification(
                    alert.user_id,
                    {
                        "type": "search_alert",
                        "listing_id": listing.id,
                        "listing_title": listing.title,
                        "listing_price": float(listing.price) if listing.price else None,
                        "alert_query": alert.query or alert.category,
                    },
                    pref_key="search_alert",
                )

# Cron: Her 15 dakikada bir
cron(check_search_alerts_task, minute={0, 15, 30, 45})
```

> **Not:** Ölçek büyüdüğünde cursor tabanlı (son işlenen `listing_id` Redis'te) yaklaşıma geçilebilir. Şimdilik `created_at >= since` yeterli.

---

**2. Flutter Feed Stats Ekranı:**

Etkilenen dosyalar:
- `mobile/lib/services/analytics_service.dart` — `getFeedStats()` zaten tanımlı, implement et
- `mobile/lib/screens/` — Pro satıcı profil veya ilan yönetim ekranında feed stats bölümü (MVVM)

```dart
// analytics_service.dart:getFeedStats() — backend: GET /api/analytics/my-feed-stats?days=7
// Response: impression, click, skip, CTR, dwell_time — sadece premium kullanıcılar
// Flutter: ViewModel.fetchFeedStats(days) → AsyncNotifier → feed stats widget
```

**Test:**
- Yeni ilan ekle (category+query eşleşen alert sahibi var) → 15 dk içinde bildirim geldi
- Kendi ilanın için bildirim gelmiyor
- Premium kullanıcı feed stats ekranı açılıyor, 7/30/90 günlük veri görünüyor
- Normal kullanıcı için premium engeli gösteriliyor

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
        # status != 'pending' zorunlu — onay bekleyen DM isteklerini silmemek için
        # (auth.py:406 login'de pending request'leri listeler; silinirse istek kaybolur)
        await db.execute(text(
            "DELETE FROM message_threads mt "
            "WHERE mt.status != 'pending' "
            "AND NOT EXISTS ("
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

### TASK-18c · P20c · 🟢 listing.location Write Path Fix + ringing_at Aktivasyonu

**Plan:** Faz 2.5  

> `states.country_code` bu scope'tan **çıkarıldı** — multi-country entegrasyonunda kullanılacak (Faz 2.6).  
> `flag_reason` bu scope'tan **çıkarıldı** — DM raporlama özelliği olarak TASK-yeni-C'de implemente ediliyor.

---

**1. listing.location Write Path Fix:**

> **Sorun:** Flutter `location` alanını gönderiyor ve gösteriyor — ama backend `create_listing` ve `update_listing` use case'lerinde bu alanı hiç DB'ye yazmıyor. Kullanıcının girdiği konum sessizce kayboluyor.

Etkilenen dosyalar:
- `backend/app/use_cases/listings/commands/create_listing.py` — `location` parametresini al, modele yaz
- `backend/app/use_cases/listings/commands/update_listing.py` — `location` güncellemesini ekle
- `backend/app/routers/listings.py` — request body'de `location` alanının varlığını kontrol et

```python
# create_listing.py — listing oluşturulurken:
listing = Listing(
    ...
    location=data.location,   # ← ekle
)

# update_listing.py — listing güncellenirken:
if data.location is not None:
    listing.location = data.location  # ← ekle
```

---

**2. ringing_at Aktivasyonu:**

> **Sorun:** `call_participants.ringing_at` kolonu var ama hiçbir yerde set edilmiyor. Grup çağrısında davet edilen katılımcının zil çalmaya başladığı anı kaydetmek için kullanılmalı.
>
> **Mimari not:** 1-1 aramada `ringing` durumu Redis presence'da (`set_presence(..., "ringing", ...)`) tutuluyor — DB'ye yazılmıyor. `CallParticipant` yalnızca **grup çağrısı davetlileri** için var. Bu yüzden `ringing_at`, `CallParticipant` oluşturulduğu anda (davet push'u gönderildiğinde) set edilmeli.

Etkilenen dosya:
- `backend/app/routers/calls.py:1294` — `CallParticipant(...)` oluşturulurken `ringing_at=now` ekle

```python
# calls.py satır 1291-1302:
now = datetime.now(timezone.utc)
cp = CallParticipant(
    call_id=call_id,
    user_id=invitee_id,
    role="guest",
    status="invited",
    invited_by=current_user.id,
    livekit_token=livekit_token,
    invited_at=now,
    ringing_at=now,   # ← ekle — davet = zil başlangıcı
)
```

**Ne sağlar:** `ringing_at` ile `invited_at` farklı mı? Şu an aynı anda set ediliyor. İleride ACK tabanlı gerçek ring-start tespiti yapılırsa ayrışabilir. Şimdilik `invited_at` ile başlat yeterli.

---

**Test:**
- Flutter'dan `location` dolu ilan oluştur → `SELECT location FROM listings WHERE id=...` → değer kaydedildi
- İlan güncelle → location değişti
- Grup çağrısına davet gönder → `SELECT ringing_at FROM call_participants WHERE ...` → timestamp var

**Status:** [ ] BEKLEMEDE

---

### TASK-18d · ~~P20d~~ · ⏸️ countries Tablosu — BIRAKILDI

**Plan:** Faz 2.6 (Gelecek Kullanım)  
**Karar:** `countries` tablosu silinmeyecek. Çok ülke desteği (multi-country) eklendiğinde kullanılacak.

**Mevcut durum:**
- `countries(code, name)` — tablo var, seed data var
- `states.country_code VARCHAR(2)` — var ama FK bağlantısı yok, sorgu filtresi yok
- `/states` router yalnızca Türkiye illerini döndürüyor (ülke filtresi yok)
- Flutter `StateService` ülke seçici içermiyor

**Pazar izolasyonu aktivasyon sırası (zaman gelince):**
1. `users` tablosuna `country_code VARCHAR(2)` ekle — kullanıcının pazarı (TR/AZ/DE…)
2. `listings` tablosuna `country_code VARCHAR(2)` ekle — ilanın pazarı; backfill ile mevcut ilanları TR'ye set et
3. Feed/arama sorgularına `WHERE country_code = :user_market` filtresi ekle
4. Migration: `ALTER TABLE states ADD CONSTRAINT fk_states_country FOREIGN KEY (country_code) REFERENCES countries(code)`
5. States router'a `?country=TR` filtresi ekle
6. Flutter `StateService.getStates()` → ülke parametresi al; ilan oluşturma ekranına ülke seçici ekle
7. `exchange_rates` (usd_try, eur_try) üzerinden AZN/EUR fiyat gösterimi

> `states.country_code` adres seçicinin alt yapısı. Pazar izolasyonunun kendisi `users.country_code` + `listings.country_code`'a bağlı.

**Status:** ⏸️ BIRAKILDI — multi-country sprint'ine ertelendi

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
1. `mobile/lib/screens/teq_test_screen.dart` — Sil; `main.dart:17` import ve `main.dart:197` `/teq-test` route'unu kaldır (design system showcase ekranı, production özelliği yok)

> `getFeedStats()` bu scope'tan **çıkarıldı** — Flutter'da implement edilecek (TASK-yeni-D ile birlikte veya ayrı sprint'te).

**Dikkat:** `teq_test_screen.dart` içeriği incelendi — sadece TeqButton, TeqCard vb. UI component'leri gösteriyor, credential/debug verisi yok.

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
| TASK-yeni-C · DM raporlama (flag_reason) | 🟡 P5e | Kritik | 2.2 | [ ] |
| TASK-yeni-D · Search alert trigger + Flutter feed stats | 🟡 P5f | Kritik | 2.2 | [ ] |
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
| TASK-18c · listing.location write path + ringing_at aktivasyonu | 🟢 P20c | Orta | 2.5 | [ ] |
| TASK-18d · countries — BIRAKILDI (multi-country) | ⏸️ | — | 2.6 | ⏸️ |
| TASK-18e · Flutter User model sosyal URL typed | 🟡 P20e | Orta | 2.5 | [ ] |
| TASK-18f · Flutter dead code (teq_test + getFeedStats) | 🟢 P20f | Orta | 2.5 | [ ] |
| TASK-19 · Medya M1-M4 | 🟢 P21 | Düşük | 8.2 | [ ] |
| TASK-20 · Hesap silme KVKK | 🟢 P22 | Düşük | 9.1 | [ ] |
| TASK-21 · D2/D4/D5 model fix | 🟢 P23 | Düşük | 2.2 | [ ] |
| TASK-22 · KV2/KV3 opt-out | 🟢 P24 | Düşük | 9.2 | [ ] |
| TASK-23 · tuci→teqlik rename | 🟢 P25 | Düşük | 10 | [ ] |

---

## Gelecek Sprint Backlog — Kasıtlı Ertelenenler

> Aşağıdaki yapılar mevcut sprint'e dahil edilmedi. Silinmedi, ileride kullanılacak.

| Yapı | Niyet | Aktivasyon Şartı |
|------|-------|-----------------|
| **Pazar seçimi** (onaylı ürün yol haritası) — `countries`, `states.country_code`, `exchange_rates` hazır; `users.selected_market` + `listings.country_code` eksik | Kullanıcı pazar seçer (TR/AZ/DE…), feed+arama+fiyat değişir | Pazar sprint'i — 7 adım, plan.md Faz 2.6 |
| `referral.status = 'pending'` | İki adımlı referral: kayıt → pending; ilk alışveriş → completed + ödül tetikle | Referral iş mantığı sprint'i — `apply_referral` service refactor + ARQ görevi |
| `ad_campaigns` DB + API | Satıcı boost/reklam — schema ve wallet entegrasyonu var | Flutter "reklam ver" ekranı sprint'i — `create_listing_screen` boost butonu + reklam oluşturma akışı |
