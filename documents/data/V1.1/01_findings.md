# Teqlif — Veri Yaşam Döngüsü Analizi

**Kapsam:** MinIO · PostgreSQL · ClickHouse · Redis · VoIP · Mail · Backup  
**Hedef:** Her veri parçasının TTL'si, kim yönetiyor, backup lifecycle'ı  
**Kaynak:** Canlı kod analizi + tüm node'lara SSH erişimi  
Son güncelleme: 2026-10-08

---

## İçindekiler

1. [Genel Bakış](#genel-bakış)
2. [MinIO — Nesne Yaşam Döngüsü](#minio--nesne-yaşam-döngüsü)
3. [PostgreSQL — Tablo Bazlı TTL](#postgresql--tablo-bazlı-ttl)
4. [ClickHouse — Analytics TTL](#clickhouse--analytics-ttl)
5. [Redis — Ephemeral Veri](#redis--ephemeral-veri)
6. [VoIP / LiveKit](#voip--livekit)
7. [Mail — Stalwart](#mail--stalwart)
8. [Backup Yaşam Döngüsü](#backup-yaşam-döngüsü)
9. [ARQ Worker vs teqlif-agent Farkları](#arq-worker-vs-teqlif-agent-farkları)
10. [V1.1'de Tespit ve Düzeltilen Sorunlar](#v11de-tespit-ve-düzeltilen-sorunlar)

---

## Genel Bakış

| Veri Katmanı | Yöneten | TTL | Backup |
|-------------|---------|-----|--------|
| MinIO (recordings) | ILM policy | 4 gün (transferred_at sonrası) | node2 mc mirror, 90d |
| MinIO (DM ekleri) | — | Silinmiyor | node2 mc mirror, 90d |
| PostgreSQL | ARQ Worker + teqlif-agent | Tabloya göre 7d–10y | node2 pg_dump, günlük, 90d |
| ClickHouse | Engine TTL | 365 gün | node2 clickhouse-backup, günlük, 90d |
| Redis | TTL parametresi | Key bazlı, çoğu 24h–7d | node2 RDB snapshot, 90d |
| LiveKit | — | Geçici (egress silinir) | Yok (kayıtlar MinIO'ya aktarılır) |
| Stalwart mail | — | Silinmiyor | node2'de yok (config backup nodeMonitor'da) |
| Loki (log) | Engine retention | 30 gün | node2 rsync, 90d (V1.1'de eklendi) |
| Uptime Kuma (DB) | — | Silinmiyor | node2 mysqldump, günlük, 180d (V1.1'de eklendi) |

---

## MinIO — Nesne Yaşam Döngüsü

### Bucket Yapısı

| Bucket | İçerik | ILM | Silinme |
|--------|--------|-----|---------|
| `teqlif` | uploads/ (ilan foto/video), recordings/ | recordings/ → 4 gün expiry | ILM otomatik |
| `teqlif-dm` | DM ekleri (fotoğraf, video, dosya) | **Yok** | Silinmiyor |
| `teqlif-staging` | Staging uploads/recordings | — | — |
| `teqlif-dm-staging` | Staging DM ekleri | — | — |

### Kayıt (Recording) Yaşam Döngüsü

```
[recording]
    ↓ LiveKit egress tamamlanır
[encoding]
    ↓ transcode worker
[encoded]
    ↓ node2'ye aktarım başlar
[transferring]
    ↓ aktarım tamamlanır → transferred_at set
[available]  ←── 24 saat (expires_at = transferred_at + 24h)
    ↓ expire_recordings_task (ARQ, saatlik)
[expired]
    ↓ archive_recordings_task (ARQ, saatlik)
    ↓ koşul: transferred_at < NOW() - 4 days
    ↓ (MinIO ILM bu sürede dosyayı siler)
[archived]   ←── archived_at set
    ↓ ScheduledCleaner 03:00 UTC (teqlif-agent)
    ↓ koşul: archived_at < NOW() - 15 days
[DB'den silindi]
```

**MinIO ILM Kuralı** (`teqlif` bucket, `recordings/` prefix):
- Kural ID: `db0usckkndqcpvdusp30`
- Expiry: 4 gün
- Yönetim: `deploy/scale/V2.1/scripts/setup_minio_ilm.sh` (idempotent)

**DM Ekleri (`teqlif-dm`):**
- ILM politikası yok — eklenti nesneleri silinmiyor
- Mesaj silinse bile (`is_hidden=TRUE AND created_at < 60d`) MinIO nesnesi kalmaya devam ediyor
- Kararlaştırılmış eylem: V2.0+ roadmap'e bırakıldı

---

## PostgreSQL — Tablo Bazlı TTL

### ARQ Worker (`backend/app/worker.py`)

Cron ile çalışan, backend node'larında (node1/3/4) koşan asenkron görevler.

| Tablo | Koşul | TTL | Görev |
|-------|-------|-----|-------|
| `notifications` | `created_at <` | 30 gün | `cleanup_old_notifications_task` |
| `analytics_events` | `created_at <` | 90 gün | `cleanup_old_analytics_task` |
| `user_interactions` | `created_at <` | 365 gün | `cleanup_old_user_interactions_task` |
| `stream_likes` | `created_at <` | 7 gün | `cleanup_old_stream_likes_task` |
| `live_stream_viewers` | `left_at IS NOT NULL AND joined_at <` | 10 yıl (3650d) | `cleanup_old_stream_viewers_task` |
| `listing_offers` (declined/expired) | `created_at <` | 365 gün | `cleanup_old_listing_offers_task` |
| `exchange_rates` | `date <` | 10 yıl (3650d) | `cleanup_old_exchange_rates_task` |
| `live_streams` (ended) | `ended_at <` | 10 yıl (3650d) | `cleanup_old_streams_task` |
| `calls` (ended/missed) | `ended_at <` | 2 yıl (730d) | `cleanup_old_calls_task` |
| `message_threads` (boş) | `created_at <` | 30 gün | `cleanup_empty_message_threads_task` |
| `search_alerts` | `created_at <` | 180 gün | worker içi |
| `direct_messages` (is_hidden) | `created_at <` | 60 gün | worker içi |
| `direct_messages` (medya) | `content_type IN (...) AND created_at <` | 365 gün | worker içi |
| `listing_impressions` | `seen_at <` | 30 gün | worker içi |
| `stream_recordings` | `archived_at <` + `status='archived'` | 15 gün | ScheduledCleaner |

**ÖNEMLİ:** `direct_messages` (normal metin mesajları) hâlâ silinmiyor → V1.0/S1 bulgusu, V2.0'a ertelendi.

### teqlif-agent ScheduledCleaner (`deploy/scale/V2.1/teqlif-agent/modules/cleaner.py`)

Lider node'da UTC zamanına göre çalışan, ARQ'ya paralel ikinci güvenlik katmanı.

| Saat (UTC) | Tablo | Koşul | TTL |
|-----------|-------|-------|-----|
| 00:00 | `notifications` | `created_at < ... AND is_read=true` | 30 gün |
| 00:02 | `stories` | `expires_at < NOW()` | — |
| 00:05 | `analytics_events` | `created_at <` | 90 gün |
| 00:07 | `user_interactions` | `created_at <` | 90 gün |
| 01:00 | `listing_offers` | `updated_at < ... AND status IN (declined,expired)` | 60 gün |
| 01:05 | `calls` | `created_at <` | 90 gün |
| 01:10 | `live_stream_viewers` | `left_at IS NOT NULL AND joined_at <` | 10 yıl (3650d) |
| 02:00 | `exchange_rates` | `fetched_at <` | 365 gün |
| 02:05 | `live_streams` (ended) | `ended_at <` | 180 gün |
| 02:10 | `search_alerts` | `last_match_at <` | 90 gün |
| 02:15 | `message_threads` (boş) | `updated_at < ... AND message_count=0` | 180 gün |
| 02:20 | `listing_impressions` | `seen_at <` | 30 gün |
| 03:00 | `stream_recordings` | `archived_at < ... AND status='archived'` | 15 gün |

---

## ClickHouse — Analytics TTL

Engine seviyesinde tanımlı TTL — uygulama kodu devreye girmez.

| Tablo | TTL | Sütun |
|-------|-----|-------|
| `feed_events` | 365 gün | `timestamp` |
| `search_events` | 365 gün | `timestamp` |
| `user_events` | 365 gün | `timestamp` |
| `listing_hype` | 365 gün | `timestamp` |
| `listing_market` | 365 gün | `timestamp` |

ClickHouse TTL merge'leri arka planda asenkron çalışır; silme garantili olmakla birlikte anlık değildir.

---

## Redis — Ephemeral Veri

Redis'te saklanan veriler ağırlıklı olarak kısa ömürlü. Key bazında TTL:

| Veri Tipi | TTL | Notlar |
|-----------|-----|--------|
| JWT access token | ~1 saat | Blacklist için |
| JWT refresh token | ~30 gün | |
| Email doğrulama kodu | ~10 dakika | |
| Rate limiting | dakika/saat | Sliding window |
| Auction state cache | Stream süresi + buffer | |
| Live stream viewer count | Stream bitince expire | |
| ARQ job queue | Görev süresi | |
| Hype/skor cache | ~24 saat | |
| i18n çeviri cache | Manuel invalidation | `sync_translations.py` temizler |

Redis maxmemory: 4GB, politika: `allkeys-lru` (overflow'da en az kullanılanı atar).

---

## VoIP / LiveKit

| Veri | Yaşam | Notlar |
|------|-------|--------|
| LiveKit oda (room) | Yayın süresi | Yayın bitince oda kapanır |
| Egress (HLS/MP4) | Yayın sonrası MinIO'ya aktarılır | Aktarım bitince egress silinir |
| SFU participant state | Bağlantı süresi | RAM içi, kalıcı değil |
| call_participants DB | 2 yıl (ARQ) / 90 gün (agent) | calls tablosuyla cascade |

---

## Mail — Stalwart

Stalwart mail sunucusu nodeMonitor'da çalışır.

| Veri | TTL | Notlar |
|------|-----|--------|
| Gelen/giden mail | Silinmiyor | Kullanıcı silmedikçe kalıcı |
| SMTP queue | Gönderim sonrası temizlenir | |
| DKIM/config | Kalıcı | nodeMonitor config backup'ında |

---

## Backup Yaşam Döngüsü

Tüm backup'lar node2'de merkezi olarak toplanır.

### node2 Backup Takvimi

| Servis | Script | Saat (UTC) | Retention | Hedef Dizin |
|--------|--------|-----------|-----------|-------------|
| PostgreSQL | `pg_backup.sh` | 02:00 | 90 gün | `/project/teqlif/backups/pg/` |
| MinIO | `minio_backup.sh` | 03:00 | 90 gün | `/project/teqlif/backups/minio/` |
| Redis | `redis_backup.sh` | 04:00 | 90 gün | `/project/teqlif/backups/redis/` |
| ClickHouse | `clickhouse_backup.sh` | 04:30 | 90 gün | `/project/teqlif/backups/clickhouse/` |
| **Loki chunks** | `loki_backup.sh` | **06:00** | **90 gün** | `/project/teqlif/backups/loki/` |
| **Uptime Kuma** | `uptime_kuma_backup.sh` | **06:05** | **180 gün** | `/project/teqlif/backups/uptime_kuma/` |
| **nodeMonitor config** | `nodemonitor_config_backup.sh` | **06:10** | **Kalıcı** | `/project/teqlif/backups/nodemonitor_config/` |

*Kalın: V1.1'de eklendi*

### Backup'ın Amacı

MinIO backup: ILM veya kaza sonrası silinmiş verilerin 90 gün içinde kurtarılması.  
PostgreSQL backup: Veri bozulması, yanlış migration veya silinme durumunda point-in-time recovery.  
Loki backup: nodeMonitor'un 30 günlük yerel retention'ı aşıldıktan sonra 90 gün erişim.  
Uptime Kuma: 180 günlük uptime geçmişi ve alert konfigürasyonu.  
nodeMonitor config: Prometheus/Grafana/Alertmanager konfigürasyonları; node kaybolsa sıfırdan kurulabilir.

### Backup Sağlığı İzleme

teqlif-agent `health.py` her backup için `.last_backup_ok` sentinel dosyasını veya dizin scan'ini kullanır.  
Eşik aşılırsa Telegram alarmı: tüm backup'lar için 25 saatlik uyarı penceresi.

---

## ARQ Worker vs teqlif-agent Farkları

İki sistem aynı tabloları farklı TTL veya koşullarla temizler — çoğu kasıtlı çift güvenlik katmanı, bir kısmı uyumsuzluk.

| Tablo | ARQ Worker | teqlif-agent | Durum |
|-------|-----------|--------------|-------|
| `notifications` | 30d (tümü) | 30d (is_read=true) | Komplementer — agent okunmuşları erken atar |
| `analytics_events` | 90d | 90d | ✅ Uyumlu |
| `user_interactions` | 365d (created_at) | 90d (created_at) | ⚠️ Fark var — agent daha agresif |
| `stream_likes` | 7d | — | ARQ tek yönetici |
| `live_stream_viewers` | 10y (left_at IS NOT NULL) | 10y (left_at IS NOT NULL) | ✅ Düzeltildi (V1.1) |
| `listing_offers` | 365d (created_at) | 60d (updated_at) | ⚠️ Farklı kolon + TTL — agent daha kısa |
| `exchange_rates` | 10y | 365d | Agent daha agresif; 10y ARQ gereksiz uzun |
| `live_streams` | 10y | 180d | Agent daha agresif |
| `calls` | 2y (ended_at) | 90d (created_at) | ⚠️ Farklı kolon + TTL |
| `message_threads` | 30d (boş, created_at) | 180d (boş, updated_at) | Farklı kolon; agent daha uzun |
| `search_alerts` | 180d (created_at) | 90d (last_match_at) | Komplementer — farklı koşullar |
| `listing_impressions` | 30d (seen_at) | 30d (seen_at) | ✅ Düzeltildi (V1.1) |
| `stream_recordings` | — | 15d (archived_at) | teqlif-agent tek yönetici |
| `direct_messages` (hidden) | 60d | — | ARQ tek yönetici |

---

## V1.1'de Tespit ve Düzeltilen Sorunlar

### S1 [DÜZELTILDI] — MinIO ILM Hiç Tanımlanmamıştı

`archive_recordings_task` açıkça "MinIO'nun dosyayı sildiğini kabul eder" diyor ama `mc ilm add` hiç çalıştırılmamıştı. Kayıtlar node1 MinIO'da birikmekteydi.

**Düzeltme:**
- `deploy/scale/V2.1/scripts/setup_minio_ilm.sh` oluşturuldu (idempotent)
- `recordings/` prefix için 4 günlük expiry kuralı tanımlandı
- Kural ID: `db0usckkndqcpvdusp30` (node1'de aktif)

### S2 [DÜZELTILDI] — nodeMonitor Backup'ı Yoktu

Loki log chunk'ları, Uptime Kuma veritabanı ve monitoring stack konfigürasyonu hiç backup'lanmıyordu.

**Düzeltme:**
- `loki_backup.sh`, `uptime_kuma_backup.sh`, `nodemonitor_config_backup.sh` oluşturuldu
- node2'de 3 systemd servis + timer (`06:00`, `06:05`, `06:10 UTC`) tanımlandı ve aktive edildi
- node2 SSH public key nodeMonitor `authorized_keys`'e eklendi
- nodeMonitor'da MySQL `backup` kullanıcısı oluşturuldu (password: `.my-backup.cnf`)
- teqlif-agent `health.py`'a 3 yeni backup monitörü eklendi

### S3 [DÜZELTILDI] — `live_stream_viewers` TTL Uyumsuzluğu

ARQ Worker: 10 yıl (fraud/analytics için uzun tutma)  
teqlif-agent cleaner: 90 gün ← **hatalıydı**

**Düzeltme:** `cleaner.py` 90 gün → 10 yıl (3650 gün), ARQ ile hizalandı.

### S4 [DÜZELTILDI] — `listing_impressions` TTL Uyumsuzluğu

ARQ Worker: `seen_at < 30 gün`  
teqlif-agent cleaner: `created_at < 90 gün` ← **yanlış kolon + yanlış süre**

**Düzeltme:** `cleaner.py` → `seen_at < 30 days`, ARQ ile hizalandı.

---

## Açık Kalan Konular

| # | Konu | Öncelik | Not |
|---|------|---------|-----|
| A1 | `teqlif-dm` bucket ILM yokluğu | Düşük | DM eklerinde kullanıcı tabanlı silme gerekir, V2.0 roadmap |
| A2 | `direct_messages` (normal) silinmiyor | Orta | V1.0/S1 bulgusu; int4 PK + retention birlikte ele alınacak |
| A3 | `user_interactions` ARQ/agent farkı (365d vs 90d) | Düşük | Agent daha agresif; hangisinin doğru olduğuna karar verilmeli |
| A4 | `calls` ARQ/agent farkı (2y ended_at vs 90d created_at) | Düşük | Kolona göre farklı davranış; netleştirilmeli |
| A5 | Stalwart mail backup yok | Düşük | Config backup var; mail kendisi yok |
