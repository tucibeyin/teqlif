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

## TASK-yeni-I · Bid DB-Redis Stale State Sync

**Staging tarihi:** 2026-09-22  
**Commit:** 54259752  
**Staging testi:** Servis sağlıklı ✅ (race condition nadir, log'da gözlemlenmez)  

**node5 adımları:**

```bash
cd /var/www/teqlif.com && git pull origin main
sudo teqlif-restart
```

Yalnızca kod değişikliği — migration yok:
- `auction_redis_repo.py`: `update_bid_state()` helper eklendi
- `auction_commands.py` `place_bid()`: `execute_bid()` ok==0 durumunda DB'den son teklif çekilip Redis senkronize ediliyor

**[PROD FARKI]:** Yok.

---

## TASK-15 + TASK-yeni-N · Feed N+1 Doğrulaması + Slim Feed DTO

**Staging tarihi:** 2026-09-22  
**Commit:** d11a8971  
**Staging testi:** search ve recommendation endpoint'lerinden dönen JSON alanları `_card_dict` şemasıyla eşleşti ✅  

**node5 adımları:**

```bash
cd /var/www/teqlif.com && git pull origin main
sudo teqlif-restart
```

Yalnızca kod değişikliği — migration yok:
- `search_listings_query.py`: inline dict → `_card_dict` tabanlı yapı; search'e özgü alanlar (`category`, `subcategory`, `image_urls`, `video_url`, `active_room_id`) üstte eklendi
- `recommendation_service._hydrate()`: `_row_dict` → `_card_dict` (similar listings slim payload)
- `feed_queries.py`, `get_swipe_feed.py`: zaten `_card_dict` + JOIN kullanıyordu — N+1 yoktu, doğrulandı

**[PROD FARKI]:** Yok.

---

## TASK-yeni-J · webhooks.py Dead Code Temizliği + _VIEWER_TTL Düzeltmesi

**Staging tarihi:** 2026-09-22  
**Commit:** 0bd2eba2  
**Staging testi:** `grep -r "_on_viewer" backend/` → sonuç yok ✅; chat WS viewer sayacı çalışıyor ✅  

**node5 adımları:**

```bash
cd /var/www/teqlif.com && git pull origin main
sudo teqlif-restart
```

Yalnızca kod değişikliği — migration yok:
- `webhooks.py`: `_VIEWER_TTL`, `_resolve_stream_and_host`, `_on_viewer_joined`, `_on_viewer_left` silindi (hiç dispatch edilmiyordu)
- `chat_commands.py`: `_VIEWER_TTL = 12 * 3600` → `48 * 3600`; `add_viewer/remove_viewer` içindeki 3 hardcoded `48 * 3600` → `_VIEWER_TTL`

**[PROD FARKI]:** Yok.

---

## TASK-17 · KV1: ip_address Maskeleme (KVKK)

**Staging tarihi:** 2026-09-25  
**Commit:** a6a3dce7  
**Staging testi:** analytics_events.ip_address = '127.0.0.0' (son oktet sıfır) ✅  

**node5 adımları:**

```bash
cd /var/www/teqlif.com && sudo teqlif-restart production
```

Migration yok — analytics.py ve auction.py logic değişikliği.

**[PROD FARKI]:** Yok.

---

## TASK-18f · Flutter Dead Code Temizliği

**Staging tarihi:** 2026-09-22  
**Commit:** 71cf6bd4  
**Staging testi:** Flutter-only değişiklik — dart analyze 0 hata ✅  

**node5 adımları:** Flutter-only, deployment gerekmez.

---

## TASK-18 · GC6/GC7 worker tasks + D1 image_urls JSONB

**Staging tarihi:** 2026-09-22  
**Commit:** 95ad2eb7  
**Staging testi:** GC6/GC7 cron'lar kayıtlı; image_urls kolonu jsonb tipinde ✅  

**node5 adımları:**

```bash
cd /var/www/teqlif.com && sudo teqlif-restart production
```

Migration otomatik çalışır: `ALTER TABLE listings ALTER COLUMN image_urls TYPE JSONB` + GIN index oluşturulur + schema_version bump edilir.

**[PROD FARKI]:** Production'da listings tablosu daha büyük olabilir — migration in-transaction çalışır, kısa süre tablo kilitlenir. Yoğun olmayan bir saatte restart edilmesi önerilir (örn. gece 04:00).

---

## TASK-16 · GC2: calls cleanup cron görevi

**Staging tarihi:** 2026-09-22  
**Commit:** 976e87f9  
**Staging testi:** `cron:cleanup_old_calls_task` worker listesinde görüldü ✅  

**node5 adımları:**

```bash
cd /var/www/teqlif.com && sudo teqlif-restart production
```

Migration yok — worker.py'ye cron eklendi.

**[PROD FARKI]:** Yok.

---

## TASK-18c · listing.location Write Path Fix + ringing_at Aktivasyonu

**Staging tarihi:** 2026-09-22  
**Commit:** 130477f0  
**Staging testi:** Servisler aktif, kod deploy edildi ✅  

**node5 adımları:**

```bash
cd /var/www/teqlif.com && sudo teqlif-restart production
```

Migration yok — sadece backend logic değişikliği.

**[PROD FARKI]:** Yok.

---

## TASK-18b · listings.updated_at Write Path Düzeltmesi

**Staging tarihi:** 2026-09-22  
**Commit:** 28c8e9d0  
**Staging testi:** Migration çalıştı, NULL updated_at count = 0 ✅  

**node5 adımları:**

```bash
cd /var/www/teqlif.com && sudo teqlif-restart production
```

Migration otomatik çalışır (`alembic upgrade head`): `listings` tablosundaki NULL `updated_at` değerleri `created_at` ile doldurulur.

**[PROD FARKI]:** Yok — migration ve model değişikliği her ortamda aynı.

---

## TASK-18e · Flutter User Model — Sosyal URL Typed Alanlar

**Staging tarihi:** 2026-09-22  
**Commit:** 5815ede8  
**Staging testi:** Flutter-only değişiklik — backend servisleri aktif ✅  

**node5 adımları:**

```bash
cd /var/www/teqlif.com && git pull origin main
# Backend restart gerekmez — Flutter kodu değişti
```

- `user.dart`: 7 sosyal URL alanı eklendi + `fromJson` güncellendi
- `profile_screen.dart`: `_EditProfileScreen.initState()` — `User.fromJson()` typed erişimi

**[PROD FARKI]:** Yok.

---

## TASK-yeni-D · Search Alert Trigger + Flutter Feed Stats

**Staging tarihi:** 2026-09-22  
**Commit:** 275826a1  
**Staging testi:** `cron:check_search_alerts_task` worker başlangıç listesinde görüldü ✅  

**node5 adımları:**

```bash
cd /var/www/teqlif.com && git pull origin main
sudo teqlif-restart
```

Yalnızca kod değişikliği — migration yok:
- `worker.py`: `check_search_alerts_task` — 15dk cron, yeni ilanları aktif alert'larla eşleştirip push bildirimi gönderir
- `listing_analytics_view_model.dart`: `feedStatsProvider` (FutureProvider.family)
- `listing_analytics_screen.dart`: `_FeedStatsCard` widget — premium kullanıcıya özel, 7/30/90 günlük seçici

**[PROD FARKI]:** Yok.

---

## TASK-yeni-C · DM Raporlama — flag_reason Aktivasyonu

**Staging tarihi:** 2026-09-22  
**Commit:** 056f8147  
**Staging testi:** `POST /api/messages/1/flag?reason=spam` → `404 MESSAGE_NOT_FOUND` (endpoint aktif, mesaj yok) ✅  

**node5 adımları:**

```bash
cd /var/www/teqlif.com && git pull origin main
sudo teqlif-restart
```

Yalnızca kod değişikliği — migration yok (`flag_reason` kolonu zaten mevcut):
- `flag_message.py`: `FlagMessageCommand` — receiver kontrolü, valid reason validation
- `messages.py`: `POST /{message_id}/flag?reason=...` endpoint (204, 20/min rate limit)
- `messages_screen.dart`: uzun basma → `_showMessageActions` (sil + raporla menüsü)
- `notification_service.dart`: `flagMessage()` API metodu eklendi

**[PROD FARKI]:** Yok.

---

## TASK-14 · Endpoint Cache Stratejisi

**Staging tarihi:** 2026-09-22  
**Commit:** 64b74338  
**Staging testi:** `redis-cli KEYS "cqrs:*"` → `cqrs:app_config:99914b932bd3` ✅  

**node5 adımları:**

```bash
cd /var/www/teqlif.com && git pull origin main
sudo teqlif-restart
```

Yalnızca kod değişikliği — migration yok:
- `GET /listings/{id}`: `cache_get/cache_set`, ns=`listing:{id}`, params=`{uid}`, TTL=60s
- `GET /users/{username}`: `cache_get/cache_set`, ns=`user_profile`, TTL=300s
- `GET /config/version`: `cache_get/cache_set`, ns=`app_config`, TTL=600s
- `UpdateListingCommand`: commit sonrası `invalidate_cache(f"listing:{listing_id}")`
- `DeleteListingCommand`: commit sonrası `invalidate_cache(f"listing:{listing_id}")`
- `PATCH /auth/me`: commit sonrası `invalidate_cache("user_profile")`

**[PROD FARKI]:** Yok.

---

## TASK-yeni-L · Like Sayıları Redis Counter

**Staging tarihi:** 2026-09-22  
**Commit:** ab1c9a96  
**Staging testi:** `redis-cli GET listing:engagement:1` → `"0"` (nil değil) ✅  

**node5 adımları:**

```bash
cd /var/www/teqlif.com && git pull origin main
sudo teqlif-restart
```

Yalnızca kod değişikliği — migration yok:
- `like_service.py` `batch_listing_likes()`: Redis read-through cache (`listing:engagement:{id}`, 7 gün TTL)
- `toggle_listing_like()`: commit sonrası `listing:engagement:{id}` key invalidate
- `add_stream_like()`: commit sonrası `stream:likes:{id}` INCR + 48 saat TTL
- `batch_stream_likes()`: Redis read-through cache
- `favorites.py` `add_favorite/remove_favorite`: commit sonrası invalidation
- `stream_finalizer.py`: stream bitince `stream:likes:{id}` key silinir

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

## TASK-yeni-G · Pydantic Şema Konsolidasyonu (S5/S6/S10)

**Staging tarihi:** 2026-09-25  
**Commit:** 8a24027f  
**Staging testi:** Tüm import'lar OK; UserMiniOut inheritance doğrulandı; `is_request` ConversationOut'ta yok ✅  

**node5 adımları:**

```bash
cd /var/www/teqlif.com && git pull origin main
sudo teqlif-restart
```

Değişiklikler:
- S5: `UserMiniOut` base class eklendi (`schemas/user.py`); `StoryAuthorOut`/`BlockedUserOut`/`StreamHostOut` türetildi
- S6: `DirectSaleSummaryOut` → discriminated union (`SellerSummaryOut`/`BuyerSummaryOut`); `role` Literal
- S10: `ConversationOut`'tan `is_request` kaldırıldı; `MessageRequestOut` ayrı tip; `/requests` endpoint güncelllendi

**[PROD FARKI]:** Yok.

---

## TASK-19 · Medya Optimizasyonu M1-M4

**Staging tarihi:** 2026-09-25  
**Commit:** 05bccd97  
**Staging testi:** IMAGE_MAX_BYTES: 3MB, VIDEO_MAX_BYTES: 20MB doğrulandı ✅  

**node5 adımları:**

```bash
cd /var/www/teqlif.com && git pull origin main
sudo teqlif-restart
```

Değişiklikler:
- M1: İlan fotoğrafı WebP 1920px q80 (JPEG 1200px'den); max 3 fotoğraf (10'dan)
- M2: İlan videosu `MediumQuality` 720p (`HighestQuality` 1080p'den)
- M3: DM foto limit 5→3MB, DM video 30→20MB (Flutter + backend `media_limits.py`)
- M4: Profil avatarı `profilePhoto` 800px WebP q75 (`dmPhoto` 1200px JPEG'den)

**Not:** Limitler compress sonrası değerler (raw dosya sınırı yok).

**[PROD FARKI]:** Yok.

---

## TASK-22 · KV3 — Analytics Opt-Out Toggle

**Staging tarihi:** 2026-09-25  
**Commit:** a38d0c29  
**Staging testi:** `analytics_opt_out default: False` + NotificationPrefs key doğrulandı ✅  

**node5 adımları:**

```bash
cd /var/www/teqlif.com && git pull origin main
sudo teqlif-restart
```

Değişiklikler:
- `NotificationPrefs` şemasına `analytics_opt_out: bool = False` eklendi
- `analytics.py`: `/track`, `/interaction`, `/track-search` endpointlerinde opt-out kontrolü (`_is_analytics_opted_out`)
- Flutter: `NotificationSettingsState.analyticsOptOut` + `toggleAnalyticsOptOut()` metodu
- UI: Bildirim ayarları ekranında "Gizlilik" bölümü ve toggle
- ARB: `analyticsOptOutTitle`/`analyticsOptOutDesc` + `lblPrivacySettings` (tr/en/ru/ar)

**Not:** Migration yok — `notification_prefs JSONB` içine yeni key, mevcut kayıtlar için `DEFAULT_NOTIF_PREFS` merge garantisi var.

**[PROD FARKI]:** Yok.

---

## TASK-21 · D2/D4/D5 Model Düzeltmeleri

**Staging tarihi:** 2026-09-25  
**Commit:** 59e9fc1c  
**Staging testi:** FK constraint, created_at/updated_at TIMESTAMPTZ doğrulandı ✅  

**node5 adımları:**

```bash
cd /var/www/teqlif.com && git pull origin main
sudo teqlif-restart
```

Alembic migration (`zzzzd_d2_d4_d5_model_fixes`) otomatik çalışır:
- `listings.active_room_id`: FK `live_streams.id ON DELETE SET NULL` eklendi
- `reports.created_at`: `TIMESTAMP WITH TIME ZONE + DEFAULT now()` yapıldı
- `app_configs.updated_at`: `TIMESTAMP WITH TIME ZONE` yapıldı

**Doğrulama:**
```bash
source /var/www/teqlif.com/venv/bin/activate && python3 -c "
import asyncio, re, asyncpg
async def check():
    url = open('/var/www/teqlif.com/backend/.env.production').read()
    dsn = re.search(r'DATABASE_URL=(.+)', url).group(1).strip().replace('postgresql+asyncpg://', 'postgresql://')
    conn = await asyncpg.connect(dsn)
    r1 = await conn.fetchrow(\"SELECT data_type FROM information_schema.columns WHERE table_name='reports' AND column_name='created_at'\")
    print('reports.created_at:', r1['data_type'])
    r2 = await conn.fetchrow(\"SELECT constraint_name FROM information_schema.table_constraints WHERE table_name='listings' AND constraint_name='fk_listings_active_room_id'\")
    print('listings FK:', r2['constraint_name'] if r2 else 'NOT FOUND')
    await conn.close()
asyncio.run(check())
"
```

**[PROD FARKI]:** `.env.production` kullan.

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

---

## TASK-23 — tuci → teqlik Yeniden Adlandırma

**Staging tarihi:** 2026-09-25  
**Commit:** 32bd5f39  
**Staging testi:** `teqlik_balance` kolonu ✅ · `teqlik_transactions` tablosu ✅  

**node5 adımları:**

```bash
cd /var/www/teqlif.com && git pull origin main
sudo teqlif-restart
```

Migration otomatik çalışır (`alembic upgrade head`):
- `tuci_transactions` → `teqlik_transactions`
- `users.tuci_balance` → `users.teqlik_balance`
- `ix_tuci_transactions_user_created` → `ix_teqlik_transactions_user_created`

Doğrulama:
```bash
sudo -u postgres psql teqlif -c "SELECT column_name FROM information_schema.columns WHERE table_name='users' AND column_name='teqlik_balance'; SELECT table_name FROM information_schema.tables WHERE table_name='teqlik_transactions';"
```

Değişiklikler:
- DB: tablo + kolon + index yeniden adlandırıldı (Alembic migration)
- Backend: `TeqlikTransaction`, `teqlik_balance` — `TuciTransaction`/`TuciTransactionRepository` alias'ları geçiş için korundu
- i18n JSON + ARB (tr/en/ru/ar): `TUCi` → `TEQlik`, `tuciSpent` → `teqlikSpent`
- Flutter (13 dosya): tüm `tuci*` referansları `teqlik*` ile değiştirildi

**[PROD FARKI]:** Yok.
