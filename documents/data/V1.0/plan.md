# teqlif — Veri Yaşam Döngüsü ve Optimizasyon Planı

**Stack:** FastAPI + PostgreSQL + Redis + ClickHouse + MinIO | Flutter  
**Üretim:** node5 (4c EPYC, 16 GB RAM, 500 GB SSD, 1 Gbps) | node3 staging  
**Referans:** `deploy/scale/V1.4/documents/05_final.md` · `documents/teqlif_architectural_decisions.md`  
**Son güncelleme:** 2026-09-20

---

## Notasyon

| Sembol | Anlam |
|--------|-------|
| 🔴 | Kritik — üretim riski, veri bütünlüğü sorunu veya yüksek birikim |
| 🟡 | Orta — performans ya da büyüme sorunu |
| 🟢 | Düşük — iyileştirme fırsatı |
| ✅ | Mevcut mekanizma çalışıyor |
| ⚠️ | Mekanizma eksik veya bozuk |
| □ | Karar bekleniyor |
| ■ | Onaylandı / uygulandı |

---

## Bölüm 1 — Veri Yaşam Döngüsü (Lifecycle Karar Tablosu)

> **İlk karar noktası.** Her satırdaki saklama süresini onaylayın. Onaylanan değerler Bölüm 5'teki cleanup görevlerine dönüşecektir.

### 1.1 — PostgreSQL Tabloları

#### Yüksek Hacim / Birikim Riski Taşıyanlar

| Tablo | Oluşma Sıklığı | Şu Anki Durum | Önerilen Saklama | Mekanizma | Öncelik |
|-------|---------------|--------------|-----------------|-----------|---------|
| `analytics_events` | Her kullanıcı aksiyonunda | ✅ 90 gün (haftalık cleanup) | □ 90 gün yeterli mi? | ARQ Pzt 04:00 | 🟢 |
| `user_interactions` | Her browse/tıklama | ✅ 90 gün (haftalık cleanup) | □ 90 gün yeterli mi? | ARQ Sal 04:00 | 🟢 |
| `listing_impressions` | Her ilan görüntülemesinde | ✅ 30 gün (günlük cleanup) | □ 30 gün yeterli mi? | ARQ 05:00 | 🟢 |
| `stream_likes` | Her canlı yayın beğenisinde | ✅ 7 gün (günlük cleanup) | □ 7 gün yeterli mi? | ARQ 01:00 | 🟢 |
| `live_stream_viewers` | Her izleyici giriş/çıkışında | ⚠️ **Hiç silinmiyor** | □ Önerilen: 90 gün | Yeni GC görevi | 🔴 |
| `notifications` | Her sistem olayında | ✅ 30 gün (günlük cleanup) | □ 30 gün yeterli mi? | ARQ 03:00 | 🟢 |
| `direct_messages` (text) | Her mesaj gönderiminde | ⚠️ **Hiç silinmiyor** (hidden hariç) | □ Önerilen: sonsuz (konuşma geçmişi) ya da 1 yıl? | Yok | 🟡 |
| `direct_messages` (hidden/shadowban) | Moderasyon kararında | ✅ 60 gün (günlük cleanup) | □ 60 gün yeterli mi? | ARQ 02:30 | 🟢 |
| `direct_messages` (media) | Medya mesajı gönderiminde | ✅ 7 gün (günlük cleanup) | □ 7 gün kısa mı? | ARQ 06:30 + MinIO | 🟡 |
| `message_threads` | İlk mesajda | ⚠️ **Hiç silinmiyor** | □ Önerilen: mesajlar silinince thread da silinsin mi? | Yok | 🟡 |

#### Ticaret ve Finansal Kayıtlar

| Tablo | Oluşma Sıklığı | Şu Anki Durum | Önerilen Saklama | Not |
|-------|---------------|--------------|-----------------|-----|
| `purchases` | Satın alımda | ⚠️ Sonsuz | □ Sonsuz (yasal) | Finansal kayıt — silme önerilmez |
| `tuci_transactions` | Bakiye transferinde | ⚠️ Sonsuz | □ Sonsuz (yasal) | Para akışı — silme önerilmez |
| `auctions` | Açık artırma başladığında | ⚠️ Sonsuz | □ Sonsuz ya da 2 yıl? | Sona erenler anlamsız ama referans olabilir |
| `bids` | Her teklif verildiğinde | ⚠️ Sonsuz | □ Önerilen: açık artırma bitişinden 1 yıl | Ticaret kanıtı, kısa süre gerekli |
| `direct_sales` | Doğrudan satış başladığında | ⚠️ Sonsuz | □ Sonsuz (ticaret kaydı) | |
| `direct_sale_orders` | Sipariş verildiğinde | ⚠️ Sonsuz | □ Sonsuz (ticaret kaydı) | |
| `gift_events` | Her hediye gönderiminde | ⚠️ Sonsuz | □ Önerilen: 1 yıl | Tuci transferi — finansal ama yüksek hacim |
| `rating_history` | Değerlendirme güncellendiğinde | ⚠️ Sonsuz | □ Sonsuz (moderasyon kaydı) | |
| `ratings` | Değerlendirme verildiğinde | ⚠️ Sonsuz | □ Sonsuz (kullanıcı itibarı) | |

#### İlan ve İçerik Verisi

| Tablo | Oluşma Sıklığı | Şu Anki Durum | Önerilen Saklama | Mekanizma |
|-------|---------------|--------------|-----------------|-----------|
| `listings` (aktif) | İlan oluşturulduğunda | ✅ 30 gün aktif | □ 30 gün uygun mu? | ARQ 04:00 |
| `listings` (pasif→silindi) | Pasiften 60 gün sonra | ✅ 60 gün pasif sonra soft-delete | □ Onaylı | ARQ 04:30 + MinIO cleanup |
| `listing_offers` (declined/expired) | Teklif reddedildiğinde | ⚠️ **Hiç silinmiyor** | □ Önerilen: 60 gün | Yeni GC görevi | 🟡 |
| `stories` | Hikaye yüklendiğinde | ✅ `expires_at` (24 saat tipik) | □ Onaylı | ARQ saatlik + MinIO |
| `story_views` | Her hikaye görüntülemesinde | ✅ CASCADE silinir | □ Onaylı | — |
| `story_likes` | Hikaye beğenildiğinde | ✅ CASCADE silinir | □ Onaylı | — |
| `listing_likes` | İlan beğenildiğinde | ⚠️ Sonsuz (CASCADE ile kullanıcı/ilan silinince) | □ Sonsuz uygun | Sosyal veri |
| `favorites` | Favorilere eklendiğinde | ⚠️ Sonsuz (CASCADE) | □ Sonsuz uygun | Sosyal veri |

#### Sosyal ve İletişim Verisi

| Tablo | Oluşma Sıklığı | Şu Anki Durum | Önerilen Saklama | Not |
|-------|---------------|--------------|-----------------|-----|
| `follows` | Takip edildiğinde | ⚠️ Sonsuz (CASCADE) | □ Sonsuz uygun | Sosyal graf |
| `user_blocks` | Engelleme yapıldığında | ⚠️ Sonsuz (CASCADE) | □ Sonsuz uygun | Güvenlik |
| `reports` | Şikayet yapıldığında | ⚠️ Sonsuz | □ Sonsuz uygun | Moderasyon/yasal |
| `referrals` | Davet kullanıldığında | ⚠️ Sonsuz | □ Önerilen: 6 ay | Kampanya kaydı |
| `mass_notification_campaigns` | Kitlesel bildirim gönderiminde | ⚠️ Sonsuz | □ Önerilen: 1 yıl | Kampanya geçmişi |
| `search_alerts` | Kullanıcı uyarı kurduğunda | ⚠️ Sonsuz | □ Önerilen: 180 gün inaktif | Kullanıcı silmezse birikir |

#### Canlı Yayın Verisi

| Tablo | Oluşma Sıklığı | Şu Anki Durum | Önerilen Saklama | Mekanizma |
|-------|---------------|--------------|-----------------|-----------|
| `live_streams` (aktif stale) | Sunucu çökmesinde | ✅ 3 dakika sonra cleanup | □ Onaylı | ARQ 2 dakika |
| `live_streams` (biten) | Yayın bittiğinde | ⚠️ Sonsuz | □ Önerilen: 1 yıl arşiv, sonra sil | Yeni GC görevi |
| `live_stream_viewers` | Her izleyici oturumunda | ⚠️ **Hiç silinmiyor** | □ Önerilen: 90 gün | Yeni GC görevi 🔴 |

#### Çağrı Verisi

| Tablo | Oluşma Sıklığı | Şu Anki Durum | Önerilen Saklama | Mekanizma |
|-------|---------------|--------------|-----------------|-----------|
| `calls` (ghost calling) | Kayıp çağrıda | ✅ 5 dakika | □ Onaylı | ARQ 15 dakika |
| `calls` (ghost active) | Kayıp çağrıda | ✅ 1 saat | □ Onaylı | ARQ 15 dakika |
| `calls` (ended/missed) | Çağrı bittiğinde | ⚠️ **Hiç silinmiyor** | □ Önerilen: 1 yıl | Yeni GC görevi 🟡 |
| `call_participants` | Çağrı başladığında | ✅ CASCADE ile silinir | □ Onaylı | — |

#### Sistem ve Yapılandırma

| Tablo | Oluşma Sıklığı | Şu Anki Durum | Önerilen Saklama | Not |
|-------|---------------|--------------|-----------------|-----|
| `exchange_rates` | Günlük 1 kayıt | ⚠️ **Hiç silinmiyor** | □ Önerilen: 2 yıl | Günlük birikim |
| `app_configs` | Manuel güncelleme | ⚠️ Sonsuz | □ Sonsuz uygun | Küçük tablo |
| `categories` / `subcategories` | Manuel yönetim | ⚠️ Sonsuz | □ Sonsuz uygun | Referans verisi |
| `users` | Kayıtta | ⚠️ Sonsuz | □ Hesap silme politikası? | Bölüm 6'da |

#### ML / Kişiselleştirme

| Tablo | Oluşma Sıklığı | Şu Anki Durum | Önerilen Saklama | Mekanizma |
|-------|---------------|--------------|-----------------|-----------|
| `user_interests` | ARQ her 15 dk (UPSERT) | ✅ Overwrite (birikmez) | □ Onaylı | ARQ compute_user_interests |
| `user_interactions` | Her etkileşimde | ✅ 90 gün | □ 90 gün uygun? | ARQ Sal 04:00 |

---

### 1.2 — ClickHouse Tabloları

TTL'ler `database_clickhouse.py` DDL'inde tanımlı, MergeTree arka planda uygular.

| Tablo | Şu Anki TTL | Önerilen | Karar |
|-------|------------|---------|-------|
| `user_events` | ✅ 30 gün | □ 30 gün yeterli mi? | |
| `feed_analytics` | ✅ 30 gün | □ 30 gün yeterli mi? | |
| `search_events` | ✅ 30 gün | □ 30 gün yeterli mi? | |
| `swipe_live_events` | ✅ 30 gün | □ 30 gün yeterli mi? | |
| `direct_sale_events` | ✅ 180 gün | □ 180 gün uygun mu? | |

> **Not (D51b):** `init_clickhouse()` fonksiyonunda `database=` parametresi eksik — tablolar `default` DB yerine `teqlif_prod_analytics`'e yazılmıyor. Bölüm 3.4'te düzeltme var.

---

### 1.3 — Redis Key Kalıpları

| Key Kalıbı | TTL | Yönetim | Not |
|-----------|-----|---------|-----|
| `session:{id}` | 30 gün | `expire()` | Oturum |
| `blacklist:{jti}` | Token süresi | `setex()` | Revoke token |
| `ch_buf:{table}` | Flush'a kadar (~30s) | Flush loop | ClickHouse buffer |
| `interests:{uid}` | İnvalidate on write | Overwrite | Kullanıcı ilgi skoru |
| `live:viewers:{sid}` | `_VIEWER_TTL` | `expire()` | Canlı izleyici sayısı |
| `rate:*` | Window boyutu | `expire()` | Rate limit |
| `notif:peak_hours:{uid}` | Recompute'da üzerine yazılır | Overwrite | Bildirim saati |
| `cache:listing:{id}` | 60 sn | `setex()` | İlan detay cache |
| `cache:categories` | 1 saat | `setex()` | Kategori listesi |

---

### 1.4 — MinIO Nesneleri

| Bucket / Prefix | İçerik | Şu Anki Durum | Lifecycle Policy | Karar |
|----------------|--------|--------------|-----------------|-------|
| `teqlif/listings/` | İlan fotoğrafları ve videoları | ✅ Listing soft-delete'de silinir | ⚠️ YOK | □ Güvenlik ağı için 365 gün lifecycle ekle |
| `teqlif/stories/` | Hikaye videoları ve thumb | ✅ expires_at'da silinir (story_service) | ⚠️ YOK | □ 2 gün lifecycle güvenlik ağı |
| `teqlif-dm/` | DM medya dosyaları | ✅ 7 gün ARQ cleanup | ⚠️ YOK | □ 14 gün lifecycle güvenlik ağı |
| `teqlif/avatars/` | Profil fotoğrafları | ⚠️ Eski avatar güncellenmede siliniyor; hesap silinince? | ⚠️ YOK | □ Hesap silme akışı + lifecycle |
| `teqlif/highlights/` | Hype highlight videoları | ✅ 2 saat ARQ cleanup (local disk) | — | Lokal disk, MinIO değil |

> **Kritik:** MinIO'da lifecycle policy yok. Uygulama katmanı silme çağrısı kaçırılırsa dosyalar sonsuza kalır. Güvenlik ağı olarak her bucket'a lifecycle eklenmeli.

---

### 1.5 — İzleme Sistemi (node3)

| Sistem | Retention | Yapılandırma | Karar |
|--------|-----------|-------------|-------|
| Prometheus TSDB | ✅ 30 gün | `--storage.tsdb.retention.time=30d` | □ 30 gün uygun |
| Loki log | ✅ 14 gün | `retention_period: 336h` | □ 14 gün uygun |
| Backup (local node5) | ✅ 2 gün | `BACKUP_RETENTION_LOCAL_DAYS=2` | □ 2 gün uygun |
| Backup (remote node3) | ✅ 7 gün | `BACKUP_RETENTION_REMOTE_DAYS=7` | □ 7 gün uygun |

---

## Bölüm 2 — Veri Yapısı (Schema Audit)

### 2.1 — Finansal Alan Tipleri: Float → Numeric 🔴

Float, IEEE 754 kayan nokta hatası nedeniyle finansal değerler için güvensiz.

| Tablo | Kolon | Şu Anki Tip | Olması Gereken |
|-------|-------|------------|----------------|
| `listings` | `price` | `Float` | `Numeric(12, 2)` |
| `listings` | `buy_it_now_price` | `Float` | `Numeric(12, 2)` |
| `listings` | `last_sold_price` | `Float` | `Numeric(12, 2)` |
| `listings` | `last_start_price` | `Float` | `Numeric(12, 2)` |
| `auctions` | `start_price` | `Float` | `Numeric(12, 2)` |
| `auctions` | `buy_it_now_price` | `Float` | `Numeric(12, 2)` |
| `auctions` | `final_price` | `Float` | `Numeric(12, 2)` |
| `bids` | `amount` | `Float` | `Numeric(12, 2)` |
| `purchases` | `price` | `Float` | `Numeric(12, 2)` |
| `listing_offers` | `amount` | `Float` | `Numeric(12, 2)` |
| `search_alerts` | `max_price` | `Float` | `Numeric(12, 2)` |
| `users` | `max_budget` | `Float` | `Numeric(12, 2)` |
| `exchange_rates` | `usd_try`, `eur_try` | `Float` | `Numeric(10, 4)` |
| `direct_sales` | `price` | `Numeric(10, 2)` | ✅ Doğru |
| `direct_sale_orders` | `unit_price` | `Numeric(10, 2)` | ✅ Doğru |
| `tuci_transactions` | `amount` | `Integer` | ✅ Doğru (teqlik tamsayı) |

> Alembic migration: `ALTER TABLE ... ALTER COLUMN ... TYPE NUMERIC(12,2) USING price::numeric`  
> Tek `op.execute()` per kolon (asyncpg multi-statement yasak — bkz. `feedback_alembic_asyncpg.md`)

---

### 2.2 — Model Hataları

| # | Tablo | Sorun | Etki |
|---|-------|-------|------|
| D1 | `image_urls: Text` | JSON array text olarak saklanıyor | JSONB yapılmalı — GIN index, doğrudan sorgu |
| D2 | `listings.active_room_id` | ForeignKey tanımlanmamış | Referans bütünlüğü yok |
| D3 | `auctions.status` | `default="completed"` | Yeni açık artırma tamamlanmış görünüyor — `"active"` olmalı |
| D4 | `reports.created_at` | `DateTime` (timezone=False) + `datetime.utcnow()` | Diğer tablolarla uyumsuz |
| D5 | `app_configs.updated_at` | `DateTime` (timezone=False) | Tüm diğerleri timezone=True |
| D6 | `analytics_events` model | `Column()` API (legacy) | Diğerleri `Mapped[]` kullanıyor — tutarsızlık |
| D7 | `user_interactions` model | `Column()` API (legacy) | Aynı |
| D8 | `app_configs.value` | `String` (unbounded) | `String(4096)` gibi bir limit konmalı |

---

### 2.3 — Önerilen JSONB Dönüşümleri

| Tablo | Kolon | Şu Anki | Öneri | Gerekçe |
|-------|-------|---------|-------|---------|
| `listings` | `image_urls` | `Text` (JSON string) | `JSONB` | GIN index, dizi sorgusu |
| `users` | `notification_prefs` | `JSON` | `JSONB` | Indekslenebilir |
| `listings` | `extra_data` | `JSONB` | ✅ Doğru | |

---

### 2.4 — tuci → teqlik Yeniden Adlandırma

Para birimi adı sistem genelinde değişecek:

| Katman | Değişiklik |
|--------|-----------|
| DB | `tuci_transactions` → `teqlik_transactions`, `tuci_balance` → `teqlik_balance` |
| Python | Model, repository, use_case, schema sınıf/alan adları |
| API | JSON response field isimleri (`tuci_balance` → `teqlik_balance`) |
| Flutter | ViewModel, DTO, i18n ARB anahtarları |

Strateji: atomic deploy — DB migration + Python deploy + Flutter sürümü aynı anda.  
Geçiş döneminde API dual-key (hem `tuci_balance` hem `teqlik_balance` döndürülür).

---

## Bölüm 3 — Database Mimarisi

### 3.1 — PostgreSQL: PgBouncer Aktivasyonu 🔴

**Sorun:** 4 ARQ worker × 30 bağlantı = 120, PG default `max_connections=100`'ü aşıyor.  
**Durum:** `config.py`'de `use_pgbouncer: bool = False` — kodlanmış, devre dışı.

```
Şu An:
  API (4 worker) → doğrudan PostgreSQL → bağlantı sınırı aşılıyor

Hedef:
  API (4 worker) → PgBouncer :5432 → PostgreSQL :5433
  PgBouncer pool: transaction mode, max 30 PG bağlantısı
```

**Adımlar:**
1. node5'te PgBouncer kurulumu ve `pgbouncer.ini` yapılandırması
2. `config.py`: `use_pgbouncer: bool = True`, DB port güncelleme
3. `systemd/pgbouncer.service` oluşturma
4. Staging'de test → prod deploy

**Başarı kriteri:** `pg_stat_activity` → max 30 aktif bağlantı, wait = 0

---

### 3.2 — PostgreSQL: Index Stratejisi

**Eksik composite index'ler:**

| Tablo | Index | Sorgu Amacı |
|-------|-------|------------|
| `live_streams` | `(stream_id, status)` | Aktiif yayın sorgulama |
| `tuci_transactions` | `(user_id, created_at DESC)` | Cüzdan geçmişi |
| `listing_offers` | `(listing_id, status)` | Teklife göre filtreleme |
| `follows` | `(follower_id, followed_id)` UNIQUE | Takip kontrolü |
| `purchases` | `(buyer_id, created_at DESC)` | Alıcı satın alım geçmişi |
| `calls` | `(caller_id, status)`, `(callee_id, status)` | ✅ Var |
| `bids` | `(stream_id, created_at DESC)` | Açık artırma teklif geçmişi |
| `analytics_events` | `(user_id, created_at)` | Kullanıcı bazlı analiz |
| `user_interactions` | `(user_id, created_at)` | ML sorgu performansı |

**Not:** `CREATE INDEX CONCURRENTLY` transaction içinde yasak — teqlif env.py transaction kullandığı için tüm index migration'ları `op.execute()` ile ayrı blokta çalıştırılmalı (bkz. `feedback_alembic_concurrently.md`).

---

### 3.3 — Redis: Namespace ve DB Ayrımı

Mevcut V1.4 yapısı (`05_final.md`'den):
- **DB0:** Uygulama verisi — session, i18n, ch_buf, interests, cache:*
- **DB1:** Ops verisi — rate limit, edge_metrics

**Kural:** Mevcut key yapısı değiştirilmez. Yeni cache key'ler `cache:` prefix'i ile DB0'a eklenir. SECURITY_CRITICAL key'lere (session, blacklist, rate limit) dokunulmaz.

**Cache taksonomisi (`teqlif_architectural_decisions.md` §9):**

| Kategori | Örnekler | TTL |
|---------|---------|-----|
| SCHEMA_VERSIONED | `/api/catalog`, field-config | Schema migration'da invalidate |
| ALGORITHMIC | Feed, trending, user_interests | 30s – 5 dk |
| LIFECYCLE | Auction state, stream state | Event-driven invalidate |
| SECURITY_CRITICAL | Session, token blacklist | Token süresince |
| EPHEMERAL | Listing detay, user profile | 30s – 5 dk |

---

### 3.4 — ClickHouse: DDL Hatası

**Sorun (D51b):** `init_clickhouse()` fonksiyonunda `database=` parametresi eksik. Tablolar hedef DB yerine `default` DB'de açılıyor.

```python
# Hatalı (database_clickhouse.py):
_client = await clickhouse_connect.get_async_client(
    host=settings.clickhouse_host,
    port=settings.clickhouse_port,
    # database= eksik!
)

# Doğru:
_client = await clickhouse_connect.get_async_client(
    host=settings.clickhouse_host,
    port=settings.clickhouse_port,
    database=settings.clickhouse_db,  # "teqlif_prod_analytics"
)
```

**Not:** `get_clickhouse_client()` zaten doğru — sadece `init_clickhouse()` bozuk.

---

## Bölüm 4 — Sorgu Optimizasyonu ve Cache

### 4.1 — Endpoint Cache Stratejisi

| Endpoint | Şu An | Öneri | TTL | Cache Kategorisi |
|---------|-------|-------|-----|----------------|
| `GET /listings/{id}` | DB sorgusu | Redis cache | 60 sn | EPHEMERAL |
| `GET /users/{id}` (profil) | DB sorgusu | Redis cache | 5 dk | EPHEMERAL |
| `GET /catalog/categories` | DB sorgusu | Redis cache | 1 saat | SCHEMA_VERSIONED |
| `GET /app-config` | DB sorgusu | Redis cache | 10 dk | SCHEMA_VERSIONED |
| `GET /listings/feed` | DB sorgusu | Redis cache | 30 sn | ALGORITHMIC |
| `GET /listings/{id}/offers` | DB sorgusu | Redis cache | 30 sn | LIFECYCLE |
| Listing feed sıralaması | Hesaplanmış | Redis cache | 30 sn | ALGORITHMIC |

**Kural:** Schema değişikliği olan her Alembic migration'ına `bump_schema_version()` çağrısı eklenmeli.

---

### 4.2 — N+1 Sorgu Düzeltmeleri

**Feed sorgusu — şu an:**
```sql
SELECT * FROM listings LIMIT 20;
-- Her listing için: SELECT * FROM users WHERE id = ?   ← N+1
-- Her listing için: SELECT * FROM favorites WHERE ...  ← N+1
```

**Düzeltme:**
```sql
SELECT l.*, u.username, u.rating_avg,
       (SELECT COUNT(*) FROM favorites WHERE listing_id = l.id) AS fav_count
FROM listings l
JOIN users u ON u.id = l.user_id
WHERE l.status = 'active'
ORDER BY l.created_at DESC, l.id DESC
LIMIT 20
```

| Sorun | Endpoint | Fix |
|-------|---------|-----|
| Satıcı bilgisi N+1 | Feed, arama | JOIN users |
| Favori durumu N+1 | Feed, detay | Toplu `WHERE listing_id IN (...)` |
| Teklif sayısı N+1 | Feed | COUNT subquery |
| Stream izleyici N+1 | Aktif yayın listesi | JOIN live_stream_viewers |

---

### 4.3 — Keyset (Cursor) Pagination

**Şu An (OFFSET):**
```sql
SELECT * FROM listings ORDER BY created_at DESC LIMIT 20 OFFSET 100
-- OFFSET 100: 120 satır okur, 100'ünü atar → yavaşlar
```

**Hedef (Keyset):**
```sql
-- Sonraki sayfa (cursor: last_seen_at + last_seen_id):
SELECT * FROM listings
WHERE status = 'active'
  AND (created_at, id) < (:last_seen_at, :last_seen_id)
ORDER BY created_at DESC, id DESC
LIMIT 20
```

| Endpoint | Öncelik |
|---------|---------|
| Listing feed | 🔴 Öncelikli |
| Cüzdan geçmişi | 🔴 Öncelikli |
| Mesaj geçmişi | 🟡 Thread id sonrası |
| Bildirimler | 🟡 Orta |

---

### 4.4 — JSONB Sorgu Optimizasyonu

`listings.image_urls` Text → JSONB geçişi sonrası:
```sql
-- GIN index ile: belirli URL içeren ilanları bul
SELECT id FROM listings WHERE image_urls @> '["https://..."]'::jsonb

-- İlk görseli doğrudan al:
SELECT image_urls->0 AS first_image FROM listings WHERE id = ?
```

---

## Bölüm 5 — Temizleme ve Garbage Collection

### 5.1 — Mevcut ARQ Cron Takvimi

#### Temizlik Görevleri

| Görev | Zamanlama | Silinen Veri | Durum |
|-------|-----------|-------------|-------|
| `cleanup_stale_streams_task` | Her 2 dakika | `live_streams` stale (>3dk) | ✅ |
| `cleanup_ghost_calls_task` | Her 15 dakika | `calls` ghost (calling>5dk, active>1s) | ✅ |
| `cleanup_expired_stories_task` | Saatlik | `stories` + MinIO | ✅ |
| `cleanup_hype_highlights_task` | Saatlik | `highlights` + local disk | ✅ |
| `cleanup_old_stream_likes_task` | Günlük 01:00 | `stream_likes` >7 gün | ✅ |
| `cleanup_hidden_messages_task` | Günlük 02:30 | `direct_messages` (hidden, >60 gün) | ✅ |
| `cleanup_old_notifications_task` | Günlük 03:00 | `notifications` >30 gün | ✅ |
| `deactivate_expired_listings_task` | Günlük 04:00 | `listings` aktif >30 gün → pasif | ✅ |
| `delete_expired_inactive_listings_task` | Günlük 04:30 | `listings` pasif >60 gün → soft-delete + MinIO | ✅ |
| `cleanup_old_analytics_task` | Haftalık Pzt 04:00 | `analytics_events` >90 gün + VACUUM | ✅ |
| `cleanup_old_user_interactions_task` | Haftalık Sal 04:00 | `user_interactions` >90 gün + VACUUM | ✅ |
| `cleanup_old_impressions_task` | Günlük 05:00 | `listing_impressions` >30 gün | ✅ |
| `cleanup_old_media_messages_task` | Günlük 06:30 | `direct_messages` media >7 gün + MinIO | ✅ |

#### Veri İşleme Görevleri

| Görev | Zamanlama | Kategori |
|-------|-----------|---------|
| `flush_interactions_to_db` | Her 5 dakika | Redis → PG sync |
| `sync_ad_campaigns_task` | Her 10 dakika | Reklam bütçe sync |
| `compute_user_interests_task` | Her 15 dakika | Kişiselleştirme |
| `compute_user_condition_preferences_task` | Her 15 dakika | Kişiselleştirme |
| `invalidate_swipe_live_configs_task` | Her 15 dakika | Cache invalidate |
| `sync_swipelive_interests_task` | Her 20 dakika | Kişiselleştirme |
| `compute_trending_listings_task` | Her 30 dakika | Analytics |
| `backfill_listing_embeddings_task` | Her 30 dakika | ML backfill |
| `backfill_listing_quality_scores_task` | Saatlik :45 | ML backfill |
| `populate_foryou_feed_task` | Saatlik | Feed cache |
| `compute_trending_categories_task` | 6 saatte bir | Analytics |
| `rebuild_faiss_index_task` | 2x/gün 00:00 ve 12:00 | ML |
| `compute_seller_badges_task` | Günlük 01:30 | Compute |
| `train_swipe_live_als_task` | Günlük 01:00 | ML eğitim |
| `train_feed_als_task` | Günlük 01:30 | ML eğitim |
| `calculate_user_budgets_task` | Günlük 02:00 | Compute |
| `compute_trust_scores_task` | Günlük 02:15 | Compute |
| `process_churn_and_airdrop` | Günlük 03:30 | Process |
| `optimize_notification_timing_task` | Günlük 04:00 | Compute |
| `nsfw_backfill_task` | Günlük 05:15 | ML backfill |
| `backfill_phash_task` | Günlük 05:30 | ML backfill |
| `hesitation_retarget_task` | Günlük 06:00 | Bildirim |
| `train_bpr_task` | Pzt+Çar+Cmt 00:30 | ML eğitim |
| `train_item2vec_task` | Haftalık Paz 02:00 | ML eğitim |
| `train_kmeans_cold_start_task` | Çar+Paz 02:15 | ML eğitim |
| `train_churn_model_task` | Haftalık Pzt 02:30 | ML eğitim |
| `train_listing_quality_model_task` | Haftalık Paz 02:30 | ML eğitim |

---

### 5.2 — Eksik GC Görevleri (Onay Bekleniyor)

| # | Yeni Görev | Tablo | Öneri | Zamanlama |
|---|-----------|-------|-------|-----------|
| GC1 | `cleanup_old_stream_viewers_task` | `live_stream_viewers` | >90 gün sil | Haftalık Çar 04:00 |
| GC2 | `cleanup_old_calls_task` | `calls` (ended/missed) | >1 yıl sil | Haftalık Per 04:00 |
| GC3 | `cleanup_old_listing_offers_task` | `listing_offers` (declined) | >60 gün sil | Haftalık Cum 04:00 |
| GC4 | `cleanup_old_exchange_rates_task` | `exchange_rates` | >2 yıl sil | Aylık 1. gün 05:00 |
| GC5 | `cleanup_old_streams_task` | `live_streams` (biten) | >1 yıl sil | Aylık 1. gün 06:00 |
| GC6 | `cleanup_empty_message_threads_task` | `message_threads` | 0 mesaj + >30 gün | Haftalık Paz 05:00 |
| GC7 | `cleanup_old_gift_events_task` | `gift_events` | >1 yıl sil | Aylık 1. gün 04:00 |
| GC8 | `cleanup_inactive_search_alerts_task` | `search_alerts` | >180 gün inaktif sil | Haftalık Paz 06:00 |

> GC1 kritik: `live_stream_viewers` yüksek yazma hacmi + cleanup yok → sınırsız büyüme.

---

### 5.3 — MinIO Lifecycle Policy

Her bucket için `mc ilm add` ile S3 lifecycle kuralı:

| Bucket | Öneri | Gerekçe |
|--------|-------|---------|
| `teqlif/listings/` | 365 gün | Güvenlik ağı — uygulama kayıp silme |
| `teqlif/stories/` | 2 gün | Güvenlik ağı — expires_at cleanup kaçırılırsa |
| `teqlif-dm/` | 14 gün | Güvenlik ağı — 7 günlük cron kaçırılırsa |
| `teqlif/avatars/` | — (lifecycle değil, hesap silme akışı) | Kullanıcı silme akışına ekle |

---

## Bölüm 6 — Veri Anonimleştirme

### 6.1 — Hesap Silme Akışı

Kullanıcı hesabını sildiğinde ne olmalı:

| Veri | Şu Anki Davranış | Öneri |
|------|-----------------|-------|
| `users` satırı | Yok (soft-delete mi?) | Soft-delete: `status = 'deleted'`, PII alanları null |
| `users.email` | Saklanıyor | → `deleted_{id}@teqlif.com` |
| `users.full_name` | Saklanıyor | → `Silinmiş Kullanıcı` |
| `users.profile_image_url` | Saklanıyor | MinIO'dan sil |
| `direct_messages` | CASCADE yok | İçeriği null yap, `sender_id` null kalır |
| `analytics_events` | `user_id SET NULL` (FK var) | ✅ Zaten anonim kalır |
| `user_interactions` | `user_id SET NULL` | ✅ Zaten anonim kalır |
| `purchases` / `transactions` | `user_id FK` | Sakla — finansal kayıt |
| MinIO avatars | — | Silme akışına ekle |

### 6.2 — Analytics Anonimleştirme

ClickHouse `user_events`, `feed_analytics`: `user_id = 0` kayıtları anonim kullanıcı.  
Silinen kullanıcının event'leri zaten `user_id = 0` olarak kalır (FK yoktur ClickHouse'da).

### 6.3 — KVKK Uyumu

| Gereksinim | Durum |
|-----------|-------|
| Kullanıcı verisini silme talebi | ⚠️ Akış tanımlanmamış |
| Veri dışa aktarma talebi | ⚠️ Endpoint yok |
| Analytics opt-out | ⚠️ Yok |
| IP adresi saklama (`analytics_events.ip_address`) | 🔴 Saklıyor — maskeleme veya silme gerekli |

> `analytics_events.ip_address` KVKK kapsamında kişisel veri sayılır. Son oktet maskelenebilir: `192.168.1.x`

---

## Bölüm 7 — ML ve Tracking Verisi Optimizasyonu

### 7.1 — ARQ Worker Frekans Optimizasyonu

Onay bekleyen değişiklikler — kaynak tasarrufu:

| # | Görev | Şu An | Öneri | Kaynak Tasarrufu | Gerekçe |
|---|-------|-------|-------|-----------------|---------|
| W1 | `compute_user_interests_task` | Her 15 dk (96x/gün) | **2x/gün (08:00, 20:00)** | ~94 ClickHouse sorgusu/gün | İlgi profili saatlerce değişmez |
| W2 | `backfill_listing_embeddings_task` | Her 30 dk (gündüz dahil) | **3x/gün gece (02:00, 03:00, 04:00)** | CPU gündüz serbest kalır | sentence-transformers CPU-yoğun |
| W3 | `compute_user_condition_preferences_task` | Her 15 dk (96x/gün) | **4x/gün** | ~92 Redis işlemi/gün | Condition tercihi çok yavaş değişir |
| W4 | `populate_foryou_feed_task` | Saatlik (24x/gün) | **6x/gün** | ~18 hesaplama/gün | Interest verisi 2x/gün güncelleniyor |
| W5 | `compute_trending_listings_task` | Her 30 dk (48x/gün) | **4x/gün** | ~44 ClickHouse sorgusu/gün | 30dk TTL zaten var, 6s yenileme yeterli |
| W6 | `train_feed_als_task` | Günlük | **Haftalık** (ADR §3.3) | 6 gece CPU serbest | ADR zaten haftalık öneriyor |
| W7 | `train_swipe_live_als_task` | Günlük | **Haftalık** (ADR §3.3) | 6 gece CPU serbest | ADR zaten haftalık öneriyor |

**Sabit tutulanlar (değiştirme):**

| Görev | Gerekçe |
|-------|---------|
| `flush_interactions_to_db` (5dk) | Redis buffer — gecikmede veri kaybı riski |
| `sync_ad_campaigns_task` (10dk) | Reklam bütçe bütünlüğü |
| `cleanup_stale_streams_task` (2dk) | Gerçek zamanlı LiveKit güvenlik ağı |
| `invalidate_swipe_live_configs_task` (15dk) | SwipeLive real-time konfigürasyon |

---

### 7.2 — node5 Gece Yük Haritası (00:00–07:00)

```
00:00  rebuild_faiss_index_task       CPU: yüksek
00:30  train_bpr_task (Pzt/Çar/Cmt)  CPU: çok yüksek
01:00  cleanup_old_stream_likes
01:00  train_swipe_live_als_task      CPU: yüksek
01:30  compute_seller_badges
01:30  train_feed_als_task            CPU: yüksek
02:00  calculate_user_budgets
02:00  train_item2vec_task (Paz)      CPU: yüksek
02:15  compute_trust_scores
02:15  train_kmeans_cold_start (Çar/Paz)
02:30  cleanup_hidden_messages
02:30  train_listing_quality_model (Paz)
02:45  teqlif-backup (pg_dump+redis+CH)  IO: yüksek
03:00  cleanup_old_notifications
03:30  process_churn_and_airdrop
04:00  deactivate_expired_listings
04:00  cleanup_old_analytics (Pzt)    DB: çok yüksek (bulk DELETE)
04:30  delete_expired_inactive_listings
05:00  cleanup_old_impressions
05:15  nsfw_backfill                  CPU: yüksek (NudeNet)
05:30  backfill_phash
06:00  hesitation_retarget
06:00  teqlif-healthcheck.timer
06:30  cleanup_old_media_messages
```

**Tespit:** W6+W7 onaylanırsa (ALS haftalık) → 01:00-01:30 arası 5 gece CPU yükü azalır.

---

### 7.3 — ClickHouse Analytics Akışı

```
Flutter / API → buffer_user_event() → Redis ch_buf:user_events
                                           │
                                      flush_loop() her 30s
                                      veya 5000 satır
                                           │
                                      ClickHouse INSERT (batch)
                                      teqlif_prod_analytics.user_events
                                           │
                                      MergeTree TTL 30 gün
                                      (otomatik arka plan silme)
```

Tablo TTL'leri `database_clickhouse.py`'de tanımlı. D51b (init_clickhouse DB parametresi) düzeltilmeden tüm tablolar `default` DB'ye yazılır.

---

## Bölüm 8 — Medya Verisi

### 8.1 — Mevcut Durum

| Medya Tipi | Limit | İşleme | Depolama |
|-----------|-------|--------|---------|
| İlan fotoğrafı | 5 MB | Thumbnail 400×400 JPEG q85 | MinIO `teqlif/listings/` |
| İlan videosu | 50 MB, 60 sn | ffmpeg remux + audio AAC 128k (video yeniden kodlanmıyor) | MinIO `teqlif/listings/` |
| DM fotoğrafı | 5 MB | Thumbnail 400×400 JPEG q85 | MinIO `teqlif-dm/` |
| DM videosu | 30 MB, 90 sn | ffmpeg remux + AAC (video yeniden kodlanmıyor) | MinIO `teqlif-dm/` |
| DM ses | 2 MB, 10 dk | — (Opus 16kbps VBR) | MinIO `teqlif-dm/` |
| Hikaye | ffmpeg sıkıştırma var | H.264 → re-encode (story_service) | MinIO `teqlif/stories/` |
| Profil fotoğrafı | 5 MB | Thumbnail | MinIO `teqlif/avatars/` |

---

### 8.2 — Sıkıştırma İyileştirme Önerileri

| # | Konu | Şu An | Öneri | Etki |
|---|------|-------|-------|------|
| M1 | İlan fotoğrafı formatı | JPEG (orijinal format saklanıyor) | WebP'ye dönüştür (quality=80) | ~%30-40 boyut azalması |
| M2 | İlan fotoğrafı boyut sınırı | Kaynak boyut değiştirilmiyor | Max 1920px uzun kenar (sunucu tarafı) | Büyük dosyalar küçülür |
| M3 | Video yeniden kodlama | `-c:v copy` (kopya) | CRF 28, max 1080p, aac 96k | İlan videosu ~%50 küçülür |
| M4 | Thumbnail formatı | JPEG (ext'e göre) | Tümü WebP q70, max 400×400 | Thumbnail boyutu ~%40 azalır |
| M5 | DM medya boyut sınırı | 5 MB / 30 MB | DM foto → 3 MB, DM video → 20 MB | Storage + bandwidth tasarrufu |
| M6 | Profil fotoğrafı | JPEG q85 | WebP q75, max 800×800 | Profil yükü azalır |

> M1-M4: client taraflı da yapılabilir (Flutter'da `image_picker` sıkıştırma) — sunucu tarafı daha güvenilir.

---

### 8.3 — Depolama Yönetimi

**Silinme akışları:**

| Tetikleyici | Silinen MinIO Nesnesi | Kod Yeri |
|------------|----------------------|---------|
| Listing soft-delete (ARQ) | `listings/{id}/*` | `listing_cleanup.delete_listing_files()` |
| Story expires_at (ARQ saatlik) | `stories/{filename}` | `story_service.cleanup_expired_stories()` |
| DM media >7 gün (ARQ) | `dm/{filename}` | `cleanup_old_media_messages_task` |
| Avatar güncelleme | Eski avatar | `auth.py:1565` |
| Listing güncelleme (eski fotoğraf) | Eski görseller | `update_listing.py:139` |
| Hikaye kullanıcı silmesi | `stories/{filename}` | `story_service.delete_story()` |

**Boşluk:** Kullanıcı hesabı silindiğinde avatar silinmiyor (GC planına ekle).  
**Boşluk:** `listing_cleanup` listing owner user silindiğinde çağrılmıyor.

---

## Bölüm 9 — Mesajlaşma Verisi

### 9.1 — DM Lifecycle

```
Mesaj gönderildi
    │
    ▼
direct_messages (PostgreSQL)
    │
    ├─ content_type = text  → sonsuz (kullanıcı silmezse)
    ├─ content_type = media → 7 gün → ARQ cleanup + MinIO sil
    ├─ is_hidden = true     → 60 gün → ARQ cleanup (moderasyon)
    └─ is_shadowbanned      → görünmez, silinmez
```

**Karar bekleniyor:** Text mesajları ne kadar tutulacak?

| Seçenek | Gerekçe |
|---------|---------|
| Sonsuz | Kullanıcı kendi geçmişini görmek ister |
| 1 yıl | Disk tasarrufu, kullanıcı bilgilendirilir |
| Kullanıcı kontrolü | Kullanıcı kendi siler — uygulamada zaten var |

---

### 9.2 — Thread Yönetimi

`message_threads` tablosu her konuşma için bir kayıt tutar. Mesajlar silinse de thread kalır.

**Sorun:** Boş thread'ler (0 mesaj) birikmesi.  
**Öneri (GC6):** 30 gün mesajsız thread'leri haftalık temizle.

---

### 9.3 — Mesaj İndeks Yapısı

Büyük `direct_messages` tablosunda yavaş sorgular için:

```sql
-- Şu an:
SELECT * FROM direct_messages
WHERE (sender_id = :uid OR receiver_id = :uid)
ORDER BY created_at DESC LIMIT 50
-- Sorun: OR ile index kullanamaz

-- Öneri: thread_id FK ekle
-- Her mesaj thread'e bağlı → thread bazlı sorgu mümkün
SELECT * FROM direct_messages
WHERE thread_id = :tid
ORDER BY created_at DESC LIMIT 50
```

---

## Bölüm 10 — Node Kaynak Bütçesi (V1.4)

### node5 — Production Core

**Donanım:** 4 core EPYC 7282, 16 GB RAM, 500 GB SSD, 1 Gbps unmetered

| Servis | RAM Bütçesi | Disk Bütçesi |
|--------|------------|-------------|
| PostgreSQL | ~3 GB | ~50 GB (büyüme: +1 GB/ay) |
| Redis | 4 GB (maxmemory) | — (AOF+RDB: ~500 MB) |
| ClickHouse | ~2 GB | ~20 GB/yıl (TTL aktif) |
| MinIO | ~500 MB | ~200 GB (media + lifecycle ile sınırlandır) |
| FastAPI (4 worker) | ~2 GB | — |
| ARQ workers (2) | ~1 GB | — |
| ML modeller | ~2 GB | ~5 GB |
| **Toplam** | **~14.5 GB / 16 GB** | **~275 GB / 500 GB** |

**Kritik:** RAM bütçesi %90 dolu. W1-W7 frekans azaltımı + PgBouncer aktivasyonu birlikte uygulanmalı.

### node3 — Staging + AI Proxy + Monitoring

**Donanım:** 4 core, ~4 GB RAM (Zap-Hosting, panel girişi 90 günde bir: 2026-12-10)

| Servis | RAM Bütçesi |
|--------|------------|
| FastAPI + ARQ (staging) | ~800 MB |
| PostgreSQL (staging) | ~600 MB |
| AI Proxy (production trafiği) | ~400 MB |
| Redis (staging) | ~300 MB |
| Prometheus + Grafana | ~400 MB |
| Loki + Promtail | ~300 MB |
| ClickHouse (staging) | ~500 MB |
| **Toplam** | **~3.3 GB / ~4 GB** |

---

## Bölüm 11 — Uygulama Öncelik Matrisi

### 11.1 — Kritik (Hemen)

| # | İş | Bölüm | Etki |
|---|---|-------|------|
| P1 | PgBouncer aktivasyonu | 3.1 | 🔴 Bağlantı limiti aşılıyor |
| P2 | D51b: init_clickhouse() DB parametresi | 3.4 | 🔴 Analytics yanlış DB'ye yazıyor |
| P3 | D3: auction.status default="active" | 2.2 | 🔴 Yeni açık artırma tamamlanmış görünüyor |
| P4 | GC1: live_stream_viewers cleanup | 5.2 | 🔴 Sınırsız büyüme |
| P5 | MinIO lifecycle policy | 5.3 | 🔴 Güvenlik ağı yok |

### 11.2 — Yüksek (1 sprint)

| # | İş | Bölüm | Etki |
|---|---|-------|------|
| P6 | Float → Numeric (finansal alanlar) | 2.1 | 🔴 Yuvarlama hatası riski |
| P7 | W1: compute_user_interests_task 15dk → 2x/gün | 7.1 | ~94 sorgu/gün tasarrufu |
| P8 | W2: backfill_embeddings gündüz → gece | 7.1 | Gündüz CPU baskısı azalır |
| P9 | D1: listings.image_urls Text → JSONB | 2.3 | Sorgu optimizasyonu |
| P10 | Composite index'ler | 3.2 | Sorgu performansı |
| P11 | GC3: listing_offers cleanup | 5.2 | Birikim önlenir |
| P12 | GC4: exchange_rates cleanup | 5.2 | Günlük birikim önlenir |

### 11.3 — Orta (2. sprint)

| # | İş | Bölüm | Etki |
|---|---|-------|------|
| P13 | tuci → teqlik rename | 2.4 | Sistem geneli |
| P14 | Keyset pagination (feed + cüzdan) | 4.3 | Büyük tablolarda performans |
| P15 | Endpoint cache stratejisi | 4.1 | p95 latency düşer |
| P16 | GC2: calls cleanup | 5.2 | Birikim önlenir |
| P17 | W3-W5 frekans azaltımları | 7.1 | CPU tasarrufu |
| P18 | Feed N+1 fix | 4.2 | DB sorgu sayısı azalır |
| P19 | KVKK: ip_address maskeleme | 6.3 | Uyumluluk |

### 11.4 — Düşük (3. sprint)

| # | İş | Bölüm | Etki |
|---|---|-------|------|
| P20 | Medya WebP sıkıştırma (M1-M4) | 8.2 | Storage + bandwidth |
| P21 | W6-W7: ALS haftalığa geçiş | 7.1 | Gece CPU tasarrufu |
| P22 | Hesap silme akışı (anonimleştirme) | 6.1 | KVKK |
| P23 | Mesaj thread cleanup (GC6) | 9.2 | Küçük tablo |
| P24 | D4-D8: Diğer model hataları | 2.2 | Kalite |
| P25 | GC5-GC8 diğer cleanup görevleri | 5.2 | Uzun vadeli |

---

## Bölüm 12 — Karar Tabloları

> Kararlar birbirini besler. Önce bağımlılık haritasını okuyun (12.0), sonra sırasıyla ilerleyin.

---

### 12.0 — Bağımlılık Haritası ve Mevcut Uyumsuzluklar

#### 12.0.1 — Tespit Edilen Kritik Uyumsuzluklar (Mevcut Koddan)

Retention kararlarından bağımsız, zaten var olan ve düzeltilmesi gereken sorunlar:

| # | Sorun | Etkilenen Sistem | Mevcut Durum | Gerekli Düzeltme |
|---|-------|-----------------|-------------|-----------------|
| **BUG-1** | `compute_trust_scores_task` ClickHouse'dan **90 günlük** veri sorguluyor | `user_events` ClickHouse | TTL **30 gün** → sorgu sadece 30 günü görüyor | R9 ≥ 90 gün VEYA trust_scores sorgusunu 30 güne düşür |
| **BUG-2** | `train_bpr_task` `user_interactions`'tan **120 günlük** veri sorguluyor | `user_interactions` PG | Retention **90 gün** → BPR son 30 günlük veriyi kaybediyor | user_interactions ≥ 120 gün VEYA BPR penceresini 90 güne düşür |
| **BUG-3** | `train_churn_model` ClickHouse'dan **44 günlük** veri sorguluyor | `user_events` ClickHouse | TTL **30 gün** → churn modeli son 14 günlük veriyi kaybediyor | R9 ≥ 44 gün VEYA churn penceresini 30 güne düşür |

> BUG-1, BUG-2, BUG-3 retention kararlarından önce çözülmeli. R9 ve user_interactions retention kararları bu bug'ları da kapatır.

#### 12.0.2 — Retention Kararları Arasındaki Bağımlılıklar

```
R3 (live_streams silme)
    │── CASCADE → gift_events silinir   ← R5 ile çakışır
    │── CASCADE → direct_sales silinir  ← ticaret kaydı
    │── NO ondelete → bids takılır      ← R4 ile ilgili
    └── CASCADE → live_stream_viewers   ← R1 ile ilgili

    Kural: R3 ≥ R5 olmalı (live_streams gift_events'ten önce silinemez)
           VEYA gift_events.stream_id FK → SET NULL yapılmalı (mevcut CASCADE)

R9 (ClickHouse TTL)
    │── trust_scores: 90 gün pencere   ← BUG-1
    │── churn model: 44 gün pencere    ← BUG-3
    │── feed_als: 30 gün pencere       ← R9 = 30 gün, tam sınırda
    │── seller_badges: 30 gün          ← R9 = 30 gün, tam sınırda
    └── compute_user_interests: 30 gün ← R9 = 30 gün, tam sınırda

    Kural: R9 ≥ max(tüm CH sorgu pencereleri) = 90 gün

user_interactions retention
    │── BPR: 120 gün pencere          ← BUG-2
    │── item2vec: 90 gün pencere
    └── compute_user_interests: 30 gün

    Kural: user_interactions ≥ max(tüm PG sorgu pencereleri) = 120 gün

W1 (compute_user_interests frekansı)
    └── W4 (populate_foryou_feed) bağımlı
        Kural: W4 ≤ W1 frekansı (interests güncellenmeden feed yenilemenin anlamı yok)
               W1 = 2x/gün → W4 = 2x-4x/gün mantıklı, saatlik değil

R7 (DM text retention)
    └── R8 (message_threads) bağımlı
        R7 = sonsuz → R8 sorun değil
        R7 = 1 yıl → R8 için GC6 gerekli

W6+W7 (ALS haftalık)
    └── R9 bağımlı: ALS 30 günlük CH verisi kullanıyor
        R9 = 30 gün → ALS haftalık eğitilse bile 30 günlük görünürlük yeterli ✅
```

#### 12.0.3 — Karar Sırası (Bağımlılık Zinciri)

```
1. R9 (ClickHouse TTL) → BUG-1, BUG-3 fix eder → seller_badges, trust_scores, churn düzelir
2. user_interactions retention → BUG-2 fix eder → BPR düzelir
3. R3 (live_streams) → R5 (gift_events) CASCADE bağımlı → birlikte karar ver
4. W1 → W4 birlikte karar ver
5. R7 → R8 birlikte karar ver
6. Diğerleri bağımsız
```

---

### 12.1 — Retention Kararları

#### Grup A: ML Veri Kalitesi (Önce Bunlar — BUG-1/2/3 Bağlantılı)

| # | Tablo | Şu An | Öneri | Endüstri Standardı | Bağımlılık | Karar |
|---|-------|-------|-------|-------------------|-----------|-------|
| **R9** | `user_events` ClickHouse TTL | **30 gün** | **90 gün** | Mixpanel: 90 gün; Amplitude: 12 ay; Google: 14 ay. Davranışsal analitik için 90 gün minimum | BUG-1 (trust 90g), BUG-3 (churn 44g) → R9 < 90g ise bu modeller bozuk | □ 90 gün / □ 60 gün |
| **R9b** | `user_interactions` PG retention | **90 gün** | **120 gün** | Collaborative filtering için 3-6 ay öneri (Netflix, Spotify). BPR 120g pencere açık | BUG-2 → BPR 120g pencere sorguluyor ama sadece 90g görüyor | □ 120 gün / □ 180 gün |
| R9c | `feed_analytics` ClickHouse TTL | **30 gün** | **90 gün** | R9 ile birlikte değiştir (aynı TTL politikası) | R9'a bağımlı | □ R9 ile aynı |
| R9d | `swipe_live_events` ClickHouse TTL | **30 gün** | **90 gün** | R9 ile birlikte | R9'a bağımlı | □ R9 ile aynı |

> **Disk etkisi (node5):** TTL 30→90 gün: ClickHouse ~20 GB/yıl → ~60 GB/yıl. Hâlâ node5 bütçesi içinde.

#### Grup B: Canlı Yayın Verisi (Birlikte Karar Ver)

| # | Tablo | Şu An | Öneri | Endüstri Standardı | Bağımlılık | Karar |
|---|-------|-------|-------|-------------------|-----------|-------|
| **R3** | `live_streams` (biten) | Sonsuz | **1 yıl** | YouTube/Twitch: yayın kaydı sonsuz, ama metadata küçük tablo; Pazar yeri: 1 yıl yeterli | R1, R5 bağımlı. R3 silinince R5 (gift_events) CASCADE silinir — **R3 ≤ R5** olmalı | □ 1 yıl / □ Sonsuz |
| **R1** | `live_stream_viewers` | ⚠️ Sonsuz | **90 gün** | Twitch/YouTube viewer log'ları aggregate; bireysel kayıt 30-90 gün. Host analytics için 90 gün yeterli | R3 CASCADE → stream silinince viewer da silinir | □ 90 gün / □ Stream bitiminde |
| **R5** | `gift_events` | Sonsuz | **Sonsuz** (veya R3 ile CASCADE) | Finansal transfer kaydı → en az 5 yıl (Türk ticaret hukuku). **Öneri: gift_events.stream_id FK'si CASCADE → SET NULL'a çevrilmeli** | R3 CASCADE şu an gift_events'i siliyor — finansal kayıt için tehlikeli | □ SET NULL + sonsuz / □ Sonsuz (R3 = sonsuz ise) |
| **R4** | `bids` | Sonsuz | **2 yıl** | Açık artırma kayıtları: ticaret kanıtı. E-Bay/Amazon: 2 yıl erişilebilir. bids.stream_id FK ondelete YOK (restrict) | R3 silinince bids FK hatası verir — bids.stream_id → SET NULL yapılmalı | □ 2 yıl / □ Sonsuz |

#### Grup C: Mesajlaşma (Birlikte Karar Ver)

| # | Tablo | Şu An | Öneri | Endüstri Standardı | Bağımlılık | Karar |
|---|-------|-------|-------|-------------------|-----------|-------|
| **R7** | `direct_messages` (text) | Sonsuz | □ Karar bekleniyor | WhatsApp/Telegram: sonsuz (kullanıcı siler). iMessage: cihazda sonsuz, sunucuda geçici. Instagram DM: sonsuz. **Pazar yeri standardı: sonsuz** (alışveriş geçmişi önemli) | R8 bağımlı | □ Sonsuz / □ 2 yıl / □ Kullanıcı kontrolü |
| R8 | `message_threads` | Sonsuz | R7'ye bağlı | — | R7 = sonsuz → R8 sorun değil; R7 = sınırlı → GC6 gerekli | □ R7 ile birlikte |

#### Grup D: Ticaret Kayıtları

| # | Tablo | Şu An | Endüstri / Yasal Standart | Karar |
|---|-------|-------|--------------------------|-------|
| R12 | `auctions` | Sonsuz | ✅ **Sonsuz önerilir** — Türk ticaret hukuku: 10 yıl saklama zorunluluğu (TTK 82) | □ Sonsuz ✓ |
| — | `purchases` | Sonsuz | ✅ **Sonsuz / 10 yıl zorunlu** (TTK 82, VUK 253) | □ Sonsuz ✓ |
| — | `tuci_transactions` | Sonsuz | ✅ **Sonsuz / 10 yıl zorunlu** | □ Sonsuz ✓ |
| — | `direct_sales` | Sonsuz | ✅ **Sonsuz önerilir** | □ Sonsuz ✓ |

#### Grup E: Diğer

| # | Tablo | Şu An | Öneri | Endüstri Standardı | Karar |
|---|-------|-------|-------|-------------------|-------|
| R2 | `calls` (ended/missed) | Sonsuz | **1 yıl** | Telekomünikasyon CDR: 1-7 yıl zorunlu (TR: 2 yıl, 5651 Kanunu kapsamında). App çağrısı: 1 yıl yeterli | □ 1 yıl / □ 2 yıl |
| R6 | `listing_offers` (declined) | Sonsuz | **60 gün** | Marketplace teklifleri: 30-90 gün. Müzakere geçmişi kısa süre değerli | □ 60 gün / □ 30 gün |
| R10 | `exchange_rates` | Sonsuz | **2 yıl** | Finansal veri: 7-10 yıl (vergi amaçlı). Uygulama gösterimi için 2 yıl yeterli; uzun geçmiş ayrı arşivde | □ 2 yıl / □ 5 yıl |
| R11 | Hesap silinince DM | Sonsuz | **Anonimleştir** | GDPR/KVKK: "unutulma hakkı" — kullanıcı verisi silinir ama alıcının görmesi için mesaj içeriği kalır. Standart: `sender_id = NULL`, içerik "Silinmiş kullanıcı" | □ Anonimleştir ✓ |

---

### 12.2 — Frekans Kararları

#### Bağımlılık Notu

W1 ↔ W4 birlikte karar verilmeli: feed interests verisi üzerine inşa ediliyor. W1 azaltılırsa W4'ü azaltmak mantıklı.

| # | Görev | Şu An | Öneri | Bağımlılık | Sistem Etkisi | Karar |
|---|-------|-------|-------|-----------|--------------|-------|
| **W1** | `compute_user_interests_task` | Her 15 dk | **2x/gün (08:00, 20:00)** | → W4 azaltılmalı; R9 uzarsa etki artar | ~94 ClickHouse sorgusu/gün tasarrufu; ML kalitesi etkilenmez (ilgi profili günler içinde değişir) | □ 2x/gün / □ 4x/gün |
| **W4** | `populate_foryou_feed_task` | Saatlik | W1'e bağlı: **2x–4x/gün** | W1'e bağımlı — W1 azaltılmadan W4 azaltılmamalı | 18-22 hesaplama/gün tasarrufu | □ W1 ile karar ver |
| W2 | `backfill_listing_embeddings_task` | Her 30dk (gündüz) | **Sadece gece (02:00–04:00)** | Bağımsız. Yeni ilanlar `generate_embedding_task` ile anında işleniyor, backfill sadece eskiler için | sentence-transformers CPU gündüz serbest kalır | □ Onayla / □ Reddet |
| W3 | `compute_user_condition_preferences_task` | Her 15 dk | **4x/gün** | Bağımsız | Condition tercihi saatte değişmez | □ 4x/gün / □ 2x/gün |
| W5 | `compute_trending_listings_task` | Her 30 dk | **4x/gün** | Bağımsız | 30dk TTL zaten var; 6 saatlik yenileme trend için yeterli | □ 4x/gün / □ 6x/gün |
| W6 | `train_feed_als_task` | Günlük | **Haftalık** | R9 bağımlı: ALS 30g CH verisi kullanıyor; TTL 90g'ye çıkarsa haftalık eğitim daha zengin | ADR §3.3 zaten haftalık öneriyor | □ Haftalık / □ Günlük |
| W7 | `train_swipe_live_als_task` | Günlük | **Haftalık** | W6 ile aynı | ADR §3.3 zaten haftalık öneriyor | □ Haftalık / □ Günlük |

---

### 12.3 — Medya Kararları

| # | Konu | Şu An | Öneri | Disk Etkisi | Kullanıcı Etkisi | Karar |
|---|------|-------|-------|------------|-----------------|-------|
| M1 | İlan fotoğrafı formatı | JPEG as-is (max 5 MB) | **WebP q80, max 1920px** | ~%35 küçük (~1.7 MB ort. → ~1.1 MB) | WebP Flutter'da tam destekleniyor; iOS/Android native | □ Evet / □ Hayır |
| M2 | İlan videosu yeniden kodlama | `-c:v copy` (video dokunulmaz) | **CRF 28, 1080p, AAC 96k** | ~%50 küçük (50 MB → ~25 MB ort.) | Sunucu CPU +2-5 sn/video; kalite görsel olarak aynı | □ Evet / □ Hayır |
| M3 | DM medya boyutları | Foto 5MB, Video 30MB | **Foto 3MB, Video 20MB** | ~%35 bandwidth düşer | Kullanıcı sıkıştırmayı client'ta yapıyor zaten | □ Evet / □ Hayır |
| M4 | Profil fotoğrafı | JPEG q85 (5 MB) | **WebP q75, max 800px** | ~%40 küçük | Profil yükleme hızlanır | □ Evet / □ Hayır |
