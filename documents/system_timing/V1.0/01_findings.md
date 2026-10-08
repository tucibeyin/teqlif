# Sistem Zamanlama Analizi — Bulgular ve Öneriler
**Versiyon:** V1.0  
**Tarih:** 2026-10-03  
**Kapsam:** V2.1 mimarisi, node1–node6, ARQ worker, node2 backup servisleri  
**Hedef:** Tüm zamanlı işleri 03:00–07:30 UTC penceresine yaymak

---

## 1. Envanter: Tüm Zamanlı İşler

### 1.1 node1 — Sürekli Çalışan Servisler (zamanlama yok)

| Servis | Açıklama |
|--------|----------|
| `teqlif.service` | FastAPI app (8000), her zaman açık |
| `teqlif-worker.service` | ARQ worker — tüm batch + cron işleri |
| `teqlif-worker-critical.service` | ARQ worker — kritik öncelikli işler |
| `teqlif-minio.service` | MinIO object storage (9000) |
| `teqlif-redis-core.service` | Redis master (6379) |
| `postgresql.service` | PostgreSQL (5432) |

### 1.2 node1 — ARQ Sürekli İşler (programlanamaz, tasarımı gereği her zaman)

| Sıklık | İş | Kaynak |
|--------|----|--------|
| Her 2 dakika | `cleanup_stale_streams_task` | PG |
| Her 5 dakika | `flush_interactions_to_db` | Redis → PG |
| Her 10 dakika | `sync_ad_campaigns_task` | PG |
| Her 15 dakika | `cleanup_ghost_calls_task` | PG |
| Her 15 dakika | `check_search_alerts_task` | PG |
| Her 15 dakika | `invalidate_swipe_live_configs_task` | Redis |
| Her 20 dakika | `sync_swipelive_interests_task` | Redis |
| Her 1 saat :00 | `cleanup_expired_stories_task` | PG |
| Her 1 saat :00 | `cleanup_hype_highlights_task` | PG |
| Her 1 saat :45 | `backfill_listing_quality_scores_task` | PG |

### 1.3 node1 — ARQ Günlük Batch İşler (MEVCUT saatler, UTC)

| Mevcut Saat | İş | Kaynak | Ağırlık |
|-------------|-----|--------|---------|
| **00:00** | `compute_user_interests_task` | CH + Redis | Orta |
| **00:00** | `compute_trending_categories_task` | CH + PG | Orta |
| **00:10** | `compute_user_condition_preferences_task` | PG + Redis | Hafif |
| **00:20** | `populate_foryou_feed_task` | Redis | Hafif |
| **00:30** | `compute_trending_listings_task` | CH + PG | Orta |
| **01:00** | `cleanup_old_stream_likes_task` | PG | Hafif |
| **01:30** | `compute_seller_badges_task` | PG | Orta |
| **02:00** | `calculate_user_budgets_task` | PG | Orta |
| **02:00** | `backfill_listing_embeddings_task` | PG + MinIO + GPU | Ağır |
| **02:15** | `compute_trust_scores_task` | PG | Orta |
| **02:30** | `cleanup_hidden_messages_task` | PG | Hafif |
| **03:00** | `backfill_listing_embeddings_task` (2. tur) | PG + MinIO | Ağır |
| **03:00** | `cleanup_old_notifications_task` | PG | Hafif |
| **03:30** | `process_churn_and_airdrop` | CH + PG + FCM | Orta |
| **04:00** | `optimize_notification_timing_task` | CH + Redis | Orta |
| **04:00** | `deactivate_expired_listings_task` | PG | Hafif |
| **04:30** | `delete_expired_inactive_listings_task` | PG + MinIO | Orta |
| **05:00** | `cleanup_old_impressions_task` | PG | Hafif |
| **05:15** | `nsfw_backfill_task` | PG + AI-proxy | Ağır |
| **05:30** | `backfill_phash_task` | PG + MinIO | Ağır |
| **06:00** | `hesitation_retarget_task` | CH + PG | Orta |
| **06:30** | `cleanup_old_media_messages_task` | PG | Hafif |
| **00:00/12:00** | `rebuild_faiss_index_task` | PG + bellek (2× günlük) | Ağır |
| **06:00/12:00/18:00** | (yukardakiler 3 kez daha) | CH + PG + Redis | Orta |

### 1.4 node1 — ARQ Haftalık Batch İşler (MEVCUT saatler, UTC)

| Mevcut Saat | Gün | İş | Kaynak | Ağırlık |
|-------------|-----|----|--------|---------|
| **00:30** | Pzt/Çar/Cum | `train_bpr_task` | PG + bellek | **Çok Ağır** |
| **01:00** | Pazar | `train_swipe_live_als_task` | PG + CH + bellek | **Çok Ağır** |
| **01:30** | Pazar | `train_feed_als_task` | PG + CH + bellek | **Çok Ağır** |
| **02:00** | Pazar | `train_item2vec_task` | PG + bellek | **Çok Ağır** |
| **02:15** | Çar/Paz | `train_kmeans_cold_start_task` | PG + bellek | Ağır |
| **02:30** | Pazar | `train_listing_quality_model_task` | PG + CH + bellek | **Çok Ağır** |
| **02:30** | Pazartesi | `train_churn_model_task` | CH + PG + bellek | Ağır |
| **04:00** | Pazartesi | `cleanup_old_analytics_task` | CH (büyük silme) | Ağır |
| **04:00** | Salı | `cleanup_old_user_interactions_task` | PG | Hafif |
| **04:00** | Cuma | `cleanup_old_calls_task` | PG | Hafif |
| **04:00** | Cumartesi | `cleanup_old_listing_offers_task` | PG | Hafif |
| **04:00** | Perşembe | `cleanup_old_stream_viewers_task` | PG | Hafif |
| **05:00** | Pazar | `cleanup_empty_message_threads_task` | PG | Hafif |
| **05:30** | Pazar | `compute_influence_scores_task` | PG (PageRank) | Ağır |
| **06:00** | Pazar | `cleanup_inactive_search_alerts_task` | PG | Hafif |

### 1.5 node1 — ARQ Aylık İşler

| Mevcut Saat | Koşul | İş | Kaynak |
|-------------|-------|-----|--------|
| **05:00** | Ayın 1'i | `cleanup_old_exchange_rates_task` | PG | 
| **06:00** | Ayın 1'i | `cleanup_old_streams_task` | PG + MinIO |

### 1.6 node2 — Backup Timer'ları (MEVCUT saatler, UTC)

| Saat | Timer | Script | Kaynak / I/O |
|------|-------|--------|--------------|
| **01:00** | `teqlif-pg-dump.timer` | `pg_dump.sh` | node1 PG → WireGuard → **node2 HDD yazma** |
| **01:30** | `teqlif-clickhouse-backup.timer` | `clickhouse_backup.sh` | node2 CH → **node2 HDD yazma** (yerel) |
| **02:00** | `teqlif-redis-backup.timer` | `redis_backup.sh` | node2 Redis replica BGSAVE → **node2 HDD yazma** |
| **02:30** | `teqlif-mail-backup.timer` | `mail_backup.sh` | Stalwart → **node2 HDD yazma** |
| **03:00** | `teqlif-minio-backup.timer` | `minio_backup.sh` | node1 MinIO → WireGuard → **node2 HDD yazma** |
| ~~04:00~~ | `teqlif-offsite-sync.timer` | `offsite_sync.sh` | **DISABLED** — ofsite hedef yapılandırılmamış, timer çalışmıyor |

**NOT — Offsite sync durumu:**
Timer dosyası (`teqlif-offsite-sync.timer`) node2'de mevcut ama `disabled` + `inactive` durumda.
`rclone config` boş — ofsite hedef hiç yapılandırılmamış. Script içeriği temizlendi.
Ofsite hedef belirlendiğinde `offsite_sync.sh` güncellenip timer enable edilecek.

### 1.7 node2 — Sürekli Çalışan Servisler

| Servis | Durum | Açıklama |
|--------|-------|----------|
| `clickhouse-server.service` | **active (24/7)** | CH her zaman açık — "sadece geceleri" demek CH sorgulayan ARQ jobları içindi |
| `teqlif-redis-replica.service` | active | node1 Redis'in read replica'sı |
| `stalwart-mail.service` | active | Mail sunucusu |
| `postgresql.service` | active | node1 PG standby (hot-standby, read-only) |
| `teqlif-pg-receivewal.service` | **inactive** ⚠️ | WAL streaming servisi var ama çalışmıyor — RPO = son pg_dump |

### 1.8 node3 / node4 — LiveKit Sunucuları

Teqlif-specific timer yok. Sadece OS sistem timer'ları (certbot, dpkg, logrotate, apt).

### 1.9 node6 — AI Proxy

Teqlif-specific timer yok. Sadece OS sistem timer'ları.

---

## 2. Kritik Bulgular

### Bulgu 0: `train_bpr_task` weekday BUG — mevcut `worker.py`'da da var ⚠️🐛

`worker.py` satır 3807: `cron(train_bpr_task, weekday={0, 2, 5}, hour=0, minute=30)`

Python `datetime.weekday()`: 0=Pazartesi, 2=Çarşamba, **5=Cumartesi**. "Pzt/Çar/Cum" isteniyorsa `{0, 2, **4**}` olmalı.
Bu hata hem mevcut `worker.py`'da hem de §5.2 kod bloğunda vardı — ikisi birlikte düzeltildi.

### Bulgu 1: Mevcut çakışmalar

| Çakışma | Etki |
|---------|------|
| **01:00** pg_dump + cleanup_old_stream_likes → aynı anda node1 PG'ye yazma+okuma | Düşük etki, PG eşzamanlılık sorun değil, ama gereksiz yük |
| **01:30** CH_backup + compute_seller_badges → CH backup yazarken ARQ CH'dan okuma | ClickHouse backup snapshot alır, sorguları bloklamaz — teknik sorun yok ama disk I/O çakışması |
| **02:00** calculate_user_budgets + backfill_listing_embeddings → aynı anda başlama | Worker concurrency kullanılıyor, sorun yok ama peak CPU |
| **02:30** train_churn_model + cleanup_hidden_messages → aynı anda | Worker slot paylaşımı |
| **Paz 01:00–02:30** ALS+item2vec+kmeans+quality_model → aynı anda çalışanlar | CPU-bound training'ler node1 12-core'u doldurabilir |
| **00:30** train_bpr (Pzt/Çar/Cum) → kullanıcılar hala aktif olabilir | Gece geç saatte CPU spike |

### Bulgu 2: `_FORYOU_TTL = 21600` (6 saat) — KOD DEĞİŞİKLİĞİ GEREKTİRİR

`foryou_worker.py` satır 8:
```python
_FORYOU_TTL = 21600  # 6 saat — 4x/gün cron ile yenilenir
```
Eğer günde 1× yenilemeye geçersek, bu TTL **86400 (24 saat)** yapılmalı, aksi halde kullanıcılar 10:00'dan itibaren boş "Sana Özel" feed alır.

### Bulgu 3: `teqlif-pg-receivewal.service` inactive ⚠️

WAL streaming servisi dosya olarak var ama inactive. Mevcut durum:
- PG RPO = son `pg_dump` saati (gece 01:00 → ~24 saat RPO)
- Bir şey ters giderse son pg_dump'a kadar geri dönülür
- Bu bilinçli bir tercihse sorun değil, ama bir bulgu olarak kayıt altına alınmalı

### Bulgu 4: Offsite sync timer mevcut ama devre dışı ⚠️

`teqlif-offsite-sync.timer` node2'de `disabled` + `inactive` durumda. `rclone config` boş.
Ofsite yedek **şu an aktif değil** — script taslak olarak bırakılmış, hiç çalıştırılmamış.
Önerilen zamanlamaya dahil edilmedi. Ofsite hedef kararlaştırıldığında ayrıca planlanacak.

### Bulgu 5: ClickHouse 24/7 çalışıyor

`systemctl is-active clickhouse-server` → **active**. "Geceleri çalışıyor" demek CH servisinin değil, CH'a yazan/okuyan ARQ joblarının gece çalıştığı anlamındaydı.

---

## 3. Kaynak Modeli

```
node1 (12 core, 32GB, NVMe SSD)
  ├── CPU: ML training (ALS, BPR, item2vec, kmeans) → ağır
  ├── CPU: backfill görevleri (nsfw, phash, embeddings) → ağır
  ├── RAM: FAISS index rebuild → ağır (embedding boyutuna göre)
  ├── PG: okuma ağır saatlerde (pg_dump + ARQ aynı anda)
  └── Network: node2 CH'a sorgu, MinIO'ya erişim

node2 (8 core, 32GB, HDD RAID-1)
  ├── HDD: seri yazma (pg_dump → CH_backup → redis → mail → minio) → HDD'de eşzamanlı yazma YASAK
  ├── HDD: rclone okuma (offsite sync) → yazma bitmeden başlamamalı
  ├── CH: sorgu yanıt süreleri HDD nedeniyle SSD'den yavaş
  └── Network: node1'den gelen backup trafiği (WireGuard)

node3/4 (6 core, 11GB, SSD 88GB boş)
  ├── Network: LiveKit SFU — gün boyunca yayın trafiği
  ├── SSD: kayıt dosyaları birikimi (gündüz)
  └── CPU: ffmpeg encode (gece boşta)
```

---

## 4. Önerilen Yeni Zaman Çizelgesi (03:00–07:30 UTC)

### Tasarım İlkeleri

1. **node2 HDD yazma operasyonları kesinlikle seri** — eşzamanlı iki backup = random I/O = yavaş
2. **CH backup bitene kadar CH-bağımlı ML işleri başlamaz** (gereksiz I/O çakışmasını önler)
3. **pg_dump bitene kadar ağır PG batch işleri başlamaz**
4. **MinIO backup ile offsite sync aynı anda olmaz** (birini okurken diğeri yazıyor)
5. **CPU-ağır training işleri tek seferde serbestçe paralel koşabilir** (node1 12 core)
6. **Haftalık training işleri** için Pazar geceleri ekstra 30-60 dk pay
7. **Kayıt rsync'i (node3/4 → node2)** offsite sync başlamadan bitmeli (05:15)

### Önerilen Çizelge

```
SAAT    NODE     İŞ                                    KAYNAK        NOT
────────────────────────────────────────────────────────────────────────────────────
03:00   node2    pg_dump BAŞLAR                        HDD yazma     WireGuard, ~15dk
03:00   node1    cleanup_old_notifications             PG hafif      paralel OK
03:00   node1    cleanup_old_stream_likes              PG hafif      paralel OK
        
03:20   node2    pg_dump BİTER (tahmini)
03:20   node2    clickhouse_backup BAŞLAR              HDD yazma     local, ~20dk
03:20   node1    compute_seller_badges                 PG            pg_dump bitti
03:20   node1    calculate_user_budgets                PG            pg_dump bitti
03:20   node1    compute_trust_scores                  PG            pg_dump bitti
03:25   node1    cleanup_hidden_messages               PG hafif

03:40   node2    clickhouse_backup BİTER (tahmini)
03:40   node2    redis_backup BAŞLAR                   HDD yazma     BGSAVE, ~5dk
03:40   node1    compute_user_interests                CH+Redis      CH backup bitti!
03:40   node1    compute_trending_categories           CH+PG         CH backup bitti!
03:50   node1    compute_user_condition_preferences    PG+Redis
03:55   node1    populate_foryou_feed                  Redis only    hızlı

03:45   node2    redis_backup BİTER (tahmini)
03:45   node2    mail_backup BAŞLAR                    HDD yazma     ~10dk

04:00   node2    mail_backup BİTER (tahmini)
04:00   node2    minio_backup BAŞLAR (mc mirror)       HDD yazma     WireGuard+HDD, ~30-45dk
04:00   node1    compute_trending_listings             CH+PG         CH backup çoktan bitti
04:00   node1    process_churn_and_airdrop             CH+PG+FCM
04:10   node1    optimize_notification_timing          CH+Redis
04:15   node1    deactivate_expired_listings           PG
04:20   node1    delete_expired_inactive_listings      PG+MinIO
04:30   node1    cleanup_old_impressions               PG
04:30   node1    rebuild_faiss_index                   PG+bellek     CPU ağır, ~20dk

04:45   node2    minio_backup BİTER (tahmini, DB küçük)
05:00   node1    nsfw_backfill                         PG+AI-proxy   CPU ağır
05:00   node1    backfill_phash                        PG+MinIO      ağır
05:00   node1    backfill_listing_embeddings           PG+MinIO+GPU  ağır
05:00   node1    hesitation_retarget                   CH+PG
05:10   node1    cleanup_old_media_messages            PG

── Haftalık günlük cleanup (her biri kendi gününde) ──
05:00   node1    cleanup_old_user_interactions (Sal)   PG
05:00   node1    cleanup_old_calls (Cum)               PG          ← weekday=4
05:00   node1    cleanup_old_listing_offers (Cmt)      PG          ← weekday=5
05:00   node1    cleanup_old_stream_viewers (Per)      PG          ← weekday=3
05:00   node1    cleanup_old_analytics (Pzt)           CH büyük silme
05:15   node1    cleanup_empty_message_threads (Paz)   PG          ← weekday=6
05:20   node1    cleanup_inactive_search_alerts (Paz)  PG          ← weekday=6

── Kayıt sistemi (yeni, node3/4 → node2) ──────────────
05:15   node3    rsync encoded/ → node2:/project/teqlif/recordings/   node2 HDD yazma
05:15   node4    rsync encoded/ → node2:/project/teqlif/recordings/   minio bitti, slot hazır
05:30   node2    recording retention cleanup (15-gün)  HDD silme     küçük iş

── Offsite sync — tüm backuplar + kayıtlar tamamdır ──
── (ofsite yedek yapılandırılmadı, bu slot boş) ────

── Haftalık ML training — 05:15 başlangıç (timezone-safe, §7.4) ──
05:15   node1    train_bpr (Pzt/Çar/Cum)              PG+bellek     ~45dk → 06:00'da biter
05:15   node1    Pazar: train_swipe_live_als           PG+CH+bellek  ~60dk
05:30   node1    Pazar: train_item2vec                 PG+bellek     ~30dk
05:45   node1    Pazar: train_kmeans_cold_start        PG+bellek     ~20dk (Çar de 05:45)
05:45   node1    Pzt: train_churn_model                CH+PG+bellek  ~30dk  ← CH delete bittikten sonra (§7.5)
06:00   node1    Pazar: train_feed_als                 PG+CH+bellek  ~60dk
06:30   node1    Pazar: train_listing_quality_model    PG+CH+bellek  ~30dk
06:30   node1    Pazar: compute_influence_scores       PG PageRank   ~20dk  ← Pazar 06:30'da biter

── Aylık işler (ayın 1'i) ─────────────────────────────
06:00   node1    cleanup_old_exchange_rates            PG
06:15   node1    cleanup_old_streams                   PG+MinIO

────────────────────────────────────────────────────────────────────────────────
07:30   TÜM İŞLER TAMAM (Pazar hariç, Pazar ~08:00)
08:00   Kullanıcılar gelmeye başlar — sistem taze, tüm cacheler dolu
```

---

## 5. Gerekli Kod Değişiklikleri

### 5.1 `foryou_worker.py` — TTL ve frekans kararı

**Tasarım kararı:** populate_foryou_feed **2× günlük** (03:55 + 15:55) olarak planlandı.
- 03:55: user_interests hesaplandıktan hemen sonra, taze ilgi vektörleriyle
- 15:55: öğleden sonra refresh — sabah interestleri + günün yeni ilanları
- Bu iş **sadece Redis okur**, CH gerektirmez → gündüz çalışması sorunsuz

```python
# MEVCUT:
_FORYOU_TTL = 21600   # 6 saat — 4× günlük için doğruydu

# YENİ (2× günlük için): en az 12h gap kapanmalı, 24h safety margin verir
_FORYOU_TTL = 86400   # 24 saat — key zaten her 12h overwrite edilir
```

Maksimum bayatlık: 15:55'te populate → ertesi 03:55'e kadar = ~12 saat (gece saatleri, düşük aktivite).

### 5.2 `worker.py` — cron_jobs listesi (tüm yeni saatler)

```python
cron_jobs = [
    # ── Sürekli işler (değişmez) ────────────────────────────────────
    cron(cleanup_stale_streams_task,          minute=set(range(0, 60, 2))),
    cron(flush_interactions_to_db,            minute={0,5,10,15,20,25,30,35,40,45,50,55}),
    cron(sync_ad_campaigns_task,              minute={0,10,20,30,40,50}),
    cron(cleanup_ghost_calls_task,            minute={0,15,30,45}),
    cron(check_search_alerts_task,            minute={0,15,30,45}),
    cron(invalidate_swipe_live_configs_task,  minute={5,20,35,50}),
    cron(sync_swipelive_interests_task,       minute={0,20,40}),
    cron(cleanup_expired_stories_task,        minute=0),
    cron(cleanup_hype_highlights_task,        minute=0),
    cron(backfill_listing_quality_scores_task, minute=45),

    # ── Günlük batch — 03:00-05:30 penceresi ────────────────────────
    cron(cleanup_old_notifications_task,      hour=3,  minute=0),
    cron(cleanup_old_stream_likes_task,       hour=3,  minute=0),
    cron(compute_seller_badges_task,          hour=3,  minute=20),
    cron(calculate_user_budgets_task,         hour=3,  minute=20),
    cron(compute_trust_scores_task,           hour=3,  minute=20),
    cron(cleanup_hidden_messages_task,        hour=3,  minute=25),
    cron(compute_user_interests_task,         hour=3,  minute=40),
    cron(compute_trending_categories_task,    hour=3,  minute=40),
    cron(compute_user_condition_preferences_task, hour=3, minute=50),
    cron(populate_foryou_feed_task,           hour={3, 15}, minute=55),   # 2× günlük: 03:55 + 15:55
    cron(compute_trending_listings_task,      hour=4,  minute=0),
    cron(process_churn_and_airdrop,           hour=4,  minute=0),
    cron(optimize_notification_timing_task,   hour=4,  minute=10),
    cron(deactivate_expired_listings_task,    hour=4,  minute=15),
    cron(delete_expired_inactive_listings_task, hour=4, minute=20),
    cron(cleanup_old_impressions_task,        hour=4,  minute=30),
    cron(rebuild_faiss_index_task,            hour=4,  minute=30),
    cron(nsfw_backfill_task,                  hour=5,  minute=0),
    cron(backfill_phash_task,                 hour=5,  minute=0),
    cron(backfill_listing_embeddings_task,    hour=5,  minute=0),
    cron(hesitation_retarget_task,            hour=5,  minute=0),
    cron(cleanup_old_media_messages_task,     hour=5,  minute=10),

    # ── Haftalık günlük cleanup (her biri kendi gününde) ────────────
    cron(cleanup_old_analytics_task,          weekday=0, hour=5, minute=0),
    cron(cleanup_old_user_interactions_task,  weekday=1, hour=5, minute=0),
    cron(cleanup_old_stream_viewers_task,     weekday=3, hour=5, minute=0),
    cron(cleanup_old_calls_task,              weekday=4, hour=5, minute=0),
    cron(cleanup_old_listing_offers_task,     weekday=5, hour=5, minute=0),
    cron(cleanup_empty_message_threads_task,  weekday=6, hour=5, minute=15),
    cron(cleanup_inactive_search_alerts_task, weekday=6, hour=5, minute=20),
    cron(compute_influence_scores_task,       weekday=6, hour=6, minute=30),

    # ── Aylık işler ──────────────────────────────────────────────────
    cron(cleanup_old_exchange_rates_task,     day=1, hour=6, minute=0),
    cron(cleanup_old_streams_task,            day=1, hour=6, minute=15),

    # ── Haftalık ML training — 05:15 başlangıç (timezone-safe, §7.4) ──
    cron(train_bpr_task,                      weekday={0,2,4}, hour=5, minute=15),  # 0=Pzt 2=Çar 4=Cum
    cron(train_swipe_live_als_task,           weekday=6, hour=5, minute=15),
    cron(train_item2vec_task,                 weekday=6, hour=5, minute=30),
    cron(train_kmeans_cold_start_task,        weekday={2,6}, hour=5, minute=45),
    cron(train_feed_als_task,                 weekday=6, hour=6, minute=0),
    cron(train_listing_quality_model_task,    weekday=6, hour=6, minute=30),
    cron(train_churn_model_task,              weekday=0, hour=5, minute=45),  # Pzt: CH delete bittikten sonra (§7.5)
]
```

### 5.3 node2 — Backup timer'ları (systemd OnCalendar değişiklikleri)

```ini
# teqlif-pg-dump.timer
OnCalendar=*-*-* 03:00:00    # 01:00 → 03:00

# teqlif-clickhouse-backup.timer
OnCalendar=*-*-* 03:20:00    # 01:30 → 03:20

# teqlif-redis-backup.timer
OnCalendar=*-*-* 03:40:00    # 02:00 → 03:40

# teqlif-mail-backup.timer
OnCalendar=*-*-* 03:45:00    # 02:30 → 03:45

# teqlif-minio-backup.timer
OnCalendar=*-*-* 04:00:00    # 03:00 → 04:00

# teqlif-offsite-sync.timer — DISABLED, ofsite hedef yapılandırılmamış, değiştirilmedi
```

### 5.4 Yeni timer'lar (kayıt sistemi — henüz kurulmadı)

```ini
# node3: teqlif-recording-encode.timer (ffmpeg post-process)
OnCalendar=*-*-* 23:30:00

# node3/4: teqlif-recording-rsync.timer
OnCalendar=*-*-* 05:15:00

# node2: teqlif-recording-retention.timer (15-gün silme)
OnCalendar=*-*-* 05:30:00
```

---

## 6. Özet Karşılaştırma

| | Mevcut | Önerilen |
|---|---|---|
| En erken batch iş | 00:00 (kullanıcılar aktifken) | 03:00 |
| En geç iş | 06:30 | 07:00 (Paz) / 07:30 (kapasite) |
| node2 HDD çakışması | Var (örtüşen yazma işleri) | Yok (seri sıralama) |
| ClickHouse bağımlı iş sayısı | 4× günlük = gereksiz CH yükü | 1× günlük |
| `_FORYOU_TTL` | 21600s (6h) — 4× için doğruydu | 86400s (24h) — 2× günlük (03:55 + 15:55) |
| FAISS index rebuild | 2× günlük (00:00 + 12:00) | **1× günlük** (04:30) — marketplace için yeterli |
| `train_bpr_task` weekday | `{0,2,5}` = Pzt/Çar/**Cmt** ← BUG | `{0,2,4}` = Pzt/Çar/Cum — düzeltildi |
| offsite sync | Devre dışı (timer disabled, hedef yok) | Devre dışı — ofsite hedef belirlenince planlanır |
| Haftalık training başlama | 00:30–02:30 (gece geç, kullanıcılar aktifken) | 05:15–06:45 UTC = 08:15–09:45 Türkiye |
| Kayıt sistemi | Yok | 23:30 encode → 05:15 rsync → node2 |

---

## 7. Mimari Değerlendirme Notları

### 7.1 node2 HDD Sequential I/O — Neden Önemli

HDD kafası eşzamanlı iki yazma isteği alırsa farklı sektörler arasında gidip gelir (random I/O) ve hız 10-20 MB/s'ye düşebilir. Backup'ları 03:00→03:20→03:40→03:45→04:00 şeklinde sıralamak HDD'nin sequential write kapasitesini (~150 MB/s) tam kullanmasını sağlar. Bu bir "hardware-aware" tasarım kararıdır.

### 7.2 CPU / Network Ayrıştırması

03:00–04:45 arası: node2 WireGuard + HDD yoğun (yedekler) → node1 CPU kasıtlı boş, sadece hafif cleanup  
05:00 sonrası: yedekler bitti → node1 CPU ağır işlere (AI backfill, embedding, FAISS) giriyor  
Bu sıralama ağ ve CPU'nun aynı anda boğulmasını önler.

### 7.3 15:55 UTC ForYou Refresh — Neden Bu Saat Optimal

15:55 UTC = **18:55 Türkiye (UTC+3)**.  
Prime time aralığı: 20:00–23:00 Türkiye = 17:00–20:00 UTC.  
Refresh, prime time başlamadan ~1 saat önce tamamlanır. Yoğun saatlerde sistem sadece Redis'ten okur — sıfır ML hesabı. Prime time öncesi hazırlık penceresi olarak bilinçli seçilmeli.

### 7.4 ML Training Timezone Riski — Gerçek Ama Günlük Değil

Reviewer tespiti: 06:00–07:00 UTC = **09:00–10:00 Türkiye** → sabah commute peak.  
CPU-bound training bu saatte çalışırsa FastAPI latency 1-2 sn'ye çıkabilir.

**Ancak bu risk her gün geçerli değil:**

| Gün | 06:00 UTC'de çalışan training |
|-----|-------------------------------|
| Pazartesi | `train_bpr` (~45dk) |
| Salı | — (temiz) |
| Çarşamba | `train_bpr` + `train_kmeans` |
| Perşembe | — (temiz) |
| Cuma | `train_bpr` (~45dk) |
| Cumartesi | — (temiz) |
| Pazar | `train_swipe_live_als` + `train_feed_als` + `train_item2vec` + `train_kmeans` + `train_listing_quality` → **en ağır gün** |

**Şu an için çözüm:** Training bloğunu **05:15'e çek**. Pazar'daki en uzun işler ~60-90dk → 07:00-07:45'te biter, sabah trafiği (08:00 Türkiye = 05:00 UTC) gelmeden önce bitmiş olur. Bunu §5.2'deki tüm training saatlerine uygula.

**İzleme:** Sistem büyüdüğünde Prometheus'ta `api_request_duration_seconds` p99'u 06:00-08:00 UTC aralığında izle. Spike görülürse training worker'larına `OMP_NUM_THREADS` veya `torch.set_num_threads()` ile CPU limiti eklemek yeterli — mimari değişiklik gerekmez.

### 7.5 Pazartesi CH Delete + train_churn Çakışması

Pazartesi 05:00 UTC: `cleanup_old_analytics_task` → ClickHouse'da büyük DELETE  
Pazartesi 07:00 UTC: `train_churn_model` → CH okuma  

CH HDD'de çalışıyor, büyük delete sonrası compaction başlayabilir. Bu iki iş arasında en az **10 dakika boşluk** bırakılmalı. Mevcut çizelgede zaten 05:00 → 07:00 = 2 saat var, sorun yok. Ama training saati 05:15'e çekilirse Pazartesi `train_churn` 05:15 + ~30dk = 05:45'te biter — CH delete ile örtüşmez (delete 05:00-05:30, churn 05:15-05:45 → **çakışabilir**). Bu durumda Pazartesi `train_churn` saatini 05:45'e almak gerekir.

**Sonuç:**  
Plan V2.1 aşamasında uygulanabilir. §5.2'deki training saatlerini 05:15'e çekmek ve Pazartesi `train_churn`'ü 05:45'e almak yeterli.

---

## 8. teqlif-agent'in Zamanlama Planındaki Rolü

### 8.1 Agent Şu An Ne Yapıyor (zamanlama açısından)

| Modül | Mevcut katkı |
|-------|-------------|
| `watchdog.py` | ARQ cron job'larının `teqlif:agent:job_ok` sinyallerini okur, beklenen interval'den %50 geç gelirse Telegram uyarısı. Sadece lider (nodeMonitor) değerlendirir, tüm node'lar Redis sync yapar. |
| `janitor.py` | Her 60 saniyede lider tarafından çalışır. TTL politikalarını değerlendirir. Kayıt pipeline'ı için encode + transfer trigger mekanizması **zaten yazılmış**. |
| `healer.py` | Servislerin `failed` durumuna düşmesinde otomatik `reset-failed` + `start`. Batch iş penceresinde servisler çalışır halde tutar. |
| `certs.py` | TLS sertifika expiry. Zamanlama planıyla doğrudan ilişkisi yok. |

### 8.2 Kritik Gap 1: `_JOB_REGISTRY` Interval'ları Güncellenmeli

`watchdog.py` içindeki beklenen interval değerleri hâlâ eski 4× günlük çizelgeye göre. Yeni plana göre güncellenmesi zorunlu, aksi halde watchdog ya sürekli yanlış alarm verir ya da stale işi kaçırır.

| Job | Mevcut interval | Yeni interval | Neden |
|-----|----------------|---------------|-------|
| `compute_user_interests_task` | `6*60` (360dk) | `24*60` (1440dk) | 1× günlük |
| `compute_trending_categories_task` | kayıtlı değil | `24*60` | 1× günlük, eksik |
| `compute_trending_listings_task` | `6*60` | `24*60` | 1× günlük |
| `populate_foryou_feed_task` | `6*60` | `12*60` | 2× günlük, max gap 12h |
| `rebuild_faiss_index_task` | `12*60` | `24*60` | 1× günlük |

**Değiştirilecek dosya:** `deploy/scale/V2.1/teqlif-agent/modules/watchdog.py` → `_JOB_REGISTRY`

### 8.3 Kritik Gap 2: Backup Script'leri Agent'a Kör

`pg_dump`, `clickhouse_backup`, `redis_backup`, `mail_backup`, `minio_backup` script'lerinin hiçbiri `teqlif:agent:job_ok` sinyali göndermiyor. Agent bu job'ların başarıyla tamamlanıp tamamlanmadığını bilmiyor.

**Çözüm: Her backup script'inin sonuna Redis HSET ekle:**

```bash
# Her backup script'inin başarılı tamamlanma satırından sonra:
redis-cli -u "${REDIS_URL}" HSET teqlif:agent:job_ok \
  "backup_pg_dump" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > /dev/null 2>&1 || true
```

**`_JOB_REGISTRY`'e eklenecek backup job'ları:**

```python
# Backup izleme (günlük, max 25h tolerans)
"backup_pg_dump":          25 * 60,
"backup_clickhouse":       25 * 60,
"backup_redis":            25 * 60,
"backup_mail":             25 * 60,
"backup_minio":            25 * 60,
```

Lider (nodeMonitor) gece 07:00'dan sonra bu kayıtları kontrol eder — her birinin son 25 saat içinde tamamlandığını doğrular, yoksa Telegram alarmı.

### 8.4 Janitor Kayıt Pipeline'ını Zaten Koordine Ediyor

`janitor.py` içinde **kayıt sistemi için event-driven mekanizma zaten mevcut:**

```python
# Mevcut policy'ler (janitor.py):
"stream_recording_encode_queue"   → aktif yayın yoksa Redis pubsub "teqlif:agent:encode_trigger"
"stream_recording_transfer_queue" → /var/recordings/encoded/ altında dosya varsa "teqlif:agent:transfer_trigger"
```

**Timer-tabanlı vs. event-driven karşılaştırması:**

| Yaklaşım | Avantaj | Dezavantaj |
|----------|---------|------------|
| Systemd timer (23:30 encode, 05:15 rsync) | Basit, öngörülebilir, bakım penceresiyle uyumlu | Kısa yayınlar 23:30'a kadar bekler |
| Janitor event-driven (aktif yayın yoksa trigger) | Yayın biter bitmez encode başlar, esnek | Transfer tetiklenme saatini kontrol etmek gerekir — gündüz transfer istemiyoruz |

**Önerilen hibrit yaklaşım:**
- **Encode:** Janitor event-driven bırakılır — yayın biter bitmez encode başlayabilir (node3/4 boşta zaten)
- **Transfer (rsync to node2):** Janitor trigger yayınlar ama script transfer saatini kontrol eder:

```bash
# teqlif-recording-rsync.sh başına eklenecek saat kontrolü:
HOUR=$(date -u +%H)
if [ "$HOUR" -lt 3 ] || [ "$HOUR" -gt 6 ]; then
  echo "Transfer penceresi dışı (UTC $(date -u +%H:%M)), erteleniyor."
  exit 0
fi
```

Bu sayede janitor "hazır dosya var" sinyali gönderir, ama transfer script'i bunu yalnızca 03:00-07:00 UTC penceresinde execute eder.

### 8.5 Agent Güncelleme Özeti

| # | Değişiklik | Dosya | Öncelik |
|---|-----------|-------|---------|
| 1 | `_JOB_REGISTRY` interval güncelleme | `modules/watchdog.py` | **Zorunlu** — yeni çizelge uygulanmadan önce |
| 2 | Backup script'lerine `job_ok` sinyali ekleme | `node2/resources/scripts/*.sh` | **Zorunlu** — backup izleme için |
| 3 | Transfer script'ine saat penceresi kontrolü | `node3/4 rsync script` | Önerilen |
| 4 | Janitor encode trigger'ını aktif yayın bitişine bağlı bırak | `modules/janitor.py` | Mevcut haliyle iyi |

---

## 9. Uygulama Sırası

1. `watchdog.py` → `_JOB_REGISTRY` interval güncellemesi (§8.2) — **önce bu, yeni çizelge devreye girmeden**
2. `foryou_worker.py` → `_FORYOU_TTL = 86400`
3. `worker.py` → `cron_jobs` listesi (§5.2)
4. node2 backup script'leri → `job_ok` Redis sinyali ekleme (§8.3)
5. node2 timer dosyaları → yeni `OnCalendar` değerleri (§5.3)
6. `sudo teqlif-restart` tüm node'larda + `sudo systemctl daemon-reload` node2'de
7. Kayıt sistemi: livekit-egress kurulumu + transfer script saat penceresi (§8.4) → ayrı görev
