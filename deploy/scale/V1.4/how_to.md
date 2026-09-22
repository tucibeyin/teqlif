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
