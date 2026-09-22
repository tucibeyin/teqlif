# Teqlif V1.0 — Production Deployment Guide (node5)

Bu dosya her task için **staging (node3) onayından sonra** node5'te uygulanacak
adımları kayıt bazında içerir. Her giriş bir task'ın production rehberidir.

**Kural:**
- Staging'de test edilmeden bu dosyaya giriş eklenmez.
- Her adım staging ile aynıdır; node5'e özgü farklar `[PROD FARKI]` etiketi ile belirtilir.
- Adımlar sırayla çalıştırılır, çıktı beklenir.

---

## TASK-yeni-K · PgBouncer Transaction Mode Uyumluluk Denetimi

**Staging tarihi:** 2026-09-21  
**Commit:** bd5a13c1  
**Staging testi:** Denetim — grep audit, database.py connect_args eklendi  

**node5 adımları:**

```bash
# Kod zaten git'te — git pull yeterli
cd /var/www/teqlif.com && git pull origin main
```

Kod değişikliği `backend/app/database.py`'de NullPool branch'e `connect_args` eklenmesi.
Servis yeniden başlatılması TASK-05 sonrasına bırakılır (PgBouncer aktif edilince).

**[PROD FARKI]:** Yok — database.py değişikliği her ortamda aynı.

---

## TASK-05 · PgBouncer Aktivasyonu

**Staging tarihi:** 2026-09-22  
**Commit:** 587f5da8  

**node5 adımları:**

> **[PROD FARKI]** Staging'de PgBouncer 6432, PostgreSQL 5432'de kaldı.
> Production'da PostgreSQL 5433'e taşınır, PgBouncer standart 5432 portunu alır.
> Bu DATABASE_URL'nin değişmediği anlamına gelir — yalnızca PostgreSQL'in port'u değişir.

**1. Kodu çek:**
```bash
cd /var/www/teqlif.com && git pull origin main
```

**2. PgBouncer kur:**
```bash
sudo apt update && sudo apt install -y pgbouncer
```

**3. userlist.txt oluştur:**

> **[PROD FARKI]** PostgreSQL 16 varsayılan `scram-sha-256` kullanır. SCRAM verifier'ı `pg_authid`'den al:

```bash
# Önce PostgreSQL'e bağlan (port 5433 — PgBouncer'dan önce)
sudo -u postgres psql -p 5433 -t -A -c "SELECT rolpassword FROM pg_authid WHERE rolname='teqlif';"
# Çıktı: SCRAM-SHA-256$4096:...$...:...
```
```bash
sudo nano /etc/pgbouncer/userlist.txt
# İçerik (tek satır):
# "teqlif" "SCRAM-SHA-256$...<yukarıdaki çıktı>..."
```

**4. pgbouncer.ini oluştur:**

> Staging `pgbouncer.ini`'den farklar: DB adı `teqlif`, pool_size=30, max_client_conn=200

```bash
sudo nano /etc/pgbouncer/pgbouncer.ini
```
İçerik:
```ini
[databases]
teqlif = host=127.0.0.1 port=5433 dbname=teqlif

[pgbouncer]
listen_addr = 127.0.0.1
listen_port = 5432
auth_type = scram-sha-256
auth_file = /etc/pgbouncer/userlist.txt

pool_mode = transaction
max_client_conn = 200
default_pool_size = 30
reserve_pool_size = 5
min_pool_size = 5

server_reset_query = DISCARD ALL
server_login_retry = 3
ignore_startup_parameters = extra_float_digits

log_connections = 0
log_disconnections = 0
log_pooler_errors = 1

admin_users = tucibeyin
stats_users = tucibeyin
```

```bash
sudo chown postgres:postgres /etc/pgbouncer/pgbouncer.ini /etc/pgbouncer/userlist.txt
sudo chmod 640 /etc/pgbouncer/pgbouncer.ini /etc/pgbouncer/userlist.txt
```

**5. PostgreSQL'i 5433 portuna taşı:**
```bash
sudo nano /etc/postgresql/*/main/postgresql.conf
# port = 5432  →  port = 5433
sudo systemctl restart postgresql
# Kontrol:
psql -h 127.0.0.1 -p 5433 -U tucibeyin -c "SELECT version();"
```

**6. pgbouncer.service kur:**
```bash
sudo cp /var/www/teqlif.com/deploy/scale/V1.4/node3/systemd/pgbouncer.service /etc/systemd/system/
# [PROD FARKI] Dosya node3 için yazıldı ama içerik aynı — node5'te de geçerli
sudo systemctl daemon-reload
sudo systemctl enable pgbouncer
sudo systemctl start pgbouncer
sudo systemctl status pgbouncer
```

**7. .env.production güncelle:**
```bash
nano /var/www/teqlif.com/backend/.env.production
# DATABASE_URL port zaten 5432 — DEĞİŞMEZ (PgBouncer 5432'yi karşılıyor)
# Şu satırı ekle/güncelle:
USE_PGBOUNCER=True
```

**8. teqlif.service güncelle:**
```bash
sudo cp /var/www/teqlif.com/deploy/scale/V1.4/node5/systemd/teqlif.service /etc/systemd/system/
# NOT: node5/systemd/teqlif.service'e After=pgbouncer.service eklenmeli (TASK-05 tamamlanınca güncellenecek)
sudo systemctl daemon-reload
sudo teqlif-restart
```

**9. Doğrula:**
```bash
psql -h 127.0.0.1 -p 5432 -U tucibeyin pgbouncer -c "SHOW pools;"
psql -h 127.0.0.1 -p 5433 -U tucibeyin -d teqlif -c "SELECT count(*) FROM pg_stat_activity WHERE datname='teqlif';"
# Bağlantı sayısı 30 veya altında olmalı
```

---

## TASK-01 · auction.status default="active"

**Staging tarihi:** 2026-09-22  
**Commit:** bef76ddd  
**Staging testi:** alembic upgrade head çalıştı, status default aktif  

**node5 adımları:**

```bash
cd /var/www/teqlif.com && git pull origin main
sudo teqlif-restart
```

Alembic migration (`zzzzv_auction_status_default`) otomatik çalışır:
- `auctions.status DEFAULT 'active'`
- `winner_id IS NULL AND ended_at IS NULL` olan `status='completed'` kayıtlar → `'active'`

**[PROD FARKI]:** Yok.

---

## TASK-03 · live_stream_viewers GC cron

**Staging tarihi:** 2026-09-22  
**Commit:** 6a427cb6  
**Staging testi:** worker.py syntax OK, servis aktif  

**node5 adımları:**

```bash
cd /var/www/teqlif.com && git pull origin main
sudo teqlif-restart
```

ARQ worker yeniden başlayınca `cleanup_old_stream_viewers_task` cron kaydı aktif olur (Çarşamba 04:00).

**[PROD FARKI]:** Yok.

---

## TASK-04 · Float → Numeric(12,2) finansal kolonlar

**Staging tarihi:** 2026-09-22  
**Commit:** 3b99034d  
**Staging testi:** `\d listings | grep price` → `numeric(12,2)` ✅  

**node5 adımları:**

```bash
cd /var/www/teqlif.com && git pull origin main
sudo teqlif-restart
```

Alembic migration (`zzzzw_float_to_numeric`) otomatik çalışır — 16 ALTER TABLE:
- listings (price, buy_it_now_price, last_sold_price, last_start_price)
- auctions (start_price, buy_it_now_price, final_price)
- bids (amount), purchases (price), listing_offers (amount)
- search_alerts (max_price), users (max_budget)
- direct_sales (price), direct_sale_orders (unit_price)
- exchange_rates (usd_try → Numeric(10,4), eur_try → Numeric(10,4))

**Doğrulama:**
```bash
psql -h 127.0.0.1 -p 5433 -U teqlif -d teqlif -c "\d listings" | grep price
# Beklenen: price | numeric(12,2)
```

**[PROD FARKI]:** psql portu 5433 (PostgreSQL PgBouncer arkasında).

---

## TASK-02 · FK SET NULL — gift_events/bids/direct_sales/auctions → stream_id

**Staging tarihi:** 2026-09-22  
**Commit:** 52b108da  
**Staging testi:** `gift_events.stream_id is_nullable=YES` ✅  

**node5 adımları:**

```bash
cd /var/www/teqlif.com && git pull origin main
sudo teqlif-restart
```

Alembic migration (`zzzzx_fk_set_null_stream_id`) otomatik çalışır:
- gift_events.stream_id: CASCADE → SET NULL + nullable
- bids.stream_id: tanımsız → SET NULL + nullable
- direct_sales.stream_id: CASCADE → SET NULL + nullable
- auctions.stream_id: tanımsız → SET NULL + nullable

**Doğrulama:**
```bash
psql -h 127.0.0.1 -p 5432 -U teqlif -d teqlif -c "SELECT column_name, is_nullable FROM information_schema.columns WHERE table_name='gift_events' AND column_name='stream_id'"
# Beklenen: is_nullable=YES
```

**[PROD FARKI]:** Yok.

---

## TASK-06 · ClickHouse TTL → 365 gün

**Staging tarihi:** 2026-09-22  
**Commit:** 8d654a89  
**Staging testi:** tüm tablolar `toIntervalDay(365)` ✅  

**node5 adımları — önce git pull, sonra ClickHouse ALTER:**

```bash
cd /var/www/teqlif.com && git pull origin main
```

```bash
clickhouse-client --database teqlif_prod_analytics --query "ALTER TABLE user_events MODIFY TTL timestamp + INTERVAL 365 DAY"
clickhouse-client --database teqlif_prod_analytics --query "ALTER TABLE feed_analytics MODIFY TTL timestamp + INTERVAL 365 DAY"
clickhouse-client --database teqlif_prod_analytics --query "ALTER TABLE search_events MODIFY TTL timestamp + INTERVAL 365 DAY"
clickhouse-client --database teqlif_prod_analytics --query "ALTER TABLE swipe_live_events MODIFY TTL timestamp + INTERVAL 365 DAY"
clickhouse-client --database teqlif_prod_analytics --query "ALTER TABLE direct_sale_events MODIFY TTL created_at + INTERVAL 365 DAY"
```

**Doğrulama:**
```bash
for t in user_events feed_analytics search_events swipe_live_events direct_sale_events; do
  echo -n "$t: "; clickhouse-client --database teqlif_prod_analytics --query "SHOW CREATE TABLE $t" | grep -o 'TTL.*'
done
```

**[PROD FARKI]:** DB adı `teqlif_prod_analytics` (staging: `teqlif_staging_analytics`).

---

## TASK-07 · user_interactions retention 90 → 365 gün

**Staging tarihi:** 2026-09-22  
**Commit:** 918130a6  
**Staging testi:** worker.py güncellendi, commit push edildi  

**node5 adımları:**

```bash
cd /var/www/teqlif.com && git pull origin main
sudo teqlif-restart
```

**[PROD FARKI]:** Yok.

---

## TASK-08 · MinIO Lifecycle Policy

**Staging tarihi:** 2026-09-22  
**Staging testi:** listings/365, stories/2, dm/14 ✅ (node3-staging)  

**node1 adımları (Edge 1):**

```bash
mc alias ls  # alias adını doğrula (örn: node1-prod)
mc ilm add --expiry-days 365 <alias>/teqlif/listings/
mc ilm add --expiry-days 2   <alias>/teqlif/stories/
mc ilm add --expiry-days 14  <alias>/teqlif-dm/
```

**Doğrulama:**
```bash
mc ilm ls <alias>/teqlif/listings/
mc ilm ls <alias>/teqlif/stories/
mc ilm ls <alias>/teqlif-dm/
```

**node4 adımları (Edge 2):** Aynı komutları node4 alias'ıyla tekrarla.

**[PROD FARKI]:** Bucket adları `teqlif` ve `teqlif-dm` (staging: `teqlif-staging`, `teqlif-dm-staging`).

---

## TASK-09 · W1/W3/W4/W5 ARQ Frekans + 3 Bug Fix

**Staging tarihi:** 2026-09-22  
**Commit:** f3f22bd9  
**Staging testi:** worker.py + foryou_worker.py güncellendi  

**node5 adımları:**

```bash
cd /var/www/teqlif.com && git pull origin main
sudo teqlif-restart
```

Değişiklikler:
- W1/W3/W4/W5 cron: 15dk/saatlik → günde 4x (00, 06, 12, 18)
- W4 key fix: `feed:{uid}:foryou` LIST → `feed:foryou:{uid}` String
- W3 TTL: 1500s → 21600s; W5 TTL: 1800s → 21600s

**[PROD FARKI]:** Yok.

---

## TASK-10 · W2/W6/W7 ARQ Frekans Değişikliği

**Staging tarihi:** 2026-09-22  
**Commit:** ce92a44e  
**Staging testi:** servisler aktif ✅  

**node5 adımları:**

```bash
cd /var/www/teqlif.com && git pull origin main
sudo teqlif-restart
```

Değişiklikler:
- backfill_listing_embeddings_task: {0,30} → gece 02:00, 03:00 (W2)
- train_swipe_live_als_task: günlük → Pazar 01:00 (W6)
- train_feed_als_task: günlük → Pazar 01:30 (W7)

**[PROD FARKI]:** Yok.

---

## TASK-11 · Composite Index'ler

**Staging tarihi:** 2026-09-22  
**Commit:** 3d9fec1a  
**Staging testi:** `ix_tuci_transactions_user_created` btree ✅  

**node5 adımları:**

```bash
cd /var/www/teqlif.com && git pull origin main
sudo teqlif-restart
```

Alembic migration (`zzzzy_composite_indexes`) otomatik çalışır:
- `ix_tuci_transactions_user_created` (user_id, created_at DESC)
- `ix_purchases_buyer_created` (buyer_id, created_at DESC)
- `ix_user_interactions_user_created` (user_id, created_at)
- `ix_listings_user_status` (user_id, status)

**[PROD FARKI]:** Yok.

---

## TASK-12 · GC3/GC4/GC5 Cleanup Cron'ları

**Staging tarihi:** 2026-09-22  
**Commit:** ababd522  
**Staging testi:** servisler aktif, worker başladı ✅  

**node5 adımları:**

```bash
cd /var/www/teqlif.com && git pull origin main
sudo teqlif-restart
```

- GC4 (exchange_rates): ayın 1'i 05:00 — aktif
- GC5 (live_streams): ayın 1'i 06:00 — aktif
- GC3 (listing_offers): TASK-yeni-A tamamlanınca worker.py'de yorum kaldır

**[PROD FARKI]:** Yok.

---

## TASK-yeni-H · Auction Redis State Recovery

**Staging tarihi:** 2026-09-22  
**Commit:** 4b468af8  
**Staging testi:** servisler aktif, journal temiz ✅  

**node5 adımları:**

```bash
cd /var/www/teqlif.com && git pull origin main
sudo teqlif-restart
```

`end_auction()` içine `_rebuild_auction_state_from_db()` eklendi: Redis state boşsa (TTL/crash) DB'deki `bids` kayıtlarından en son teklifi ve toplam bid_count'u yeniden oluşturur, ardından Redis'e yazar ve normal kapanış devam eder. Önceki tamamlanmış açık artırmaların teklifleri `ended_at` ile filtrelenir.

**[PROD FARKI]:** Yok.

---

## TASK-yeni-E · BigInteger PK + DM Retention

**Staging tarihi:** 2026-09-22  
**Commit:** 464de604  
**Staging testi:** `direct_messages.id = bigint` ✅  

**node5 adımları:**

```bash
cd /var/www/teqlif.com && git pull origin main
sudo teqlif-restart
```

Alembic migration (`zzzzb_bigint_pk_dm_notifications`) otomatik çalışır:
- `direct_messages.id` INT4 → BIGINT
- `notifications.id` INT4 → BIGINT
- DM cleanup genişletildi: `is_hidden+60gün` korundu + `is_read=FALSE+365gün` eklendi

**Doğrulama:**
```bash
psql -h 127.0.0.1 -p 5433 -U teqlif -d teqlif -c "SELECT data_type FROM information_schema.columns WHERE table_name='direct_messages' AND column_name='id'"
# Beklenen: bigint
```

**[PROD FARKI]:** Yok.

---

## TASK-yeni-F · response_model= on critical endpoints

**Staging tarihi:** 2026-09-22  
**Commit:** 9777e720  
**Staging testi:** 5/5 endpoint şemaya uygun JSON döndü ✅  

**node5 adımları:**

```bash
cd /var/www/teqlif.com && git pull origin main
sudo teqlif-restart
```

Yalnızca kod değişikliği — migration yok:
- `schemas/listing.py`: `SellerMiniOut`, `ListingOut`, `ListingDetailOut` eklendi
- `schemas/commerce.py` (yeni): `InitOut`, `CommerceItemOut`, `CommerceSaleOut`
- `GET /listings` → `list[ListingOut]`
- `GET /listings/{id}` → `ListingDetailOut`
- `GET /auth/init` → `InitOut`
- `GET /auth/me/commerce/purchases` → `list[CommerceItemOut]`
- `GET /auth/me/commerce/sales` → `list[CommerceSaleOut]`

**[PROD FARKI]:** Yok.

---

## TASK-yeni-B · user_interests UNIQUE constraint — subcategory dahil

**Staging tarihi:** 2026-09-22  
**Commit:** f4ee05e9  
**Staging testi:** `uq_user_interest UNIQUE NULLS NOT DISTINCT (user_id, category, subcategory)` ✅  

**node5 adımları:**

```bash
cd /var/www/teqlif.com && git pull origin main
sudo teqlif-restart
```

Alembic migration (`zzzza_user_interests_unique`) otomatik çalışır:
- `UNIQUE(user_id, category)` → `UNIQUE NULLS NOT DISTINCT (user_id, category, subcategory)` (PG 15+)
- Worker upsert: `ON CONFLICT ON CONSTRAINT uq_user_interest`

**[PROD FARKI]:** Yok.

---

## TASK-yeni-A · listing_offers — status + updated_at + GC3

**Staging tarihi:** 2026-09-22  
**Commit:** 160d942e  
**Staging testi:** `\d listing_offers` → status NOT NULL DEFAULT 'active', updated_at ✅  

**node5 adımları:**

```bash
cd /var/www/teqlif.com && git pull origin main
sudo teqlif-restart
```

Alembic migration (`zzzzz_listing_offers_status`) otomatik çalışır:
- `listing_offers.status VARCHAR(20) NOT NULL DEFAULT 'active'`
- `listing_offers.updated_at TIMESTAMPTZ`
- GC3 cron aktif: Cuma 04:00 — `declined`/`expired` ve 1 yıldan eski teklifler temizlenir

**Doğrulama:**
```bash
psql -h 127.0.0.1 -p 5433 -U teqlif -d teqlif -c "\d listing_offers" | grep -E "status|updated_at"
```

**[PROD FARKI]:** Yok.

---

## TASK-13 · Keyset Pagination — Feed + Listings + Logout Hive Clear

**Staging tarihi:** 2026-09-22  
**Commit:** abbadb7e  
**Staging testi:** servisler aktif, journal temiz ✅  

**node5 adımları:**

```bash
cd /var/www/teqlif.com && git pull origin main
sudo teqlif-restart
```

Değişiklikler:
- `GET /listings`: `cursor_at` + `cursor_id` keyset parametresi eklendi (additive); `page`/`offset` hâlâ çalışıyor
- `GET /feed` ve `GET /feed/for-you`: `cursor` param eklendi (additive, ileriki kullanım için)
- `GET /feed/recent`: zaten `max_id` cursor destekliyordu — değişiklik yok
- Flutter `HomeState.lastMaxId`: loadMore artık `max_id` cursor kullanıyor (offset yerine)
- Flutter `StorageService.clear()`: logout sırasında `homeCache` + `api_cache` Hive box'ları da temizleniyor
- Flutter `homeCache` cacheVersion=2 kontrolü: versiyon uyumsuzluğunda cache otomatik temizleniyor

**[PROD FARKI]:** Yok.
