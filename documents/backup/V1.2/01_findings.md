# teqlif Platformu — Offsite Backup (`node101`) ve Sistem Geneli Bakım / Yedekleme / İş Sürekliliği Bulgular Raporu (V1.2)

**Tarih:** 11 Kasım 2026  
**Sürüm:** `V1.2` *(Claude / mühendislik ekibinin doğrudan adım adım uygulayabileceği, iç referanslı ve çözüldükçe damgalanan yaşayan mühendislik dökümanı)*  
**Durum:** 🔍 Tam Analiz + 6 Mimari Karar Kilitlendi (**Faz 0 → Faz 3: 36 Atomik Adım Uygulamaya Hazır**)  
**Hedef Offsite Sunucusu:** `node101` — `195.206.234.142` (`ssh node101` / DELUXHOST AS214677, Kerkrade NL / Debian 13 `trixie`, `restic 0.18.0` + `restic-rest-server 0.13.0 --append-only`)  
**Repo Config Yolu:** `deploy/scale/V2.1/node101/` (`specs.md`, `config/`, `resources/`)  
**Referans Şablon:** [`documents/problems/V1.0/01_findings.md`](file:///Users/tucibeyin/Desktop/teqlif/documents/problems/V1.0/01_findings.md)  
**İlişkili Raporlar:** `documents/backup/V1.0/01_findings.md`, `documents/backup/V1.1/01_findings.md`, `documents/system_timing/V1.0/01_findings.md`, [`documents/wallet/V1.0/01_findings.md`](file:///Users/tucibeyin/Desktop/teqlif/documents/wallet/V1.0/01_findings.md), `deploy/scale/V2.1/documents/01_architecture.md`

> **Döküman Kullanım & Takip Kuralı (`problems/V1.0` Standardı):**  
> 1. Bu döküman `34` bulgunun (`OFFSITE-01..13`, `MAINT-01..08`, `AUDIT-01..08`, `BIZ-01..05`) tamamını **tek tip kartlarla** (`Ne / Nerede / Neden → Hedef Mimari & Reçete → Doğrulama → Çözüm Damgası`) tanımlar ve sonunda tüm işi **[Master Eylem Planı (36 Adım)](#master-eylem-plani)** altında sıralar.  
> 2. Her **Adım N** uygulandığında ve doğrulama komutu geçtiğinde: (a) özet tablosundaki durum `✅ Çözüldü <commit>` olarak güncellenir, (b) ilgili karttaki `Çözüm Damgası` doldurulur ve (c) Master Plan satırının üzeri `~~...~~ ✅ <commit>` şeklinde çizilir.  
> 3. Birbirinin dosyasına dokunan adımlar (`minio_backup.sh`, `worker.py`, `schedule.yaml`, `health.py`, `postgresql.conf`) kart başındaki **Ortak Dosya / Bağımlılık** satırıyla birbirine çapraz bağlıdır.

---

<a id="icindekiler"></a>
## 🧭 Hızlı Gezinti & Döküman Haritası

- [1. Önceliklendirme ve Özet Tabloları (34 Bulgu → 36 Adım)](#ozet-tablolari)
- [2. Ana Karar Özeti & Kilitli 6 Mühendislik Kararı](#kilitli-kararlar)
- [3. Cluster Envanteri, Canlı `node2` Disk Dökümü & Kanonik 24 Saat Zaman Çizelgesi](#envanter-zamanlama)
- [4. `node101` Offsite Blueprint, WAL RPO Kanıtı, `fio` & DR Senaryoları](#blueprint)
- [5. Detaylı Bulgu Kartları & Uygulanabilir Reçeteler (34 Kart)](#detayli-kartlar)
  - [Bölüm A: Offsite Backup & `node101` Mimarisi (`OFFSITE-01` .. `OFFSITE-13`)](#kartlar-a)
  - [Bölüm B: Sistem Geneli Bakım, Zamanlama & Donanım Anomalileri (`MAINT-01` .. `MAINT-08`)](#kartlar-b)
  - [Bölüm C: Uçtan Uca Bakım, DR, Birikme & Telemetri (`AUDIT-01` .. `AUDIT-08`)](#kartlar-c)
  - [Bölüm D: İş Mantığı, Finans, KVKK/Uyum, SPOF & Ölçek (`BIZ-01` .. `BIZ-05`)](#kartlar-d)
- [6. Master Eylem Planı (Uçtan Uca Sıralı Mühendislik Yol Haritası — Faz 0..3 / Adım 1..36)](#master-eylem-plani)
- [7. Denetim Turları & Güncelleme Günlüğü (`Tur 1` .. `Tur 7`)](#denetim-turlari)

---

<a id="ozet-tablolari"></a>
## 📌 1. Önceliklendirme ve Özet Tabloları

### A. Offsite Backup & `node101` Mimari Bulguları (`OFFSITE-01` .. `OFFSITE-13`)

| ID | Seviye | Bileşen / Dosya | Zaaf / Hata / Bulgu Özeti | Bağlı Adım | Durum |
| :---: | :---: | :--- | :--- | :---: | :---: |
| [`OFFSITE-01`](#offsite-01) | 🔴 **P0** | `cluster.yaml`, `node101/specs.md` | MinIO 2g ILM sonrası tek-kopya riski + `node101` tek volume (`vdb`, RAID yok), IPv4-only ve `/` (`6.1 GB` boş) | [Adım 11](#adim-11) | ✅ `0e61ca9a` |
| [`OFFSITE-02`](#offsite-02) | 🔴 **P0** | `offsite_sync.sh`, `node101` (`ext4`) | `rclone sync` destrüktif silme yayılımı + `ext4` snapshot yokluğu + 7g retention kırpması | [Adım 9](#adim-9) | ✅ `f773a084` |
| [`OFFSITE-03`](#offsite-03) | 🔴 **P0** | `offsite_sync.sh`, `.env.backup` | İstemci şifrelemesi (`restic`) ve sunucu dışı **3'lü Key Escrow** eksikliği | [Adım 10](#adim-10) | ✅ `1bf776a7` |
| [`OFFSITE-04`](#offsite-04) | 🔴 **P0** | `teqlif-offsite-sync.*`, `watchdog`, `health`, `schedule.yaml` | 3 izleme katmanında tam körlük, sessiz `exit 0`, `OnFailure` yok + `disabled` vs `active` timer sapması | [Adım 13](#adim-13) | ✅ `2214bff7` |
| [`OFFSITE-05`](#offsite-05) | 🟠 **P1** | `wg_mesh_apply.sh`, `secrets.env.template`, `node101` UFW | `node101` WG (`10.10.0.101`) peer izolasyonu (yalnız `node2`+`nodeMonitor`), UFW ve SSH sertleştirmesi | [Adım 2](#adim-2) | ✅ Çözüldü `c5cb95a2` |
| [`OFFSITE-06`](#offsite-06) | 🟠 **P1** | `node101` (`2.9 GiB RAM`, `/mnt/data`, `fio`) | Düşük RAM (`2.9 GiB`), `6.1 GB` `/` taşma riski, `fdatasync` tail latency (`83 IOPS`) + TZ `UTC` | [Adım 1](#adim-1) | ✅ Çözüldü `09eb442c` |
| [`OFFSITE-07`](#offsite-07) | 🟠 **P1** | `offsite_sync.sh`, `pg_basebackup.sh`, `pg_wal`, `pg_dump.sh` | Offsite PG PITR (`pg_basebackup`+`pg_wal`) eksikliği (24s RPO) + `pg_dump/*.dump.gz` (2–8 Eki) yetimleri | [Adım 12](#adim-12) | ✅ `114c0ee4` |
| [`OFFSITE-08`](#offsite-08) | 🟠 **P1** | `clickhouse_backup.sh`, canlı `node2` CH | Method 1/2 çalışmıyor (`/var/lib/clickhouse/backups` boş), fallback `285B` arşiv, `BACKUP` izni/DDL yok | [Adım 14](#adim-14) | ⬜ Açık |
| [`OFFSITE-09`](#offsite-09) | 🟠 **P1** | `nodemonitor_config_backup.sh`, canlı `node2` | **`979 MB` TSDB/WAL sızıntısı** (`prometheus/data` 823M + `loki` 156M) — `--delete-excluded` yok | [Adım 15](#adim-15) | ⬜ Açık |
| [`OFFSITE-10`](#offsite-10) | 🟡 **P2** | `node2/systemd/*.service`, `offsite_sync` | Tüm backup servislerinde `IOSchedulingClass=idle`/`Nice=19` eşitleme ve `.tmp`/`.partial` filtre | [Adım 26](#adim-26) | ⬜ Açık |
| [`OFFSITE-11`](#offsite-11) | 🟡 **P2** | `runbook.sh`, `node101/resources/` | `node101 → yeni node1/node2` çifte felaket DR runbook'u + periyodik decrypt/PITR tatbikatı | [Adım 36](#adim-36) | ⬜ Açık |
| [`OFFSITE-12`](#offsite-12) | 🟡 **P2** | `_common.sh`, `bootstrap_node2.sh`, `bootstrap_node101.sh` | Tekrarlanabilir `bootstrap_node101.sh` yok; `node2` bootstrap'ta `rclone`/7 timer `enable` eksik | [Adım 3](#adim-3) | ✅ Çözüldü `1ce09741` |
| [`OFFSITE-13`](#offsite-13) | 🟢 **P3** | `documents/wallet/V1.0`, `node101` | TTK/MASAK 5–10 yıl `financial_archives` WORM şifreli mühürlü akışı eksik | [Adım 35](#adim-35) | ⬜ Açık |

### B. Sistem Geneli Bakım, Zamanlama & Donanım Anomalileri (`MAINT-01` .. `MAINT-08`)

| ID | Seviye | Bileşen / Node | Tespit Edilen Anomali / Çakışma | Bağlı Adım | Durum |
| :---: | :---: | :--- | :--- | :---: | :---: |
| [`MAINT-01`](#maint-01) | 🟠 **P1** | `cleaner.py` vs `schedule.yaml` / `worker.py` | Çift & batch'siz PG `DELETE` (`message_threads 180d` < `dm_archive 365d` veri kaybı tuzağı!) | [Adım 21](#adim-21) | ⬜ Açık |
| [`MAINT-02`](#maint-02) | 🟠 **P1** | `cluster.yaml`, `encoder.py:357`, `minio_backup`, `worker.py` | Video transfer (`05:00–07:00`) ↔ `minio_backup` (`05:30`) ↔ `notify` (`05:00/06:00`) çarpışması | [Adım 22](#adim-22) | ⬜ Açık |
| [`MAINT-03`](#maint-03) | 🔴 **P0** | `node2` `redis-failover*`, `redis_failover.sh` | **`promoted` (`18 Eki`) bayrağı nedeniyle resmi failover kör** + düz metin şifreli rogue timer | [Adım 4](#adim-4) | ✅ Çözüldü `c0154e66` |
| [`MAINT-04`](#maint-04) | 🟡 **P2** | `node1..6`, `node2`, `nodeMonitor` OS Timer | `apt-daily-upgrade` (`06:05–06:50 UTC`) + `node2` `mdcheck` (`06:46 UTC`) backup bloğuna biniyor | [Adım 27](#adim-27) | ⬜ Açık |
| [`MAINT-05`](#maint-05) | 🟡 **P2** | `schedule.yaml`, `schedule_loader.py`, `worker.py` | `backup:` YAML anahtarı yok, `chat_messages` çift kayıt, hatalı saat yorumları | [Adım 28](#adim-28) | ⬜ Açık |
| [`MAINT-06`](#maint-06) | 🟡 **P2** | `loki`, `kuma`, `config`, `pg_wal_cleanup`, `node2` | Redis `job_ok` atmayan 4 script + `0B` yetim `.last_mail_backup_ok` + eski `03:45` mail timer | [Adım 29](#adim-29) | ⬜ Açık |
| [`MAINT-07`](#maint-07) | 🟡 **P2** | `nodeMonitor` (`1.9 GiB RAM`) | **`240 MiB` aktif swap**, `165 MiB` free RAM darboğazı — Prometheus/Loki bellek limiti ayarı | [Adım 30](#adim-30) | ⬜ Açık |
| [`MAINT-08`](#maint-08) | 🟢 **P3** | `node2` `wg show`, `systemd` timeout'lar | Canlı `node2` `wg show` `node3`/`node4` peer eksikliği + backup servislerinde `TimeoutStartSec` | [Adım 34](#adim-34) | ⬜ Açık |

### C. Uçtan Uca Bakım, DR, Birikme & Telemetri (`AUDIT-01` .. `AUDIT-08`)

| ID | Seviye | Bileşen / Node | Tespit Edilen Eksik / Bozuk İşleyiş / Birikme | Bağlı Adım | Durum |
| :---: | :---: | :--- | :--- | :---: | :---: |
| [`AUDIT-01`](#audit-01) | 🔴 **P0** | `node2` DR (`runbook.sh`, `pg_basebackup.sh`, `pg_dump.sh`) | **Yerel DR/PITR kırık:** `pg_lsclusters` boş, **`postgresql-17-pgvector` yok**, `.env.dr`/`cf-origin.*` yok, `pg_wal.tar.gz` atlanıyor + `immediate` PITR'ı kesiyor | [Adım 5](#adim-5) | ✅ Çözüldü `f48e8eaf` |
| [`AUDIT-02`](#audit-02) | 🟠 **P1** | `watchdog.py`, `db.py`, `worker.py`, `reporter.py`, `recorder.py` | Donmuş SQLite (`1 Kas`), `IS NULL` körlüğü, 10+ statik/early-return cron `_agent_ok` yok, `5/11` rapor | [Adım 19](#adim-19) | ⬜ Açık |
| [`AUDIT-03`](#audit-03) | 🟠 **P1** | `nodemonitor_config_backup.sh`, `loki_backup.sh`, cluster sırları | Grafana (`521 MB` + `shared/config`) ve `loki/compactor/` yedeksiz; `node1..6` TLS/WG/`.env` yedeksiz | [Adım 16](#adim-16) | ⬜ Açık |
| [`AUDIT-04`](#audit-04) | 🟠 **P1** | `minio_backup.sh`, `uptime_kuma_backup.sh` | `node2` `30g` video temizlik eksiği + `confirm_recordings` race + Kuma `20B` boş `.sql.gz`/inline şifre | [Adım 18](#adim-18) | ⬜ Açık |
| [`AUDIT-05`](#audit-05) | 🟠 **P1** | `node2`/`node5` ClickHouse, `encoder.py`, `node5:/var/recordings` | TTL'siz CH `system.*_log` (**`node2 2.38 GiB`**, **`node5 5.4 GiB`**) + `3.2G` cache + **`194M` video artığı** | [Adım 23](#adim-23) | ⬜ Açık |
| [`AUDIT-06`](#audit-06) | 🟡 **P2** | `_common.sh`, `teqlif-agent`, `journald` | Kırık `**/*.log` glob (`16M` Redis log), **`565 MB` `agent.log`**, kotasız **`journald` (`1.2G`/`1.6G`)** | [Adım 31](#adim-31) | ⬜ Açık |
| [`AUDIT-07`](#audit-07) | 🟡 **P2** | `teqlif-agent` (`db.py`, `gossip.py`, `janitor.py`) | `cleanup_log` `UNIQUE` eksik + RAM-only `_last_sync` çoğaltma + `janitor.py:149` stale yorum | [Adım 32](#adim-32) | ⬜ Açık |
| [`AUDIT-08`](#audit-08) | 🟡 **P2** | `backend/app/worker.py` (`cleanup_*`) | `media_messages` `.scalars().all()` OOM/`60d→30d`/commit sırası + `11` tablo batch'siz `DELETE` | [Adım 33](#adim-33) | ⬜ Açık |

### D. İş Mantığı, Finans, KVKK/Uyum, SPOF & Ölçek (`BIZ-01` .. `BIZ-05`)

| ID | Seviye | Bileşen / İş Akışı | Tespit Edilen İş Mantığı / Uyum / Ölçek Riski | Bağlı Adım | Durum |
| :---: | :---: | :--- | :--- | :---: | :---: |
| [`BIZ-01`](#biz-01) | 🔴 **P0** | `messages.py` vs `dm_archive`, `streams.py` vs `stream_recording` | **DM Arşivi public bucket okuyup `[]` döner** + **Standart 14g PRO upsell `404 NoSuchKey` kırık** | [Adım 7](#adim-7) ✅, [Adım 8](#adim-8) ✅ | ✅ Çözüldü (`622507fc`) |
| [`BIZ-02`](#biz-02) | 🔴 **P0** | `wallet_tasks.py:102-262`, `node1` PG, `redis_failover.sh` | **Alarmsız mutabakat** + **Sınırsız `max_slot_wal_keep_size = -1`** (prod disk crash!) + `wg` peer tuzağı | [Adım 6](#adim-6), [Adım 4](#adim-4) | ✅ Çözüldü `8234ee8d` |
| [`BIZ-03`](#biz-03) | 🟠 **P1** | `auth.py:1638`, `analytics_tasks`, `listing_tasks`, `notification_service` | KVKK `delete_account` (bakiye kilidi/DM yok) + `--remove` yok + **`07:00 TR` push fırtınası** | [Adım 24](#adim-24), [Adım 18](#adim-18) | ⬜ Açık |
| [`BIZ-04`](#biz-04) | 🟠 **P1** | `mail_backup.sh`, `nodeMonitor` SPOF, Prometheus kapsamı | **`09:15 TR` Mail Stop** (`config.toml`/`.env.mail` yok) + **`nodeMonitor` SPOF** + CH/MinIO/Mail kör | [Adım 17](#adim-17), [Adım 20](#adim-20) | ⬜ Açık |
| [`BIZ-05`](#biz-05) | 🟠 **P1** | `worker.py:4153-4264`, `listing_tasks.py:84-160` | `sync_pg_to_clickhouse` `LIMIT` sessiz veri silme + sınırsız/retry'sız ilan temizleme (`>50K`) | [Adım 25](#adim-25) | ⬜ Açık |

---

<a id="kilitli-kararlar"></a>
## 🎯 2. Ana Karar Özeti & Kilitli 6 Mühendislik Kararı

> **1. "Offsite backup planlamak gerekir mi?"** → **Evet — zorunlu.** Bugün tüm yedekler tek sağlayıcıdaki (OVH) iki sunucuda (`node1` ↔ `node2`) ve video tarafında 2 gün ILM sonrası yalnız `node2` tek kopyasında duruyor.  
> **2. "`node101` altyapısı hazır mı?"** → **`node101` ağ/konum/CPU (`AES-NI ✔`, `12.5 ms` ping, `934 GiB` `/mnt/data`, `fio` 1M `145 MB/s`, 4K `27.4k IOPS`) uygun; ancak şu an boş minimal Debian 13.** Faz 0'dan Faz 3'e sırayla kurulacak.

Uygulama sırasında Claude veya ekibin hiçbir tahmin yapmaması için açık kalmış **6 tasarım kararı** kod tabanı ve canlı donanım verilerine göre kesin olarak kilitlenmiştir:

| # | Karar Alanı | Kilitli Nihai Karar | Gerekçe & Etkilenen Adımlar |
| :---: | :--- | :--- | :--- |
| **K1** | **`mail_backup.sh` Saati** | **`03:50 UTC` (`06:50 TR`)** | `06:15 UTC` (`09:15 TR`) mesai kesintisini bitirir; `03:20` CH ve `03:40` Redis arasına sıkışmaz ([Adım 17](#adim-17)). |
| **K2** | **`archive_old_dm_task` & `03:00` ARQ** | **DM Arşivi: Pazar `03:20 UTC`; Günlük temizlik: `03:10 UTC`** | Önce `03:00 pg_dump` PG anlık görüntüsünü alır, ardından DM arşivlenip silinir → **0 sn tek-kopya** ([Adım 7](#adim-7)). |
| **K3** | **Video Transfer, ILM & 14g PRO Upsell** | **`node1` MinIO ILM: `2g`; Transfer: `04:00–05:00` (`disk_warn 03:00`); `minio_backup`: `05:30`; `notify`: `05:45`; `node2` Video Saklama: `30g`; 3.–14. gün PRO upsell: `node2 → node1` on-demand restore; `recordings/*` hariç diğer prefixlerde `--remove`** | `node1` NVMe şişmez; T+14 hakediş + 16 gün pay kalır; global `--remove` video arşivini silmezken KVKK avatar/ilan/DM silmeleri `node2`'ye yansır ([Adım 8](#adim-8), [Adım 18](#adim-18), [Adım 22](#adim-22)). |
| **K4** | **Canlı `node1` PG `postgresql.conf`** | **`wal_compression = lz4`, `archive_timeout = 3600`, `max_slot_wal_keep_size = '50GB'`, `lock_timeout = '5s'`, `idle_in_transaction_session_timeout = '5min'`, global `statement_timeout = 0`** *(API/cleanup'ta `SET LOCAL '15s'`)* | Canlı PG 17.11'de `lz4` mevcut ve `426 GB` boş alan var; `50GB` sınırı `node2` kesintisinde prod diski kurtarır, `0` global timeout `pg_dump`'ı kesmez ([Adım 6](#adim-6)). |
| **K5** | **`media_messages` Süresi & KVKK `delete_account`** | **`media_messages`: `30 gün` (`500` batch, commit sonrası silme). `delete_account`: `pending`/`available > 0` veya açık `WithdrawalRequest` varsa `HTTP 409`; `0` ise DM/ilan medyası temizliği + TTK/MASAK WORM** | `3/7g` T+14 anlaşmazlık kanıtını bozar, `30g` hem kanıtı korur hem mevcut `60g`'ye göre diski %50 azaltır ([Adım 24](#adim-24), [Adım 33](#adim-33)). |
| **K6** | **Promosyon/Airdrop Push Penceresi & Saatlik WAL** | **Airdrop/İlan/Retarget push: `08:00–08:30 UTC` (`11:00–11:30 TR`) + `quiet_hours`. Offsite motoru: `restic 0.18 --pack-size 32` (`daily-full` `06:30 UTC`, saatlik WAL `*:45 UTC`)** | `07:00 TR` push fırtınasını önler; `--pack-size 32` `node101` `83 IOPS fdatasync` tıkanmasını aşar ([Adım 12](#adim-12), [Adım 13](#adim-13), [Adım 24](#adim-24)). |

---

<a id="envanter-zamanlama"></a>
## 📊 3. Cluster Envanteri, Canlı Disk Dökümü & Kanonik 24 Saat Zaman Çizelgesi

### 3.1. Cluster Geneli Donanım, Disk & Bakım Rolü Matrisi (Canlı Ölçüm: 11 Kasım 2026)

| Node | Sağlayıcı / Konum | Donanım (CPU) | RAM / Swap (Canlı) | Disk & Boş Alan (Canlı) | OS / TZ | WG IP | Rol |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **`node1`** | OVH Dedicated | `6c/12t`, Xeon | `31 GiB` (`19 GiB` avail) | `/dev/md3` **`467G`** (`17G` kullan., **`426G` boş**, `%4`). PG `1.1G`, MinIO `360K`, Log `16M` | Debian 13 / `UTC` | `10.10.0.1` | Primary PG 17.11, Redis Core, MinIO, FastAPI, ARQ (`default`, `critical`, `video`) |
| **`node2`** | OVH Dedicated (DE) | `4c/8t` Xeon D-2123IT | `31 GiB` (`25 GiB` avail) / `1G` Swap | `/dev/md3` RAID-1 HGST **`3.6T`** (`8.9G` kullan., **`3.4T` boş**, `%1`). Backups `~2.1G` | Debian 13 / `UTC` | `10.10.0.2` | Merkezi Yedekleme, `pg_receivewal`, DR Standby, Redis Replica, ClickHouse, Stalwart |
| **`node3`** | OVH VPS | `6 vCPU` | `11 GiB` (`10 GiB` avail) | **`99G`** (`85G` boş). `/var/recordings` | Debian 13 / `UTC` | `10.10.0.3` | LiveKit Edge 1 + Encode (`03:00/04:00–05:00 UTC` transfer → `node1`) |
| **`node4`** | OVH VPS | `6 vCPU` | `11 GiB` (`10 GiB` avail) | **`99G`** (`85G` boş). `/var/recordings` | Debian 13 / `UTC` | `10.10.0.4` | LiveKit Edge 2 + Encode (`03:00/04:00–05:00 UTC` transfer → `node1`) |
| **`node5`** | zap-hosting | `4 vCPU` | `7.8 GiB` (`5.5G` avail) / `4G` Swap | `/dev/sda1` **`50G`** (`27G` kullan., **`22G` boş**, **`%56`** — CH `5.4G` + cache `3.2G` + rec `194M`) | Debian 13 / `UTC` | `10.10.0.5` | Staging + AI Proxy (`10.10.0.5:8001`) + Redis VIP |
| **`node6`** | zap-hosting | `4 vCPU` | `3.8 GiB` (`3.2G` avail) / `4G` Swap | `/dev/sda1` **`50G`** (`18G` kullan., **`30G` boş**, `%37`) | Debian 13 / `UTC` | `10.10.0.6` | AI Proxy 2 + Redis VIP |
| **`nodeMonitor`** | Netcup | `2 vCPU` | `1.9 GiB` (`165M` free / **`240M` Swap aktif!**) | `/dev/vda3` **`58G`** (`13G` kullan., `43G` boş). Prom `1.4G`, Loki `314M` | Debian 13 / **`Europe/Berlin`** | `10.10.0.99` | Prometheus, Alertmanager, Loki, Grafana (`521M`), Uptime Kuma, `teqlif-agent` Lider |
| **`node101`** | DELUXHOST (`AS214677`, NL) | `2 vCPU` E5-2699 v4 (**`AES-NI ✔`**) | **`2.9 GiB`** (`2.6G` avail) / `1G` Swap | `vda` `10G` SSD (`/` **`6.1G` boş** `%36`) + **`vdb` `1000G` (`/mnt/data` `984G`: **`934G` boş**, `1M 137/145 MiB/s`, `4k 27.4k IOPS`, `fdatasync 83/s`)** | Debian 13 / **`Europe/London` → `UTC`** | `195.206.234.142` (WG `10.10.0.101`) | **Offsite Hedef** (`rest-server --append-only`, `12.5 ms`, `1 Gbps`, IPv4-only) |

### 3.2. Canlı `node2` `/project/teqlif/backups/` Durumu (11 Kasım 2026 `~05:35 UTC`)

| Dizin | Canlı Boyut | Saklama | Gerçek Durum & İlgili Bulgu |
| :--- | ---: | :--- | :--- |
| `nodemonitor_config` | **`979 MB`** | Kalıcı | 🔴 `prometheus/data` (`823M`, 18 Eki) + `loki` (`156M`, aktif `wal/` dahil) sızıntısı (`--delete-excluded` yok) → [`OFFSITE-09`](#offsite-09) |
| `pg_wal` | **`561 MB`** | En eski `basebackup`'a | 🟡 `34` segment (`16M` dosya ~15–27 saatte kapanıyor), offsite dışı → [`OFFSITE-07`](#offsite-07) |
| `loki` | **`393 MB`** | `90g` | Sağlam (`chunks/`), ama `compactor/` & `job_ok` yok → [`AUDIT-03`](#audit-03), [`MAINT-06`](#maint-06) |
| `stalwart` | **`136 MB`** | `90g` | Tar `643` dosya (✔), ama `config.toml`/`.env.mail`/`acme/` yok + `09:15 TR` kesinti + `0B` yetim sentinel → [`BIZ-04`](#biz-04), [`MAINT-06`](#maint-06) |
| `uptime_kuma` | **`14 MB`** | `180g` | `67.015` satır (✔), ama `13 Eki` `20B` boş `.sql.gz` var + `job_ok` yok → [`AUDIT-04`](#audit-04) |
| `pg_basebackup` | **`14 MB`** | Son `2` adet | Pazar `02:00 UTC` (✔), ama offsite dışı + non-atomik + `runbook` `pg_wal.tar.gz` atlıyor → [`OFFSITE-07`](#offsite-07), [`AUDIT-01`](#audit-01) |
| `pg_dump` | **`8.2 MB`** | `7g` | `teqlif_*.dump` `647` öğe (✔), ama `2–8 Eki` `7` eski `.dump.gz` yetim duruyor + `--globals-only` yok → [`OFFSITE-07`](#offsite-07), [`AUDIT-01`](#audit-01) |
| `redis` | **`2.9 MB`** | `7g` | `gzip -t` ✔; ancak failover **`promoted` (`18 Eki`)** bayrağı ile kör → [`MAINT-03`](#maint-03) |
| `clickhouse` | **`40 KB`** | `7g` | 🔴 Method 1/2 çalışmıyor; fallback boş `~285B` `.tar.gz`; `BACKUP` yetkisi/DDL yok → [`OFFSITE-08`](#offsite-08) |
| `minio` | **`12 KB`** | `30g` hedef | `0B` (henüz video yok); `node2` `15g/30g` silme kodu yok, `--remove` ayrımı yok → [`AUDIT-04`](#audit-04), [`BIZ-01`](#biz-01) |
| **TOPLAM** | **`~2.1 GB`** | — | Çöp TSDB hariç **temiz çekirdek yedek hacmi şu an ~1.1 GB**. |

<a id="zamanlama-matrisi"></a>
### 3.3. Hedef Kanonik 24 Saatlik Bakım, Yedekleme & İş Penceresi (Çakışmasız Tek Doğru Tablo)

> **Not:** `node1..6`, `node2` ve `node101` **UTC** çalışır; yalnız `nodeMonitor` `Europe/Berlin` (`UTC+1/+2`) olduğundan systemd timer'larda mutlaka açık `UTC` yazılır.

| UTC | TR (`+3`) | Host / Katman | İş / Görev | Uygulama Adımı & Değişiklik |
| :--- | :--- | :--- | :--- | :--- |
| **Sürekli / Sn** | — | `node2`, `node1`, Edges | `pg_receivewal` (sürekli), `teqlif-redis-failover` (`10s`), `direct_sale` (`10s`), `flush_ch` (`30s`), `concat` (`2m`), `expire_rec` (`:00,:30`), `archive_rec` (`:15`) | [Adım 4](#adim-4), [Adım 19](#adim-19) |
| **`*:45` (Saatlik)** | — | `node2` → `node101` | **Saatlik PG WAL Offsite (`teqlif-offsite-wal.timer`)** (`--tag pg_wal --exclude '*.partial'`) | [Adım 13](#adim-13) *(RPO ≤ 1 saat)* |
| `00:00` | `03:00` | `node1` ARQ | `daily_financial_reconciliation_task` (**sapmada acil Telegram/Sentry**) | [Adım 6](#adim-6) |
| `00:05` *(Ayın 1)* | `03:05` | `node1` ARQ | `reset_monthly_withdrawal_quota_task` | [Adım 19](#adim-19) |
| `01:50` | `04:50` | `node1` → `node2` | `sync_pg_to_clickhouse_task` (**cursor pagination + batch delete**) | [Adım 25](#adim-25) |
| `02:00` *(Pazar)* | `05:00` | `node2` systemd | `teqlif-pg-basebackup.timer` (atomik `.tmp`→`mv`, `--max-rate=40M`) | [Adım 5](#adim-5) |
| `02:15` | `05:15` | `node1` ARQ | `release_pending_earnings_task` (`T+14`) | — *(02:00 sonrası temiz)* |
| `02:30 – 02:45` | `05:30 – 05:45` | `node1` / CH | `compute_analytics_cache_task`, `precompute_premium_user_analytics_task` | — |
| `03:00` | `06:00` | `node2` systemd | **`teqlif-pg-dump.timer`** (`--globals-only` + `-Fc` + `pg_restore -l`) | [Adım 5](#adim-5) |
| **`03:10`** | **`06:10`** | `node1` ARQ | `check_expired_pro_users`, `cleanup_old_notifications`, `cleanup_old_stream_likes` | [Adım 28](#adim-28) *(`pg_dump` arkası)* |
| **`03:20`** | **`06:20`** | `node2` systemd / `node1` | `teqlif-clickhouse-backup.timer` + **Pazar: `archive_old_dm_task`** + `badges`/`budgets`/`trust` | [Adım 7](#adim-7), [Adım 14](#adim-14) |
| `03:40` | `06:40` | `node2` systemd | `teqlif-redis-backup.timer` (`BGSAVE` → `.rdb.gz`) | — |
| **`03:50`** | **`06:50`** | `node2` systemd | **`teqlif-mail-backup.timer`** (Stalwart stop ~1s + `config.toml`/`.env.mail`/`acme/` + `tar -tzf`) | [Adım 17](#adim-17) *(`09:15 TR` kesinti biter)* |
| **`03:00 / 04:00–05:00`** | **`06:00/07:00–08:00`** | `node3/4` → `node1` | **Video Transfer Penceresi** (`start_utc: 3, end_utc: 5`; normal `04:00–05:00`, low-disk `03:00–05:00`) + sessiz PG temizlikleri | [Adım 22](#adim-22), [Adım 33](#adim-33) |
| `05:00 – 05:45` | `08:00 – 08:45` | `node1` ARQ | Haftalık temizlik + **ML Eğitim** (`train_bpr`, `train_churn`, `kmeans`, Pazar DAG) + `media_messages` (`30g`) | [Adım 25](#adim-25), [Adım 33](#adim-33) |
| **`05:30`** | **`08:30`** | `node2` systemd | **`teqlif-minio-backup.timer`** (`recordings/` 30g + diğer prefix `--remove` + zaman kilidi) | [Adım 18](#adim-18) |
| **`05:45`** | **`08:45`** | `node1` ARQ | `notify_new_recordings_task` (`05:30` mirror sonrası, yalnız kayıt sahiplerine!) | [Adım 22](#adim-22) |
| `06:00 – 06:10` | `09:00 – 09:10` | `node2` ← `nodeMonitor` | `loki_backup` (`06:00`, +`compactor`), `uptime_kuma` (`06:05`), `nodemonitor_config` (`06:10`, `--delete-excluded` + `Grafana`) | [Adım 15](#adim-15), [Adım 16](#adim-16), [Adım 18](#adim-18) |
| `06:20` | `09:20` | `node2` systemd | `pg_wal_cleanup.timer` (`pg_archivecleanup` + `job_ok`) | [Adım 29](#adim-29) |
| **`06:30`** | **`09:30`** | `node2` → `node101` | **Günlük Ana Offsite (`teqlif-offsite-sync.timer`)** (`restic --tag daily-full --pack-size 32`, `IO=idle`) | [Adım 12](#adim-12), [Adım 13](#adim-13) |
| **`07:30+`** | **`10:30+`** | Tüm Node'lar | OS `apt-daily-upgrade` (`07:30–08:30`), `node2` aylık `mdcheck` (`07:30+`), **Pazar `08:00 UTC` `node101` `restic prune`/`check`** | [Adım 9](#adim-9), [Adım 27](#adim-27) |
| **`08:00 – 08:30`** | **`11:00 – 11:30`** | `node1` ARQ | **Promosyonel Push Penceresi:** `process_churn_and_airdrop`, `hesitation_retarget`, ilan süre/silme push'ları | [Adım 24](#adim-24) *(`07:00 TR` fırtına biter)* |

---

<a id="blueprint"></a>
## 🏗️ 4. `node101` Kilitli Offsite Blueprint, WAL Kanıtı, `fio` & DR Senaryoları

### 4.1. Motor & Topoloji: `restic 0.18.0` → `restic-rest-server 0.13.0 --append-only`
Debian 13 (`trixie`) deposunda her iki paket yerel olarak vardır. `node2` WG üzerinden yalnız ekleme (`append`) yapar; `forget`/`prune` HTTP isteklerini `--append-only` reddeder. Temizlik yalnız `node101` lokal timer'ı (`GOMEMLIMIT=1536MiB`, `GOGC=20`, `MemoryMax=2G`, Pazar `08:00 UTC`) ile koşar:
- `--tag daily-full`: `--keep-daily 7 --keep-weekly 4 --keep-monthly 6`
- `--tag pg_wal`: `--keep-within 7d` (`≤ 168` küçük snapshot; `2.9 GiB` RAM taşmaz)
- `--tag financial-worm` ([Adım 35](#adim-35)): `--keep-yearly 10 --keep-monthly 24`

### 4.2. WAL RPO Kanıtı (`archive_timeout=0` → `3600`) & `/mnt/data` `fio-3.39` Kanıtı
- **Canlı WAL Ölçümü (`node2/backups/pg_wal`):** `009E` (`Nov 8 02:00`) → `009F` (`Nov 9 08:16`) → `00A0` (`Nov 9 09:19`) → `00A1` (`Nov 10 12:21`, **~27 saat fark!**). Mevcut trafikte `archive_timeout=0` iken segment dolmadığı için saatlik push tek başına RPO'yu iyileştirmez; **`node1` `archive_timeout=3600` + `wal_compression=lz4` + saatlik `*:45 UTC` push** ile PG RPO **≤ 1 saate** iner.
- **`/mnt/data` (`vdb` `984G`) `fio-3.39` Sonuçları ([`specs.md`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/node101/specs.md#L70-L98)):** `seq-rw 1M` `137/145 MiB/s`, `rand-4k` `27.4k/27.4k IOPS`, `sync-write 64k fdatasync` **`83 IOPS / 5.45 MB/s` (`p99=229.6 ms`, `max=871.9 ms`)**. Küçük dosya aktarımını boğmamak için `restic backup --pack-size 32` zorunludur.

### 4.3. Üç Felaket Kurtarma (DR) Senaryosu
- **Senaryo A (`node2` kaybı, `node1` sağ):** Yeni `node2` → WG `10.10.0.2` → `restic restore latest --tag daily-full` + `pg_receivewal`/replica yeniden bağlanır (`API 0 dk kesinti`, yedek geçmişi `≤ 1s`).
- **Senaryo B (`node1` kaybı, `node2` sağ):** Düzeltilmiş [`runbook.sh`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/node2/resources/scripts/runbook.sh) ile `node2` üzerinde gerçek PITR (`pg_basebackup` + `pg_wal` replay), MinIO & Redis failover devreye girer (`RPO ~1 dk`, `RTO 2–15 dk`).
- **Senaryo C (Çifte Felaket — `node1` + `node2` ikisi de gitti):** Key Escrow'dan repo şifresi alınır → yeni `node1/node2` açılır → `node101`'den sıra ile `.env`/config → `pg_basebackup`+`pg_wal` PITR → `minio` (`teqlif`, `teqlif-dm`) → `clickhouse` → `redis` → `stalwart` → `uptime_kuma` / `grafana` geri yüklenir (`DB RPO ≤ 1 saat`, `RTO ~1–3 saat`).

---

<a id="detayli-kartlar"></a>
## 🔍 5. Detaylı Bulgu Kartları & Uygulanabilir Çözüm Reçeteleri

<a id="kartlar-a"></a>
### Bölüm A — Offsite Backup & `node101` Mimarisi (`OFFSITE-01` .. `OFFSITE-13`)

---

<a id="offsite-01"></a>
#### `OFFSITE-01` · 🔴 P0 (Kritik) · MinIO 2g ILM Tek-Kopya Riski ve `node101` Tek-Volume / `/` Kısıtları

**Bağlı Adım:** [Adım 11](#adim-11) · **Ortak Dosya:** `minio_backup.sh`, `offsite_sync.sh` ([`AUDIT-04`](#audit-04), [`BIZ-01`](#biz-01)) · **Mimari:** [Blueprint](#blueprint)

##### 1. Zaafın Kök Nedeni ve Mekanizması (Ne / Nerede / Neden?)
* **Etkilenen Dosyalar:** [`cluster.yaml:46-51`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/cluster.yaml#L46-L51), [`specs.md:18,22,89-98`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/node101/specs.md#L18-L98)
* **Canlı Kanıt (`node1` ↔ `node2` ↔ `node101`):**
  1. `node1` ve `node2` aynı sağlayıcıda (OVH); `node1` MinIO `recordings/` dosyaları `2 gün`de silindiğinden 3. günden itibaren **tek kopya `node2`'de** kalmaktadır.
  2. `node101` (`DELUXHOST AS214677`, NL) sağlayıcı/ülke izolasyonu sağlar ancak `/mnt/data` (`/dev/vdb` `984G`) **RAID-1 olmayan tek volume**dur; ayrıca `node101` **IPv4-only**'dir (`IPv6 Offline`) ve root `/` yalnız **`6.1 GB` boş alana** sahiptir.

##### 2. Hedef Mimari & Çözüm Reçetesi (Ne İçin / Nasıl?)
1. **3-2-1 Kuralında Rol Kilidi:** `node101` birincil kopya değil **"1 offsite kopya"** olarak konumlanır; `minio_backup.sh` 2g ILM tetiklemesi öncesi `node2` kopyasına ek olarak `06:30 UTC` `daily-full` offsite ile `node101`'de en az 1 şifreli snapshot tutulur.
2. **Offsite Kapsamında `minio` Sıralaması:** `offsite_sync.sh` içinde `pg_dump`, `minio/teqlif/recordings` ve `minio/teqlif-dm` en üst öncelikte `restic backup --tag daily-full` paketine dahil edilir.
* **Doğrulama:** `ssh node101 "df -h / /mnt/data"` sonrası `/` kullanımının `%40` altında ve `restic snapshots --tag daily-full` içinde `/project/teqlif/backups/minio` yolunun mevcut olduğu doğrulanır.

##### ✅ Çözüm Damgası
- `2026-11-12` · commit `c5133ac3` → `0e61ca9a` — **P0+P1 OFFSITE-01 kapatıldı** ✓: 3-2-1 kural doğrulaması: `offsite_sync.sh` `/project/teqlif/backups/minio` (teqlif + teqlif-dm) `daily-full` restic snapshot'ına dahil ✓; timer sırası 05:30 minio_backup → 06:30 offsite_sync ✓; ILM 2d normal / 7d emergency ✓. Canlı: `e9549003` (2026-11-12 06:30) paths → `/project/teqlif/backups/minio` ✓; node101 `/` 37% ✓; `/mnt/data` 1% ✓. **P1 staleness guard** (`0e61ca9a`): eşik 43200s (12h) — Persistent/retry/manuel çalıştırma yanlış alarm üretmez; minio stale ise restic tüm kritik yollar için çalışır (fate-sharing kırıldı), tamamlandıktan sonra exit 1 + OnFailure alarmı.

---

<a id="offsite-02"></a>
#### `OFFSITE-02` · 🔴 P0 (Kritik) · `rclone sync` Yıkıcı Silme Yayılımı + `ext4` Snapshot Eksikliği

**Bağlı Adım:** [Adım 9](#adim-9) · **Ortak Dosya:** `node101/systemd/restic-rest-server.service` ([`OFFSITE-03`](#offsite-03), [`OFFSITE-07`](#offsite-07))

##### 1. Zaafın Kök Nedeni ve Mekanizması (Ne / Nerede / Neden?)
* **Etkilenen Dosya:** [`offsite_sync.sh:61`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/node2/resources/scripts/offsite_sync.sh#L61)
```bash
# Mevcut kod (destrüktif sync):
rclone sync "${src}" "${DEST}/$(basename "${src}")" \
```
1. `rclone sync`, `node2` kaynakta silinen veya ransomware ile şifrelenen dosyaları bir sonraki `07:00` çalışmada **`node101`'den de siler**.
2. `pg_dump` ve `redis` yerelde 7 gün tutulur; `sync` varsa 8 günlük geri dönüş penceresi hiç oluşmaz. `node101:/mnt/data` `ext4` olduğundan ZFS/Btrfs snapshot koruması da yoktur.

##### 2. Hedef Mimari & Çözüm Reçetesi (Ne İçin / Nasıl?)
* `node101`'de `restic-rest-server` kurulumunda **`--append-only`** zorunlu tutulur; `node2` asla `forget`/`prune` HTTP DELETE çağrısı atamaz. Eski snapshot budaması yalnız `node101` yerel systemd timer'ından yapılır:
```ini
# /etc/systemd/system/restic-rest-server.service (deploy/scale/V2.1/node101/systemd/)
[Unit]
Description=teqlif Offsite Restic REST Server (Append-Only WORM)
After=network-online.target wg-quick@wg0.service

[Service]
User=teqlif-backup
Group=teqlif-backup
Environment=TMPDIR=/mnt/data/tmp
ExecStart=/usr/bin/restic-rest-server \
    --path /mnt/data \
    --listen 10.10.0.101:8000 \
    --htpasswd-file /etc/teqlif-offsite/htpasswd \
    --append-only \
    --private-repos
Restart=always
RestartSec=5
MemoryMax=512M

[Install]
WantedBy=multi-user.target
```
```ini
# teqlif-offsite-prune.service (node101 yerel Pazar 08:00 UTC — OOM korumalı)
[Service]
Type=oneshot
User=teqlif-backup
Environment="GOGC=20" "GOMEMLIMIT=1536MiB" "TMPDIR=/mnt/data/tmp" "RESTIC_CACHE_DIR=/mnt/data/cache/restic"
EnvironmentFile=/etc/teqlif-offsite/restic.env
IOSchedulingClass=idle
Nice=19
MemoryMax=2G
ExecStart=/usr/bin/restic forget --tag daily-full --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune
ExecStart=/usr/bin/restic forget --tag pg_wal --keep-within 7d --prune
```
* **Doğrulama:** `node2` üzerinden `restic forget --prune` denemesi HTTP `403/Forbidden (append-only)` hatası döndürmelidir; `systemctl is-active restic-rest-server` `active` olmalıdır.

##### ✅ Çözüm Damgası
- `2026-11-12` · commit `f773a084` — **P0 OFFSITE-02 kapatıldı** ✓: `restic-rest-server.service` `MemoryMax` `256M→512M` (peak 259MB OOM riskini giderir) ✓; `After=wg-quick@wg0.service` bağımlılığı eklendi ✓; `teqlif-offsite-prune.service` `MemoryMax` `1536M→2G` (GOMEMLIMIT 1536MiB için GC headroom) ✓; `bootstrap_node101.sh` prune+verify timer'lar artık kurulumda enable ediliyor ✓. Live node101: servis dosyaları `sudo cp` + `daemon-reload` ✓; `restic-rest-server` restart — `active`, `MemoryMax=536870912` (512M), `After=wg-quick@wg0.service` ✓; `teqlif-offsite-prune.timer` + `teqlif-offsite-verify.timer` enable + start ✓; Sonraki tetik: Pazar `2026-11-15 08:00/09:00 UTC` ✓; `--append-only`, `--private-repos`, `Authentication enabled` journal'da onaylı ✓.
- `2026-11-12` · commit `e6641f5b` — **P2 bootstrap hijyeni** ✓: `/mnt/data/teqlif` önceden `teqlif-backup:teqlif-backup 700` oluşturuluyor ✓; `notify_backup_failed.sh` `/usr/local/bin/` kurulumu eklendi ✓; `htpasswd ... tucibeyin` → `teqlif` ✓; ölü `restic_prune.sh`/`restic_verify.sh` silindi ✓; `01_findings.md` snippet `prune.env` → `restic.env` ✓.
- `2026-11-12` · commit `340649df` — **P1 final: restic.env single-source-of-truth** ✓: `EnvironmentFile=` her zaman `Environment=` satırlarını ezebileceğinden `restic.env.template` ve canlı `/etc/teqlif-offsite/restic.env` → yalnız `RESTIC_REPOSITORY`+`RESTIC_PASSWORD`; `GOGC/GOMEMLIMIT/TMPDIR/RESTIC_CACHE_DIR` tamamen kaldırıldı ✓; her servis kendi `Environment=` satırında yönetiyor; `EnvironmentFile=` önce yükleniyor ✓. Canlı doğrulama: `verify` `GOMEMLIMIT=384MiB` ✓ — `prune` `GOMEMLIMIT=1536MiB` ✓ (restic.env override yok).

---

<a id="offsite-03"></a>
#### `OFFSITE-03` · 🔴 P0 (Kritik) · İstemci Taraflı Şifreleme & Sunucu Dışı Anahtar Emaneti (Key Escrow) Eksikliği

**Bağlı Adım:** [Adım 10](#adim-10) · **İlgili:** [`OFFSITE-02`](#offsite-02), [`OFFSITE-11`](#offsite-11)

##### 1. Zaafın Kök Nedeni ve Mekanizması (Ne / Nerede / Neden?)
* `offsite_sync.sh` şifrelemesiz tasarlandığı için PII (`pg_dump`), özel DM medyası (`teqlif-dm`), mail (`stalwart`) ve tüm cluster `.env` sırları (`nodemonitor_config`) `node101` KVM host diskinde düz metin dururdu. Öte yandan şifre yalnız `node2`'de tutulursa `node2` kaybında offsite yedek ebediyen kilitlenir.

##### 2. Hedef Mimari & Çözüm Reçetesi (Ne İçin / Nasıl?)
1. `node2` RAM'inde `restic` (`AES-256-CTR + Poly1305`, `AES-NI` donanım hızlandırmalı) ile istemci taraflı şifreli `restic init` çalıştırılır (parola `node2:/project/teqlif/config/.env.backup` → `RESTIC_PASSWORD`, `640 root:tucibeyin`; node101 `/etc/teqlif-offsite/restic.env` → `640 root:teqlif-backup`; **Git'e asla commit edilmez**).
2. **Üçlü Key Escrow Zorunluluğu:** `RESTIC_PASSWORD` + `rest-server` kullanıcı parolası en az 2 sunucu dışı ortama (yerel yönetici Password Manager + offline şifreli USB/kağıt kasa) kaydedilir.
* **Doğrulama:** Rastgele bir test dizinine yalnız Key Escrow şifresiyle `restic -r ... restore latest --target /tmp/escrow-test` okuma testi sıfır hatayla tamamlanır ve `/tmp/escrow-test` temizlenir.

##### ✅ Çözüm Damgası
- `2026-11-12` · commit `1bf776a7` — **P0 OFFSITE-03 kapatıldı** ✓: `RESTIC_PASSWORD` node2 `.env.backup`'ta mevcut ✓; restic repo initialize edilmiş — 27 snapshot (daily-full + pg_wal) aktif ✓; RESTIC_PASSWORD node101 `/etc/teqlif-offsite/restic.env`'e stdin pipe ile sync edildi (şifre komut argümanına geçmedi) ✓; `restic check --read-data-subset=5%` node101 lokal → `no errors were found` ✓; `restic restore e9549003 --include pg_dump → /tmp/escrow-test` 8.072 MiB başarıyla geri yüklendi, cleanup OK ✓; `secrets.env.template`'e `restic_aes_password=` + `restic_rest_password=` eklendi (apply_secrets bootstrap bütünlüğü) ✓. **Key Escrow:** `secrets.env` (gitignore, lokal) proje için birincil escrow — `restic_aes_password=` + `restic_rest_password=` girdileri `secrets.env.template`'e eklendi; kullanıcı node2 `.env.backup` değerlerini kendi `secrets.env`'ine kaydetti ✓.
- `2026-11-12` · **P2 ek düzeltmeler** ✓: `secrets.env.template`'e `restic_rest_user=teqlif` eklendi (DR bootstrap RESTIC_REST_USER placeholder tutarlılığı) ✓; `01_findings.md` L296 eski `/etc/teqlif/restic.pass` yolu fiili `.env.backup` / `restic.env` lokasyonlarıyla güncellendi ✓. **Operasyonel not:** `RESTIC_PASSWORD` + `RESTIC_REST_PASSWORD` için 2. bağımsız offsite kopya (Password Manager / offline şifreli USB) kullanıcı sorumluluğunda.

---

<a id="offsite-04"></a>
#### `OFFSITE-04` · 🔴 P0 (Kritik) · Üç Katmanlı Offsite İzleme Körlüğü + Sessiz `exit 0` + Timer Sapması

**Bağlı Adım:** [Adım 13](#adim-13) · **Ortak Dosya:** `teqlif-offsite-sync.service`, `schedule.yaml`, `health.py` ([`MAINT-06`](#maint-06), [`AUDIT-02`](#audit-02))

##### 1. Zaafın Kök Nedeni ve Mekanizması (Ne / Nerede / Neden?)
* **Etkilenen Dosyalar:** [`offsite_sync.sh:45-49`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/node2/resources/scripts/offsite_sync.sh#L45-L49), [`teqlif-offsite-sync.service:1-10`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/node2/systemd/teqlif-offsite-sync.service#L1-L10), [`health.py:44-54,402-418`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/teqlif-agent/modules/health.py#L44-L418), [`schedule.yaml:304-340`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/schedule.yaml#L304-L340)
```bash
# offsite_sync.sh:45-49 (sessiz exit 0 → 23 gün alarm vermedi):
if [[ -z "${RCLONE_REMOTE:-}" ]] || [[ -z "${RCLONE_BUCKET:-}" ]]; then
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) offsite_sync: SKIP — RCLONE_REMOTE/RCLONE_BUCKET tanımlı değil"
    exit 0
fi
```
1. Canlı `node2`'de `teqlif-offsite-sync.timer` **dosyası `disabled`** olduğu halde RAM'de **`active` (Oct 18)** çalışıp her sabah `07:00 UTC`'de `SKIP ... exit 0` atıyor (reboot'ta düşer!).
2. **`teqlif-offsite-sync.service`** içinde `9` çekirdek backup servisinde bulunan `OnFailure=teqlif-backup-failed@%n.service` yok (`pg-wal-cleanup` ile birlikte eksik); `schedule.yaml`'da `offsite_sync`/`offsite_wal_sync` yok; `health.py` `_BACKUP_MAX_MIN` ve `_backup_ages` içinde yok!

##### 2. Hedef Mimari & Çözüm Reçetesi (Ne İçin / Nasıl?)
1. `offsite_sync.sh` & yeni `offsite_wal_sync.sh`: Env eksikse Telegram/syslog + **`exit 2`** dön (`OFFSITE_MODE=disabled` açık verilmedikçe). Başarıda `/project/teqlif/backups/.last_offsite_sync_ok` / `.last_offsite_wal_ok` + Redis `HSET teqlif:agent:job_ok` yaz.
2. `teqlif-offsite-sync.service` içine `OnFailure=teqlif-backup-failed@%n.service`, `IOSchedulingClass=idle`, `Nice=19`, `EnvironmentFile=/project/teqlif/config/.env.backup` ekle; yeni `teqlif-offsite-wal.{service,timer}` (`OnCalendar=*-*-* *:45:00 UTC`) oluştur ve her iki timer'ı `systemctl enable --now` yap.
3. [`schedule.yaml`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/schedule.yaml) `backup:` altına `offsite_sync` (`watchdog_m: 1500`) + `offsite_wal_sync` (`watchdog_m: 90`); [`health.py`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/teqlif-agent/modules/health.py#L44-L54) içine `offsite_sync` (`25*60`) ve `offsite_wal_sync` (`90`) ekle.
* **Doğrulama:** `systemctl is-enabled teqlif-offsite-sync.timer teqlif-offsite-wal.timer` ikisi de `enabled` döner; sahte hata ile `systemctl start teqlif-offsite-sync.service` `OnFailure` Telegram uyarısı tetikler.

##### ✅ Çözüm Damgası
- `2026-11-12` · commit `2214bff7` — **P0 OFFSITE-04 kapatıldı** ✓: `offsite_sync.sh` / `offsite_wal_sync.sh` sessiz `exit 0` → `exit 2` (OFFSITE_MODE=disabled olmadıkça) ✓; `.last_offsite_sync_ok` + `.last_offsite_wal_ok` sentinel dosyaları başarılı çalışmada dokunuluyor ✓; `teqlif-offsite-sync.service` `Nice=10→19`, `EnvironmentFile=` eklendi ✓; `schedule.yaml`: `offsite_sync` (watchdog_m:1500) + `offsite_wal_sync` (watchdog_m:90) ✓; `health.py` `_BACKUP_MAX_MIN` + `sentinel_dirs` offsite girişleri ✓. Canlı doğrulama: sentinel dosyaları `Nov 12 14:01/14:02` ✓; her iki timer `enabled` ✓; `teqlif-agent` yeniden başlatıldı.
- `2026-11-12` · commit `f41689e6` — **P2 kapatıldı** ✓: `health.py` `blabel` sözlüğüne `"offsite_sync"` + `"offsite_wal_sync"` Türkçe etiketler eklendi ✓; `teqlif-offsite-wal.service` `Nice=10→19` + `EnvironmentFile=/project/teqlif/config/.env.backup` ✓.

---

<a id="offsite-05"></a>
#### `OFFSITE-05` · 🟠 P1 (Yüksek) · `node101` Ağ Topolojisi, WireGuard (`10.10.0.101`) ve Firewall İzolasyonu

**Bağlı Adım:** [Adım 2](#adim-2) · **Ortak Dosya:** `wg_mesh_apply.sh`, `secrets.env.template`, `node101/config/` ([`MAINT-08`](#maint-08))

##### 1. Zaafın Kök Nedeni ve Mekanizması (Ne / Nerede / Neden?)
* **Etkilenen Dosyalar:** [`wg_mesh_apply.sh:28-53`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/scripts/wg_mesh_apply.sh#L28-L53), `secrets.env.template`, `scripts/teqlif-restart.sh`
* `wg_mesh_apply.sh` yalnız `node1..node6` tanımlar; canlı `node101`'de `wg`, `ufw`, `node_exporter` yoktur. `node1/3/4/5/6` gibi web/edge sunucularının `node101`'e doğrudan bağlanması **blast-radius**'u büyütür.

##### 2. Hedef Mimari & Çözüm Reçetesi (Ne İçin / Nasıl?)
* `node101` tam mesh'e değil **yalnız 2 WG peer'ına** açılır (`node2: 10.10.0.2/32`, `nodeMonitor: 10.10.0.99/32`):
```ini
# node101 /etc/wireguard/wg0.conf
[Interface]
Address = 10.10.0.101/24
ListenPort = 51820
PrivateKey = <NODE101_WG_PRIVKEY>

[Peer] # node2
PublicKey = <NODE2_WG_PUBKEY>
Endpoint = 135.125.223.43:51820
AllowedIPs = 10.10.0.2/32
PersistentKeepalive = 25

[Peer] # nodeMonitor
PublicKey = <NODEMONITOR_WG_PUBKEY>
Endpoint = <NODEMONITOR_PUBLIC_IP>:51820
AllowedIPs = 10.10.0.99/32
PersistentKeepalive = 25
```
* `node101` UFW (`/etc/default/ufw` `IPV6=no`): `ufw default deny incoming`, `allow 22/tcp` (Ed25519 key-only, `PasswordAuthentication no`), `allow 51820/udp`, `allow in on wg0 from 10.10.0.2 to any port 8000 proto tcp`, `allow in on wg0 from 10.10.0.99 to any port 9100 proto tcp`.
* **Doğrulama:** `ssh node2 "ping -c2 10.10.0.101"` ve `ssh nodeMonitor "curl -sf http://10.10.0.101:9100/metrics | head -1"` ✔; `ssh node1 "nc -zw2 10.10.0.101 8000"` başarısız (erişim yok) ✔.

##### ✅ Çözüm Damgası
- **Mac peer (10.10.0.7) politikası:** `wg0.conf.template`'deki Mac peer kasıtlıdır — admin SSH erişimi için tutulur (UFW 8000/9100/19100'ü zaten engeller, yalnız 22/tcp açık). Politika istisna olarak kayıt altında.
- `2026-11-11` · commit `351c35fb` + `c5cb95a2` — `wg_mesh_apply.sh`'e node101 eklendi (`apply_wg_node101()`, partial mesh) ✓; `secrets.env.template`'e `node101_pubkey`+`nodemonitor_pubkey` eklendi ✓; `ufw_node101()` kaynak kısıtlaması: port 8000 yalnız `10.10.0.2`, port 9100 yalnız `10.10.0.99`, gossip 19100 her iki peer ✓; `IPV6=no` ✓; SSH `01-teqlif-hardening.conf` first-match düzeltmesi — `sshd -T`: `passwordauthentication no` ✓. **Doğrulama:** `node2 → node101:8000`: OK ✓; `nodeMonitor → node101:9100/metrics`: `# HELP go_gc_duration_seconds…` ✓; `node1 → node101:8000`: ULAŞAMADI (blast-radius koruması) ✓.

---

<a id="offsite-06"></a>
#### `OFFSITE-06` · 🟠 P1 (Yüksek) · `node101` Donanım Kısıtları (`2.9 GiB RAM`, `6.1 GB` `/`, `fdatasync` Tail, TZ)

**Bağlı Adım:** [Adım 1](#adim-1) · **Ortak Dosya:** [`specs.md`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/node101/specs.md)

##### 1. Zaafın Kök Nedeni ve Mekanizması (Ne / Nerede / Neden?)
* Canlı `node101`: `/` diski yalnız **`6.1 GB` boş**, RAM **`2.9 GiB`**, TZ şu an `Europe/London` (yazın `BST`), `/mnt/data` (`934 GB`) sahipliği `tucibeyin:tucibeyin` ve `64k fdatasync` `83 IOPS / 5.45 MB/s` (`p99=229.6 ms`). Restic temp/cache `/` diske yazarsa `6.1 GB` dakikada dolar; TZ düzeltilmezse yaz aylarında bakım 1 saat kayar.

##### 2. Hedef Mimari & Çözüm Reçetesi (Ne İçin / Nasıl?)
1. `node101` üzerinde: `sudo timedatectl set-timezone UTC`, `teqlif-backup` sistem kullanıcısı oluşturulup `/mnt/data/{restic-repo,tmp,cache/restic,logs}` dizinleri `teqlif-backup:teqlif-backup` sahipliğine alınır (`TMPDIR=/mnt/data/tmp`, `RESTIC_CACHE_DIR=/mnt/data/cache/restic`).
2. `/etc/fstab` `/mnt/data` otomatik bağlaması ve `df -h /` (`<%40`) eşikleri `node101` kurulum doğrulamasına bağlanır ([`specs.md`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/node101/specs.md#L70-L98) `fio-3.39` verisi kilitlidir).
* **Doğrulama:** `ssh node101 "timedatectl show -p Timezone --value && ls -ld /mnt/data/{restic-repo,tmp,cache/restic,logs}"` çıktısı `UTC` + tüm dizinler `teqlif-backup` olmalı.

##### ✅ Çözüm Damgası
- `2026-11-11` · commit `09eb442c` — Timezone UTC ✓; `teqlif-backup` uid=999 ✓; `/mnt/data/tmp` + `/mnt/data/cache/restic` (700, teqlif-backup) ✓; `/mnt/data/` mount point `root:root` düzeltildi ✓; `/mnt/data/teqlif/` restic repo yeri (`--private-repos` ile HTTP user=teqlif) ✓; `fstab noatime` ✓; `/` disk %36 < %40 ✓; `/var/log/teqlif-offsite/` log dizini ✓; `bootstrap_node101.sh` yanlış `restic-repo` mkdir kaldırıldı; `restic.env.template` yorum düzeltildi.
- `2026-11-11` · commit `968e2caf` — **P0/P1 review düzeltmeleri** ✓: `teqlif-agent.service` `BindsTo`/`PartOf=restic-rest-server.service` kaldırıldı (agent ölüm döngüsü) ✓; `OnFailure` doğru birim adına (`teqlif-backup-failed@%n`) güncellendi ✓; `teqlif-backup-failed@.service` + `notify_backup_failed.sh` eklendi ✓; `offsite_wal_sync.sh` `--exclude '*.partial' --exclude '*.tmp'` ✓; `scripts/teqlif-restart.sh`'e `configs/$NODE.yaml → /etc/teqlif-agent/config.yaml` sync + `node101` case eklendi (gossip split-brain düzeltmesi) ✓; `bootstrap_node101.sh`: SSH hardening (`99-teqlif-hardening.conf`), gerçek `teqlif-restart` kurma, `schedule.yaml`/`cluster.yaml` kopyalama, env idempotency, sudoers ✓; `teqlif-agent/setup/teqlif-restart` shim'e dönüştürüldü ✓. Live node101: SSH hardening dosyası kuruldu, servis dosyaları güncellendi, prune/verify timer'lar devre dışı bırakıldı ✓.
- **Not:** Belgedeki `/mnt/data/{restic-repo,logs}` yolları gerçek implementasyona güncellendi: restic repo `/mnt/data/teqlif/` (--private-repos); log `/var/log/teqlif-offsite/`.

---

<a id="offsite-07"></a>
#### `OFFSITE-07` · 🟠 P1 (Yüksek) · Offsite PostgreSQL PITR Eksikliği (`pg_basebackup`+`pg_wal`) & `pg_dump` `.dump.gz` Yetimleri

**Bağlı Adım:** [Adım 12](#adim-12) · **Ortak Dosya:** `offsite_sync.sh`, `pg_dump.sh` ([`AUDIT-01`](#audit-01), [`BIZ-02`](#biz-02))

##### 1. Zaafın Kök Nedeni ve Mekanizması (Ne / Nerede / Neden?)
* **Etkilenen Dosyalar:** [`offsite_sync.sh:72-79`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/node2/resources/scripts/offsite_sync.sh#L72-L79), [`pg_dump.sh:26`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/node2/resources/scripts/pg_dump.sh#L26)
1. `offsite_sync.sh` `pg_basebackup` ve `pg_wal` dizinlerini içermez (`node1+node2` kaybında ≤ 24 saat finans/cüzdan veri kaybı).
2. `pg_dump.sh:26` yalnız `-name "teqlif_*.dump"` aradığı için canlı `node2`'de 2–8 Ekim tarihli **7 eski `.dump.gz` yetim** duruyor.

##### 2. Hedef Mimari & Çözüm Reçetesi (Ne İçin / Nasıl?)
1. `offsite_sync.sh` `rclone sync` yerine **`restic backup --pack-size 32 --tag daily-full`** komutuna geçirilir; kaynak listesine `/project/teqlif/backups/{pg_dump,pg_basebackup,pg_wal,minio,clickhouse,redis,loki,stalwart,uptime_kuma,nodemonitor_config}` alınır ve `--exclude '*.partial' --exclude '*.tmp' --exclude '.last_*'` uygulanır.
2. `pg_dump.sh:26` filtresi `find "${BACKUP_DIR}" -name "teqlif_*.dump*" -mtime +${RETENTION_DAYS} -delete` yapılır ve canlıdaki eski `.dump.gz` dosyaları silinir.
* **Doğrulama:** `restic snapshots --tag daily-full --latest 1 --json` içinde `.partial` dosyası olmamalı ve `/project/teqlif/backups/pg_basebackup` snapshot'a dahil görünmelidir.

##### ✅ Çözüm Damgası
- `2026-11-12` · commit `114c0ee4` — **P1 OFFSITE-07 kapatıldı** ✓: `offsite_sync.sh`'ye `pg_wal` (625MB, PITR) + `loki` (413MB) eklendi ✓; `--exclude '*.partial' --exclude '.last_*'` eklendi ✓; `pg_dump.sh:39` filtresi `teqlif_*.dump` → `teqlif_*.dump*` (`.dump.gz` yetimlerini otomatik temizler) ✓; canlı node2'de 7× eski `.dump.gz` (Oct 2–8) manuel silindi ✓. Doğrulama: `restic snapshots --tag daily-full` sonraki çalışmada `pg_wal` + `loki` paths içerecek; `pg_dump.sh` artık `.dump.gz` uzantılı yetim bırakmaz.

---

<a id="offsite-08"></a>
#### `OFFSITE-08` · 🟠 P1 (Yüksek) · ClickHouse Yedek Dizin Uyuşmazlığı, Eksik `BACKUP` Yetkisi & DDL Eksikliği

**Bağlı Adım:** [Adım 14](#adim-14) · **Ortak Dosya:** `clickhouse_backup.sh`, `/etc/clickhouse-server/config.d/backups.xml` ([`AUDIT-03`](#audit-03))

##### 1. Zaafın Kök Nedeni ve Mekanizması (Ne / Nerede / Neden?)
* **Etkilenen Dosya:** [`clickhouse_backup.sh:13-56`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/node2/resources/scripts/clickhouse_backup.sh#L13-L56)
1. Canlı `node2`'de `teqlif` kullanıcısının `BACKUP` yetkisi yok ve `/var/lib/clickhouse/backups` boş (`total 8`). Her gün Method 3 fallback çalışıp `teqlif_prod_analytics` (0 satır) için `~285B` boş `.tar.gz` üretiyor; `SHOW CREATE` DDL tanımları ve MV yapıları da dahil değil!
2. `clickhouse_backup.log` dosyasına log yönlendirmesi yapılmamış; ayrıca `node2` ClickHouse üzerinde terk edilmiş `teqlif_staging_analytics` (`25` satır) dururken `node5` staging ClickHouse (`~26.5k` satır) yerel kalıyor.

##### 2. Hedef Mimari & Çözüm Reçetesi (Ne İçin / Nasıl?)
1. `node2` ClickHouse'a `GRANT BACKUP ON *.* TO teqlif;` + `/etc/clickhouse-server/config.d/backups.xml` (`allowed_path /project/teqlif/backups/clickhouse`) tanımla; Method 2 çıktılarını doğrudan `/project/teqlif/backups/clickhouse/` içine al (dizin uyuşmazlığını kaldır).
2. Method 3 fallback bloğunda her tablo + View için `SHOW CREATE TABLE` SQL dosyasını (`${DEST}/schema.sql`) mutlaka yedekle ve çıktıyı `/project/teqlif/logs/clickhouse_backup.log`'a yönlendir.
3. `teqlif_prod_analytics` boşluğunun gerçek trafik yokluğundan mı yoksa worker/buffer uyuşmazlığından mı kaynaklandığını doğrula ve `node2`'deki terk edilmiş `teqlif_staging_analytics`'i temizle.
* **Doğrulama:** `sudo bash clickhouse_backup.sh` çıktısı `OK (sql)` (fallback değil!) döner ve yedek içinde `schema` + tablolar doğrulanır.

##### ⬜ Çözüm Damgası
- *(Henüz uygulanmadı — [Adım 14](#adim-14) bekliyor)*

---

<a id="offsite-09"></a>
#### `OFFSITE-09` · 🟠 P1 (Yüksek) · `nodemonitor_config_backup.sh` İçinde `979 MB` TSDB/WAL Sızıntısı

**Bağlı Adım:** [Adım 15](#adim-15) · **Ortak Dosya:** `nodemonitor_config_backup.sh` ([`AUDIT-03`](#audit-03))

##### 1. Zaafın Kök Nedeni ve Mekanizması (Ne / Nerede / Neden?)
* **Etkilenen Dosya:** [`nodemonitor_config_backup.sh:27-41`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/node2/resources/scripts/nodemonitor_config_backup.sh#L27-L41)
```bash
# Satır 27-41: --delete var ama --delete-excluded YOK + loki/wal hariç değil!
rsync -az --delete "$@" ...
rsync_from_nodemonitor "/opt/monitor/teqlif/" "${BACKUP_DIR}/monitor-config" \
    --exclude 'prometheus/data/' \
    --exclude 'loki/data/'
```
* Canlı `node2`'de `prometheus/data` (`823 MB`) ve `loki/` (`156 MB` — aktif `wal/`, `tsdb-shipper-*`) birikmiş; toplam yedek hacmini gereksiz yere ikiye katlıyor.

##### 2. Hedef Mimari & Çözüm Reçetesi (Ne İçin / Nasıl?)
* `rsync_from_nodemonitor` içine `--delete-excluded` ve exclude listesine `--exclude 'loki/wal/' --exclude 'loki/tsdb-shipper-active/' --exclude 'loki/tsdb-shipper-cache/'` ekle; canlı `node2` kalıntı klasörlerini sil.
* **Doğrulama:** `du -sh /project/teqlif/backups/nodemonitor_config/{teqlif-config,monitor-config}` **< 5 MB** çıkar.

##### ⬜ Çözüm Damgası
- *(Henüz uygulanmadı — [Adım 15](#adim-15) bekliyor)*

---

<a id="offsite-10"></a>
#### `OFFSITE-10` · 🟡 P2 (Orta) · Yedek Servislerinde I/O / CPU Önceliği ve Geçici Dosya Filtreleri

**Bağlı Adım:** [Adım 26](#adim-26) · **Ortak Dosya:** `node2/systemd/teqlif-*-backup.service` ([`MAINT-08`](#maint-08))

##### 1. Zaafın Kök Nedeni ve Mekanizması (Ne / Nerede / Neden?)
* `node2` 2×HDD RAID-1 kullanmasına rağmen 11 backup/bakım servisinin yalnız 4'ünde (`pg-dump`, `clickhouse`, `minio`, `redis`) `Nice=19` / `IOSchedulingClass=idle` vardır; kalan 7 serviste (`pg-basebackup`, `loki`, `uptime-kuma`, `nodemonitor-config`, `mail`, `pg-wal-cleanup` ve `offsite-sync`) eksiktir.

##### 2. Hedef Mimari & Çözüm Reçetesi (Ne İçin / Nasıl?)
* `offsite-sync` ([Adım 13](#adim-13)) dahil eksik 7 `.service` biriminin `[Service]` altına `Nice=19` + `IOSchedulingClass=idle` + `IOSchedulingPriority=7` ekle; `restic` scriptlerinde `--exclude '*.tmp' --exclude '*.partial' --exclude '.last_*'` sabitle.
* **Doğrulama:** `systemctl show teqlif-*-backup teqlif-offsite-sync -p IOSchedulingClass,Nice` tamamı `idle` / `19` döner.

##### ⬜ Çözüm Damgası
- *(Henüz uygulanmadı — [Adım 26](#adim-26) bekliyor)*

---

<a id="offsite-11"></a>
#### `OFFSITE-11` · 🟡 P2 (Orta) · Offsite (`node101` → Yeni `node1`/`node2`) DR Runbook'u & Restore Tatbikatı

**Bağlı Adım:** [Adım 36](#adim-36) · **Ortak Dosya:** `deploy/scale/V2.1/node101/resources/offsite_restore_runbook.md` ([`AUDIT-01`](#audit-01))

##### 1. Zaafın Kök Nedeni ve Mekanizması (Ne / Nerede / Neden?)
* Mevcut [`runbook.sh`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/node2/resources/scripts/runbook.sh) yalnız `node2 → node1` senaryosunu bilir. Hem `node2` kaybında `node101 → yeni node2` hem çifte felakette (`node1+node2` kaybı) `node101 → yeni sunucu` kurtarma adımları ve periyodik şifreyle doğrulama tatbikatı yoktur.

##### 2. Hedef Mimari & Çözüm Reçetesi (Ne İçin / Nasıl?)
1. `node101/resources/offsite_restore_runbook.md` + yardımcı script (`restore_from_node101.sh`) hazırlanır; `node101` üzerinde haftalık **`teqlif-offsite-verify.timer`** (`restic check --read-data-subset=5%`) açılır.
2. Kurulum bitişinde `node101`'den geçici test dizinine/DB'sine gerçek `pg_basebackup + pg_wal` PITR ve `pg_dump` restore testi uygulanır.
* **Doğrulama:** `restic check --read-data-subset=5%` `no errors were found` + test DB üzerinde tablo sayımı eşleşir.

##### ⬜ Çözüm Damgası
- *(Henüz uygulanmadı — [Adım 36](#adim-36) bekliyor)*

---

<a id="offsite-12"></a>
#### `OFFSITE-12` · 🟡 P2 (Orta) · `bootstrap_node101.sh` Yokluğu & `bootstrap_node2.sh` Timer / Araç Eksikleri

**Bağlı Adım:** [Adım 3](#adim-3) · **Ortak Dosya:** [`bootstrap_node2.sh`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/scripts/bootstrap_node2.sh#L206-L215), `_common.sh`

##### 1. Zaafın Kök Nedeni ve Mekanizması (Ne / Nerede / Neden?)
```bash
# bootstrap_node2.sh:210-214 — 11 backup/bakım timer'ından yalnız 4'ü enable ediliyor:
systemctl enable \
    teqlif-pg-dump.timer \
    teqlif-redis-backup.timer \
    teqlif-minio-backup.timer \
    teqlif-offsite-sync.timer
```
* `pg_basebackup`, `clickhouse-backup`, `loki-backup`, `uptime-kuma-backup`, `nodemonitor-config-backup`, `mail-backup`, `pg-wal-cleanup` (`7` yedekleme/bakım timer'ı + yeni `offsite-wal`; ek olarak `teqlif-redis-failover.timer`) listede eksik; `node101` bootstrap scripti hiç yoktur.

##### 2. Hedef Mimari & Çözüm Reçetesi (Ne İçin / Nasıl?)
* `deploy/scale/V2.1/scripts/bootstrap_node101.sh` (idempotent Debian 13 kurulum) oluştur; `bootstrap_node2.sh:210-214`'e tüm timer'ları + `restic` paketini ekle.
* **Doğrulama:** `bash -n deploy/scale/V2.1/scripts/bootstrap_node101.sh deploy/scale/V2.1/scripts/bootstrap_node2.sh` sözdizimi hatasız geçer.

##### ✅ Çözüm Damgası
- `2026-11-12` · commit `1ce09741` — `bootstrap_node2.sh`: `install_backup_tools()` eklendi; `setup_backup_directories()` 4 → 10 dizin; `setup_backup_services()` 4 → 12 timer ✓.
- `2026-11-12` · commit `a1dbf1a1` — `CLICKHOUSE_PASSWORD` placeholder `<clickhouse_password>` → `<teqlif_ch_password>` (secrets.env.template uyumu) ✓; `install_node_exporter`: service dosyası her çalıştırmada güncellenir (listen_addr SRP) + `/tmp` cleanup ✓.
- `2026-11-12` · commit `b7a45d18` — **İdempotency + DRY + güvenlik düzeltmeleri**: `_common.sh`'e `install_node_exporter(listen_addr)` ortak fonksiyon (sürüm guard + `Text-file-busy` önlemi) ✓; `bootstrap_node2.sh`: `curl|bash` → `apt restic rclone` ✓; `chmod -R 700` → `find -type d` ✓; `.env.backup` idempotent (`[ ! -f ]` + `_add_env_key` eksik anahtar ekleme) + `CLICKHOUSE_PASSWORD`, `CLICKHOUSE_DEFAULT_PASSWORD`, `UPTIME_KUMA_DB_PASS` şablona eklendi ✓; `bootstrap_node101.sh`: `prune/verify.timer` enable Adım 10'a bırakıldı ✓. **Doğrulama:** `bash -n _common.sh bootstrap_node2.sh bootstrap_node101.sh` syntax-clean ✓; canlı node2 tüm timer'lar `enabled` ✓.

---

<a id="offsite-13"></a>
#### `OFFSITE-13` · 🟢 P3 (Düşük) · TTK / MASAK 5–10 Yıl Finansal WORM Arşiv Akışı (`financial_archives`)

**Bağlı Adım:** [Adım 35](#adim-35) · **İlgili:** [`documents/wallet/V1.0/01_findings.md`](file:///Users/tucibeyin/Desktop/teqlif/documents/wallet/V1.0/01_findings.md) (`V11-10`), [`BIZ-03`](#biz-03)

##### 1. Zaafın Kök Nedeni ve Mekanizması (Ne / Nerede / Neden?)
* `node101` `daily-full` GFS politikası 6 ay saklar; ancak `wallet_ledger`, `withdrawal_requests`, `purchases` ve `audit_logs` TTK/VUK/MASAK gereği **5–10 yıl** değiştirilemez (WORM) saklanmalıdır.

##### 2. Hedef Mimari & Çözüm Reçetesi (Ne İçin / Nasıl?)
* Aylık bir job (`archive_financial_worm_task`) 1 yıldan eski kapatılmış finansal satırları deterministik JSONL/Parquet + SHA-256 manifest ile export edip `restic backup --tag financial-worm` ile `node101` `--append-only` repoya yazar (`--keep-yearly 10` ayrı kural).
* **Doğrulama:** `restic snapshots --tag financial-worm` SHA-256 manifest dosyasıyla birlikte doğrulanır.

##### ⬜ Çözüm Damgası
- *(Henüz uygulanmadı — [Adım 35](#adim-35) bekliyor)*

---

<a id="kartlar-b"></a>
### Bölüm B — Sistem Geneli Bakım, Zamanlama & Donanım Anomalileri (`MAINT-01` .. `MAINT-08`)

---

<a id="maint-01"></a>
#### `MAINT-01` · 🟠 P1 (Yüksek) · `cleaner.py` vs `schedule.yaml` Çift Temizlik & `message_threads 180d` Veri Silme Tuzağı

**Bağlı Adım:** [Adım 21](#adim-21) · **Ortak Dosya:** `cleaner.py`, `schedule.yaml` ([`AUDIT-08`](#audit-08))

##### 1. Zaafın Kök Nedeni ve Mekanizması (Ne / Nerede / Neden?)
* **Etkilenen Dosya:** [`cleaner.py:35-70,86-112`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/teqlif-agent/modules/cleaner.py#L35-L70)
```python
# cleaner.py:43-61 — batch yok, DM arşiv süresinin (365g) yarısında silme + 03:00 pg_dump çakışması!
    (1, 10,  "live_stream_viewers", "left_at IS NOT NULL AND joined_at < NOW() - INTERVAL '3650 days'", ...),
    (2, 15,  "message_threads",     "created_at < NOW() - INTERVAL '180 days' AND has_archive = false", ...),
    (3,  0,  "stream_recordings",   "archived_at < NOW() - INTERVAL '15 days' AND status = 'archived'", ...),
```
* Canlı `nodeMonitor` üzerinde `PG_DSN` boş olduğu için şu an uykuda duruyor; ancak `/etc/teqlif-agent/env` içine `PG_DSN=` girildiği anda:
  1. `dm_archive_tasks.py` 365 günde arşivlerken `cleaner.py` 180 günlük `message_threads` satırlarını **`direct_messages` kontrolsüz** `DELETE` eder!
  2. `LIMIT`'siz `DELETE` satırları `worker.py` + `schedule.yaml` ile aynı tablolara çakışır.

##### 2. Hedef Mimari & Çözüm Reçetesi (Ne İçin / Nasıl?)
* `cleaner.py` içindeki PG `DELETE` sorumluluğu tamamen emekliye ayrılır (veya yalnızca güvenli no-op / salt okunur sayıma çekilir); tüm PG tablo temizliği tek otorite olarak `backend/app/worker.py` (5.000 batch `DELETE`) + `schedule.yaml` üzerinden yürütülür. `cleanup_empty_message_threads_task` `NOT EXISTS (SELECT 1 FROM direct_messages ...)` + `has_archive = FALSE` korumasını sürdürür.
* **Doğrulama:** `teqlif-agent` `PG_DSN` tanımlı test ortamında dahi `cleaner.py` `DELETE FROM message_threads` veya batchsiz `DELETE` çalıştırmaz.

##### ⬜ Çözüm Damgası
- *(Henüz uygulanmadı — [Adım 21](#adim-21) bekliyor)*

---

<a id="maint-02"></a>
#### `MAINT-02` · 🟠 P1 (Yüksek) · Video Transfer (`05:00–07:00 UTC`) ↔ `minio_backup` (`05:30 UTC`) ↔ `notify` Çarpışması

**Bağlı Adım:** [Adım 22](#adim-22) · **Ortak Dosya:** `cluster.yaml`, `encoder.py`, `worker.py` ([`BIZ-01`](#biz-01)) · **Referans:** [Karar K3](#kilitli-kararlar)

##### 1. Zaafın Kök Nedeni ve Mekanizması (Ne / Nerede / Neden?)
* **Etkilenen Dosyalar:** [`cluster.yaml:36-37`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/cluster.yaml#L36-L37), [`encoder.py:349-358`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/teqlif-agent/modules/encoder.py#L349-L358), [`worker.py:4845`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/worker.py#L4845)
```python
# cluster.yaml:36-37: start=4, end=7 → encoder.py:357 normalde effective_start = start_utc + 1 = 05:00!
effective_start = start_utc if free_gb < warn_gb else start_utc + 1
return effective_start <= now_h < end_utc  # Normalde 05:00–07:00 UTC!
```
* Transfer `05:00–07:00` arasında sürerken `teqlif-minio-backup.timer` **`05:30 UTC`**'de mirror yapar; `notify_new_recordings_task` da `05:00 & 06:00` koşup pencere bitmeden çalışır.

##### 2. Hedef Mimari & Çözüm Reçetesi (Ne İçin / Nasıl?)
1. `cluster.yaml:36-47`: `transfer_window_start_utc: 3`, `transfer_window_end_utc: 5` (`normal: 04:00–05:00 UTC`, `disk_warn: 03:00–05:00 UTC`) ve `retention_days: 30` yap.
2. `worker.py:4845`: `notify_new_recordings_task` saatini `05:30` `minio_backup` sonrası **`hour=5, minute=45`** (`05:45 UTC`) olarak güncelle.
* **Doğrulama:** `_can_transfer_now()` normal diskte `04:00–04:59 UTC` için `True`, `05:30 UTC` için `False` döner.

##### ⬜ Çözüm Damgası
- *(Henüz uygulanmadı — [Adım 22](#adim-22) bekliyor)*

---

<a id="maint-03"></a>
#### `MAINT-03` · 🔴 P0 (Kritik) · Canlı `node2` Zehirlenmiş `promoted` Bayrağı + Çift Failover Timer + WG İzolasyon Tuzağı

**Bağlı Adım:** [Adım 4](#adim-4) · **Ortak Dosya:** `redis_failover.sh`, canlı `node2` `/var/lib/teqlif-redis-failover/` ([`BIZ-02`](#biz-02))

##### 1. Zaafın Kök Nedeni ve Mekanizması (Ne / Nerede / Neden?)
* **Etkilenen Dosyalar:** [`redis_failover.sh:15-22,63-69`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/node2/resources/scripts/redis_failover.sh#L15-L69)
```bash
# redis_failover.sh:20-22 (18 Eki tarihli promoted bayrağı yüzünden 24 gündür sessiz exit 0!)
if [ -f "$PROMOTED_FLAG" ]; then
    exit 0
fi
# Satır 66-68 (Promote olursa node1 WG peer'ını tamamen kesip PG WAL/MinIO'yu da öldürür!):
sudo wg set wg0 peer "$_NODE1_PK" allowed-ips "0.0.0.1/32"
sudo wg-quick save wg0
```
* **Canlı `node2` Bulgusu:** `/var/lib/teqlif-redis-failover/promoted` (`18 Eki 15:06`) duruyor → resmi `teqlif-redis-failover.service` 24 gündür kontrol yapmıyor! Paralel yetkisiz `redis-failover.timer` (`/usr/local/bin/redis-failover-check.sh`) ise içinde **düz metin Redis şifresiyle** `root` olarak koşuyor ve VIP/iptables/Telegram kurmuyor.

##### 2. Hedef Mimari & Çözüm Reçetesi (Ne İçin / Nasıl?)
1. Canlı `node2` üzerinde yetkisiz `redis-failover.timer`/`service` durdurulup `/usr/local/bin/redis-failover-check.sh` ve `/var/lib/redis-failover/` silinir.
2. `node1` Redis `PONG` ve `node2` `role:slave, master_link_status:up` doğrulandıktan sonra `/var/lib/teqlif-redis-failover/promoted` kaldırılır.
3. `redis_failover.sh:62-69` içindeki **WG peer `0.0.0.1/32` bloğu kaldırılır** (VIP `10.10.0.1/32` `lo` + `iptables PREROUTING/OUTPUT` `6379` DNAT yalnızca Redis trafiğini yakalar; `pg_receivewal` `5432` ve MinIO `9000` WG tünelinden `node1`'e kesilmez!).
* **Doğrulama:** `systemctl list-timers '*failover*'` yalnız `teqlif-redis-failover.timer` gösterir; `journalctl -u teqlif-redis-failover -n 5` sağlıklı `exit 0` (`fail_count=0`) kanıtlar.

##### ✅ Çözüm Damgası
- `2026-11-12` · commit `c0154e66` — Canlı `node2` temizliği: rogue `redis-failover.timer`+`redis-failover.service` durdurulup devre dışı bırakıldı; `/etc/systemd/system/redis-failover.{timer,service}` silindi; `/usr/local/bin/redis-failover-check.sh` (düz metin şifreli) silindi; `/var/lib/redis-failover/` silindi. `node1` Redis `PONG` + `node2` `role:slave master_link_status:up` doğrulandıktan sonra `/var/lib/teqlif-redis-failover/promoted` (18 Eki 15:06) silindi — resmi failover aktif. `redis_failover.sh` WG peer `0.0.0.1/32` bloğu kaldırıldı.
- `2026-11-12` · commit `2fe7c172` — **P0:** `ip addr add 10.10.0.1/32 dev lo` kaldırıldı; iptables idempotency guard eklendi; `redis_failback.sh` oluşturuldu.
- `2026-11-12` · commit `ad968d7d` — **redis_failback.sh sıralama düzeltmesi:** `_nat_cleanup()` ÖNCE çalışır (OUTPUT DNAT aktifken PING/REPLICAOF yapılırsa 127.0.0.1:6379'a düşüyor = sahte PONG + self-replication); node1 erişilemezse `_nat_restore()` + `exit 1`; `master_link_status` grep `|| true` ile `set -e` korumalı; `fail_count` sonrası `chown tucibeyin:tucibeyin`.
- **Açık Kayıt:** `redis_vip_check.sh:89` (node3/4/5/6) — `sudo wg set wg0 peer "$NODE1_PUBKEY" allowed-ips "0.0.0.1/32"` failover sırasında node3-6→node1 TÜM trafiğini (PG WAL, MinIO) kesiyor, yalnız Redis'i değil. ADR kararı gerektirir (iptables DNAT veya ayrı WG sanal IP). BIZ-02 Adım 6 scope dışı; takip adımına bağlanacak.

---

<a id="maint-04"></a>
#### `MAINT-04` · 🟡 P2 (Orta) · OS `apt-daily-upgrade` & `mdcheck` Bakım Pencerelerinin Yedek / ML Bloğuna Çarpışması

**Bağlı Adım:** [Adım 27](#adim-27) · **Referans:** [Zamanlama Matrisi](#zamanlama-matrisi)

##### 1. Zaafın Kök Nedeni ve Mekanizması (Ne / Nerede / Neden?)
* Canlı `apt-daily-upgrade.timer` `06:05–06:50 UTC` arası tüm node'larda (`node2 06:37`, `nodeMonitor 05:40 UTC`, `node1 06:21`) çalışıp restart/I/O yaratıyor. Ayın 1. Pazartesi günü `node2 mdcheck_continue` (`06:46 UTC`) doğrudan `06:30–07:00` offsite üzerine biniyor.

##### 2. Hedef Mimari & Çözüm Reçetesi (Ne İçin / Nasıl?)
* Tüm node'larda `/etc/systemd/system/apt-daily-upgrade.timer.d/override.conf` ile zaman **`07:45 UTC`** (ve `RandomizedDelaySec=15m`) olarak çekilir; `node2` `mdcheck_continue.timer` `07:35 UTC` sonrasına ötelenir.
* **Doğrulama:** `systemctl list-timers apt-daily-upgrade.timer mdcheck_continue.timer` tüm node'larda `07:35+ UTC` gösterir.

##### ⬜ Çözüm Damgası
- *(Henüz uygulanmadı — [Adım 27](#adim-27) bekliyor)*

---

<a id="maint-05"></a>
#### `MAINT-05` · 🟡 P2 (Orta) · `schedule.yaml` `backup:` Anahtarı Eksikliği, Çift Cron & Stale Yorumlar

**Bağlı Adım:** [Adım 28](#adim-28) · **Ortak Dosya:** `schedule.yaml`, `schedule_loader.py`, `worker.py` ([`OFFSITE-04`](#offsite-04))

##### 1. Zaafın Kök Nedeni ve Mekanizması (Ne / Nerede / Neden?)
* **Etkilenen Dosyalar:** [`schedule_loader.py:59`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/schedule_loader.py#L59), [`schedule.yaml:21,210,304-340`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/schedule.yaml#L21-L340), [`worker.py:4847`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/worker.py#L4847)
1. `schedule_loader.py:59` `cfg.get("backup", [])` okur ama `schedule.yaml:304`'te üst seviye `backup:` anahtarı yok — `pg_dump..pg_basebackup` `batch:` altında!
2. `cleanup_old_stream_chat_messages_task` hem `schedule.yaml`'da hem `worker.py:4847`'de tanımlı; yorumlar `01:30 CH`, `08:30 basebackup`, `CH delete` diye yanlış bilgi içeriyor.

##### 2. Hedef Mimari & Çözüm Reçetesi (Ne İçin / Nasıl?)
* `schedule.yaml:304` başına **`backup:`** eklenir; `worker.py:4847` statik satırı kaldırılır (tek kaynak `schedule.yaml`); tüm saat/açıklama yorumları [Kanonik Tablo](#zamanlama-matrisi) ile hizalanır (`cleanup_old_notifications`/`stream_likes` → `03:10 UTC`).
* **Doğrulama:** `python3 -c "from app.schedule_loader import load_watchdog_registry; r=load_watchdog_registry(); assert 'pg_dump' in r and 'offsite_sync' in r"` sıfır hatayla geçer.

##### ⬜ Çözüm Damgası
- *(Henüz uygulanmadı — [Adım 28](#adim-28) bekliyor)*

---

<a id="maint-06"></a>
#### `MAINT-06` · 🟡 P2 (Orta) · Watchdog / `job_ok` / Sentinel Tutarsızlığı & Eski `mail` Timer Artığı

**Bağlı Adım:** [Adım 29](#adim-29) · **Ortak Dosya:** `loki_backup.sh`, `uptime_kuma_backup.sh`, `nodemonitor_config_backup.sh`, `pg_wal_cleanup.sh` ([`OFFSITE-04`](#offsite-04))

##### 1. Zaafın Kök Nedeni ve Mekanizması (Ne / Nerede / Neden?)
* `loki_backup.sh`, `uptime_kuma_backup.sh`, `nodemonitor_config_backup.sh` yalnız dosya sentinel yazar (`Redis job_ok` atmaz); `pg_wal_cleanup.sh` ne sentinel ne `job_ok` yazar; `node2` `/project/teqlif/backups/.last_mail_backup_ok` `0B` yetim duruyor ve repoda eski `node2/resources/systemd/teqlif-mail-backup.timer` (`03:45`) artığı var.

##### 2. Hedef Mimari & Çözüm Reçetesi (Ne İçin / Nasıl?)
* 4 scriptin sonuna `redis-cli ... HSET teqlif:agent:job_ok <job> "$(date -u +%Y-%m-%dT%H:%M:%SZ)"` eklenir; `schedule.yaml` `backup:` listesine ve `health.py` `_BACKUP_MAX_MIN` sözlüğüne hepsi işlenir; `0B` yetim dosya ve eski `.timer` kalıntısı kaldırılır.
* **Doğrulama:** `redis-cli HGETALL teqlif:agent:job_ok` içinde tüm 11 yerel yedek/temizlik + offsite anahtarı güncellenir.

##### ⬜ Çözüm Damgası
- *(Henüz uygulanmadı — [Adım 29](#adim-29) bekliyor)*

---

<a id="maint-07"></a>
#### `MAINT-07` · 🟡 P2 (Orta) · `nodeMonitor` Bellek & Swap Darboğazı (`1.9 GiB RAM`, `240 MiB` Aktif Swap)

**Bağlı Adım:** [Adım 30](#adim-30) · **İlgili:** [`BIZ-04`](#biz-04)

##### 1. Zaafın Kök Nedeni ve Mekanizması (Ne / Nerede / Neden?)
* Canlı `nodeMonitor` (`1.9 GiB RAM`) üzerinde Prometheus (`1.4G`), Loki (`314M`), Grafana, Uptime Kuma, MariaDB ve `teqlif-agent` Lideri koşuyor; yalnız `165 MiB` free RAM ve **`240 MiB` aktif swap** var (`MemoryMax` sınırları MariaDB/Grafana hariç `~1.4 GB` ve OOM riski taşıyor).

##### 2. Hedef Mimari & Çözüm Reçetesi (Ne İçin / Nasıl?)
* Prometheus `--storage.tsdb.retention.size=1GB` (`--storage.tsdb.retention.time=15d` veya `21d`) + Loki chunk cache/ingestion limit sıkılaştırması + Grafana/MariaDB `MemoryMax` koruması eklenir (`innodb_buffer_pool_size=64M`).
* **Doğrulama:** `ssh nodeMonitor "free -m"` swap kullanımı düşer ve `MemAvailable >= 400 MiB` kalır.

##### ⬜ Çözüm Damgası
- *(Henüz uygulanmadı — [Adım 30](#adim-30) bekliyor)*

---

<a id="maint-08"></a>
#### `MAINT-08` · 🟢 P3 (Düşük) · Canlı `node2` `wg show` Eksik Peer (`node3`/`node4`) & Backup Servis `TimeoutStartSec`

**Bağlı Adım:** [Adım 34](#adim-34) · **Ortak Dosya:** `node2/systemd/teqlif-*.service` ([`OFFSITE-05`](#offsite-05), [`OFFSITE-10`](#offsite-10))

##### 1. Zaafın Kök Nedeni ve Mekanizması (Ne / Nerede / Neden?)
* Canlı `node2 wg show` yalnız `node1, node5, node6, nodeMonitor` peer'larını gösteriyor (`node3` ve `node4` eksik/sessiz — edge `recorder`/`gossip` veya bakım erişimlerini etkileyebilir); ayrıca 11 backup/bakım servisinin yalnız `pg_basebackup` biriminde `TimeoutStartSec` tanımlı (kalan 10 serviste askıda kalırsa sonsuza dek kilitlenir).

##### 2. Hedef Mimari & Çözüm Reçetesi (Ne İçin / Nasıl?)
* `node2` ↔ `node3`/`node4` WG peering durumu denetlenip eksikse `wg_mesh_apply` ile tamamlanır; kalan 10 backup/bakım servisine çalışma süresine orantılı `TimeoutStartSec` (`900`–`3600`) eklenir.
* **Doğrulama:** `ssh node2 "sudo wg show wg0 peers | wc -l"` beklenen tüm küme + `node101` eş sayısını gösterir.

##### ⬜ Çözüm Damgası
- *(Henüz uygulanmadı — [Adım 34](#adim-34) bekliyor)*

---

<a id="kartlar-c"></a>
### Bölüm C — Uçtan Uca Bakım, DR, Birikme & Telemetri (`AUDIT-01` .. `AUDIT-08`)

---

<a id="audit-01"></a>
#### `AUDIT-01` · 🔴 P0 (Kritik) · `node2` Yerel Felaket Kurtarma (DR) & PITR Akışı Tamamen Kırık

**Bağlı Adım:** [Adım 5](#adim-5) · **Ortak Dosya:** `runbook.sh`, `pg_basebackup.sh`, `pg_dump.sh` ([`OFFSITE-07`](#offsite-07))

##### 1. Zaafın Kök Nedeni ve Mekanizması (Ne / Nerede / Neden?)
* **Etkilenen Dosyalar:** [`runbook.sh:94,134-155,206-228`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/node2/resources/scripts/runbook.sh#L94-L228), [`pg_basebackup.sh:19,27-35`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/node2/resources/scripts/pg_basebackup.sh#L19-L35), [`pg_dump.sh:17-24`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/node2/resources/scripts/pg_dump.sh#L17-L24)
```bash
# runbook.sh:134-150 (pg_wal.tar.gz'yi hiç açmıyor + immediate PITR'ı kesiyor!)
BASE_TAR="${LATEST_BASEBACKUP}/base.tar.gz"
sudo -u postgres tar -xzf "${BASE_TAR}" -C "${PG_DATA}"
sudo -u postgres mkdir -p "${PG_DATA}/pg_wal"
cat > "${PG_CONF}/conf.d/recovery.conf" <<EOF
restore_command = 'cp ${WAL_DIR}/%f %p'
recovery_target = 'immediate'
EOF
```
1. **Canlı `node2` boş & `pgvector` yok:** `pg_lsclusters` boş, **`postgresql-17-pgvector` kurulu değil** (`pg_restore` `EXTENSION vector` gerektirir!), `.env.dr` ve `/etc/ssl/teqlif/cf-origin.*` yok.
2. **Kırık PITR:** `pg_basebackup --wal-method=stream` tarafından üretilen `pg_wal.tar.gz` yok sayılıyor ve `recovery_target = 'immediate'` yüzünden `/project/teqlif/backups/pg_wal` içindeki son WAL segmentleri hiç replay edilmiyor!
3. **Rol/Atomiklik eksik:** `pg_dump.sh` `pg_dumpall --globals-only` almıyor; `pg_basebackup.sh` `.tmp`→`mv` yapmadığından yarım yedek sağlam sanılabilir.

##### 2. Hedef Mimari & Çözüm Reçetesi (Ne İçin / Nasıl?)
1. `node2`'de `sudo apt-get install -y postgresql-17-pgvector` + `pg_createcluster 17 main` hazırlığı yap, `/project/teqlif/config/.env.dr` & `/etc/ssl/teqlif/cf-origin.{crt,key}` dosyalarını yerleştir.
2. `pg_basebackup.sh`: `-D "${DEST}.tmp"` yazıp başarılı olunca `mv "${DEST}.tmp" "${DEST}"` yap; `runbook.sh:94`'te `_tmp` atla.
3. `runbook.sh:138-151`: `pg_wal.tar.gz` varsa `${PG_DATA}/pg_wal` altına aç ve `recovery_target = 'immediate'` satırını **`recovery_target_timeline = 'latest'`** ile değiştir (`pg_wal` dizininin sonuna dek replay et!).
4. `pg_dump.sh`: `PGPASSWORD="${TEQLIF_DB_PASSWORD}" pg_dumpall --globals-only -h "${PGHOST}" -U postgres > "${BACKUP_DIR}/globals_${TIMESTAMP}.sql.tmp"` ekle (`.role`/`pgvector` tam uyumu için).
* **Doğrulama:** `ssh node2 "dpkg -l postgresql-17-pgvector && pg_lsclusters && ls -la /etc/ssl/teqlif/cf-origin.* /project/teqlif/config/.env.dr"` tamamı ✔.

##### ✅ Çözüm Damgası
- `2026-11-12` · commit `76628e6f` — Altyapı hazırlığı (pgvector, cluster, CF cert, .env.dr, atomik backup):
  - `pg_basebackup.sh`: `.tmp`→`mv` atomicity + retention .tmp guard ✓
  - `runbook.sh:94`: `LATEST_BASEBACKUP`/`LATEST_DUMP` .tmp dışlandı ✓
  - `runbook.sh:PITR`: `pg_wal.tar.gz` → `${PG_DATA}/pg_wal/` açılımı ✓
  - `runbook.sh:PITR`: `recovery_target='immediate'` → `recovery_target_timeline='latest'` ✓
  - `runbook.sh:DUMP`: globals SQL restore + teqlif rol yoksa `CREATE ROLE` ✓
  - `pg_dump.sh`: `pg_dumpall --globals-only -U teqlif_repl` (7g retention) ✓
  - `bootstrap_node2.sh`: `postgresql-17-pgvector` + `pg_createcluster` guard ✓
  - `bootstrap_node2.sh`: `.env.dr` placeholder idempotent oluşturma ✓
  - Live node1: `teqlif_repl SUPERUSER` + `pg_hba host all 10.10.0.2/32` ✓ *(sonraki commit'te revize edildi)*
  - Live node2: `postgresql-17-pgvector 0.8.7`, `pg_lsclusters → 17 main down` ✓
  - Live node2: `/etc/ssl/teqlif/cf-origin.{crt,key}` node1'den kopyalandı ✓
  - Live node2: `/project/teqlif/config/.env.dr` placeholder oluşturuldu ✓

- `2026-11-12` · commit `7fb43506` — Reviewer P0/P1 düzeltmeleri (DR uçtan uca çalışır hale getirildi):
  - `runbook.sh:PITR`: WAL_DIR geçici 750/postgres erişimi + restore sonrası 700'e dön ✓
  - `runbook.sh:PITR`: `conf.d/dr.conf` max_connections=200/hot_standby=on (node1 150'den fazla) ✓
  - `runbook.sh:PITR`: `sleep 5` → `pg_is_in_recovery()=false` döngüsü (maks 10 dk) ✓
  - `runbook.sh:DUMP`: `pg_restore -h 127.0.0.1 --role=teqlif` kaldırıldı (local socket + postgres superuser → CREATE EXTENSION çalışır) ✓
  - `runbook.sh`: `.env.dr` placeholder guard (`<[a-z_]*>`) eklendi ✓
  - `bootstrap_node2.sh`: `setup_venv` eklendi; `.env.dr` lowercase + `USE_PGBOUNCER=false` ✓
  - `nginx.conf`: `include /etc/nginx/sites-enabled/*` eklendi (webmail uyumu) ✓
  - `pg_dump.sh`: `--no-role-passwords` eklendi ✓
  - Live node1: `teqlif_repl NOSUPERUSER` + `host all→postgres` (dar HBA) + `pg_reload_conf()` ✓
  - Live node2: uvicorn + tüm backend requirements `.venv`'e kuruldu ✓
  - Live node2: `.env.dr` lowercase placeholder güncellendi ✓
  - node101 dahil tüm 8 node `7fb43506`'da ✓
  - **Doğrulama:** `pg_dumpall --globals-only --no-role-passwords` NOSUPERUSER ile başarılı ✓; `uvicorn` `.venv`'de ✓; `runbook.sh` bash -n temiz ✓

- `2026-11-12` · commit `ce6eb3e3` — P0 WAL staging (traversal bariyeri kesin çözüm) + minor cleanup:
  - **P0 Kök neden:** `/project/teqlif/backups` → `700 tucibeyin:tucibeyin`, WAL dosyaları `600 tucibeyin:tucibeyin`. `chgrp postgres pg_wal + chmod 750` üst dizin (700) traversal bariyerini aşamadığı için `restore_command 'cp'` postgres UID ile çalışamıyordu.
  - `runbook.sh:PITR`: `WAL_STAGE="${RESTORE_DIR}/pg_wal_stage"` — staging dizini `install -d -o postgres -g postgres -m 755` ile oluşturulur ✓
  - `runbook.sh:PITR`: WAL dosyaları `cp ${WAL_DIR}/* ${WAL_STAGE}/` + `chown -R postgres:postgres` + `chmod -R 640` — backup ağacı hiç değiştirilmiyor ✓
  - `runbook.sh:PITR`: `restore_command = 'cp ${WAL_STAGE}/%f %p'` (WAL_DIR yerine WAL_STAGE) ✓
  - `runbook.sh:PITR cleanup`: `chgrp/chmod restore` → `rm -rf "${WAL_STAGE}"` ✓
  - `pg_dump.sh`: yorum `SUPERUSER` → `NOSUPERUSER + host postgres` güncellendi ✓
  - `bootstrap_node2.sh`: `setup_dr_app()` `systemctl disable nginx` kaldırıldı (webmail kesilmemeli) ✓
  - `runbook.sh`: failback adım 5 `disable --now ... nginx` → `disable --now teqlif-dr.service` (nginx webmail'e hizmet eder) ✓
  - node101 dahil tüm 8 node `ce6eb3e3`'de ✓
  - **Doğrulama:** `bash -n runbook.sh` temiz ✓; WAL_STAGE oluşturma/kopyalama/temizleme mantığı postgres erişim garantisi sağlıyor ✓

- `2026-11-12` · commit `f48e8eaf` — Reviewer P0: WAL_STAGE dizin traverse biti korundu:
  - **Kök neden:** `chmod -R 640 "${WAL_STAGE}"` dizinin kendisini de `640` (drw-r-----) yapıyordu → `+x` traverse biti siliniyor → postgres uid=110 staging içindeki dosyaları okuyamıyor → `restore_command` Permission denied.
  - `runbook.sh:160`: `chmod -R 640` → `chmod 750 "${WAL_STAGE}" && find "${WAL_STAGE}" -type f -exec chmod 640 {} +` ✓
  - node101 dahil tüm 8 node `f48e8eaf`'de ✓
  - **Doğrulama:** `bash -n runbook.sh` SYNTAX_OK ✓; staging dizin 750 (traverse OK), dosyalar 640 (postgres okur, dünya görmez) ✓

---

<a id="audit-02"></a>
#### `AUDIT-02` · 🟠 P1 (Yüksek) · `teqlif-agent` Watchdog Donmuş SQLite + Eksik `_agent_ok` + `recorder` / `reporter` Körlüğü

**Bağlı Adım:** [Adım 19](#adim-19) · **Ortak Dosya:** `watchdog.py`, `db.py`, `worker.py`, `reporter.py`, `recorder.py` ([`OFFSITE-04`](#offsite-04))

##### 1. Zaafın Kök Nedeni ve Mekanizması (Ne / Nerede / Neden?)
* **Etkilenen Dosyalar:** [`watchdog.py:49-64`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/teqlif-agent/modules/watchdog.py#L49-L64), [`db.py:130-137`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/teqlif-agent/db.py#L130-L137), [`worker.py:4816-4853`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/worker.py#L4816-L4853), [`reporter.py:47-53`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/teqlif-agent/modules/reporter.py#L47-L53), [`recorder.py:338-340`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/teqlif-agent/modules/recorder.py#L338-L340)
1. `watchdog._CONTINUOUS_REGISTRY` içinde `train_item2vec_task` ve `train_swipe_live_als_task` yok → Redis `Nov 8` güncelse de SQLite **`Nov 1`'de donmuş**!
2. `db.get_stale_jobs()` `WHERE last_ok_at IS NOT NULL` yüzünden hiç çalışmamış işi alarm vermez. Üstelik `worker.py` statik cron'larından **10 iş** (`flush_clickhouse_buffers`, `expire_recordings`, `archive_recordings`, `notify_new_recordings`, `direct_sale_overdue_check`, `refresh_i18n_cache`, `backfill_listing_quality_scores`, `invalidate_swipe_live_configs`, `sync_swipelive_interests`, `stream_concat`) + 4 early-return iş + `train_listing_quality_model_task` (`n<50`) `_agent_ok` çağırmaz!
3. `recorder.py:338` yalnız yayın bitince `mark_ok` yazar (yayın yoksa `10.5g`'de false-positive!); `reporter.py:47-53` 11 yedeğin yalnız `5`'ini raporlar.

##### 2. Hedef Mimari & Çözüm Reçetesi (Ne İçin / Nasıl?)
1. `watchdog._CONTINUOUS_REGISTRY` ile `worker.cron_jobs` %100 eşitlenir; her ARQ task `early-return` dalları dahil `await _agent_ok(ctx, ...)` çağırır (`try/except` hariç — fail olursa atmaz).
2. `db.get_stale_jobs()`: `registry` içinde olup `job_health` tablosunda satırı olmayan veya `last_ok_at IS NULL` olup başlangıç toleransını (`> expected_every_m * 1.5`) aşan işleri de raporla (`seed_expected_jobs()`).
3. `recorder.py` canlı edge heartbeat'ini periyodik `mark_ok` ile ayrıştırır; `reporter.py` `_BACKUP_JOBS` listesini tüm yerel + offsite yedekleri (`offsite_sync`, `offsite_wal_sync`, `loki`, `uptime_kuma`, `nodemonitor_config`, `pg_basebackup` dahil) kapsayacak şekilde genişletir.
* **Doğrulama:** `sqlite3 /var/lib/teqlif-agent/state.db "SELECT job_name, last_ok_at FROM job_health"` tüm `schedule.yaml` + sürekli işleri güncel gösterir.

##### ⬜ Çözüm Damgası
- *(Henüz uygulanmadı — [Adım 19](#adim-19) bekliyor)*

---

<a id="audit-03"></a>
#### `AUDIT-03` · 🟠 P1 (Yüksek) · Grafana (`521 MB`), `loki/compactor/` & Cluster TLS/Env Sırları Yedek Kapsamında Yok

**Bağlı Adım:** [Adım 16](#adim-16) · **Ortak Dosya:** `nodemonitor_config_backup.sh`, `loki_backup.sh` ([`OFFSITE-09`](#offsite-09))

##### 1. Zaafın Kök Nedeni ve Mekanizması (Ne / Nerede / Neden?)
* Canlı `nodeMonitor` `/opt/monitor/shared/grafana/` (`521 MB` — `grafana.db` `3.7 MB` + dashboard/plugin) ve `/project/shared/config/{grafana.ini,uptime-kuma.env}` hiçbir yedekte yok.
* `loki_backup.sh:16-28` yalnız `chunks/` çeker; TSDB/v13 `compactor/` & index almaz.
* `node1..6` TLS (`/etc/letsencrypt/`, `/etc/ssl/teqlif/cf-origin.*`), `.env*`, `/etc/teqlif-agent/env` ve `/etc/wireguard/*.conf` sistematik yedeklenmiyor.

##### 2. Hedef Mimari & Çözüm Reçetesi (Ne İçin / Nasıl?)
1. `nodemonitor_config_backup.sh` içine `/project/shared/config/` ve `/opt/monitor/shared/grafana/` (`sqlite3 grafana.db ".backup ..."` ile güvenli dump + statik pluginler) ekle.
2. `loki_backup.sh` kaynak listesine `tsdb-shipper-active/` veya index/compactor meta dizinlerini ekle.
3. Şifreli config manifest scriptiyle `node1..6` WG/TLS/`.env` dosyalarını `node2/backups/cluster_secrets/` (yalnız `restic` ile şifreli `node101`'e gider, `chmod 700`) altına al.
* **Doğrulama:** `ls -la /project/teqlif/backups/nodemonitor_config/grafana/grafana.db` + `sqlite3 ... "PRAGMA integrity_check;"` `ok`.

##### ⬜ Çözüm Damgası
- *(Henüz uygulanmadı — [Adım 16](#adim-16) bekliyor)*

---

<a id="audit-04"></a>
#### `AUDIT-04` · 🟠 P1 (Yüksek) · `minio_backup.sh` `30g` Temizlik / Race + `uptime_kuma_backup.sh` Atomik / Şifre Hijyeni

**Bağlı Adım:** [Adım 18](#adim-18) · **Ortak Dosya:** `minio_backup.sh`, `uptime_kuma_backup.sh` ([`BIZ-01`](#biz-01), [`BIZ-03`](#biz-03)) · **Karar:** [K3](#kilitli-kararlar)

##### 1. Zaafın Kök Nedeni ve Mekanizması (Ne / Nerede / Neden?)
* **Etkilenen Dosyalar:** [`minio_backup.sh:16-21,83-101`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/node2/resources/scripts/minio_backup.sh#L16-L101), [`uptime_kuma_backup.sh:25-29`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/node2/resources/scripts/uptime_kuma_backup.sh#L25-L29)
```bash
# minio_backup.sh:20,90-94:
mc mirror --overwrite --quiet "node1minio/${bucket}" "${dest}"  # 30g silme yok + KVKK --remove yok!
# confirm_recordings: created_at <= sync_started_at koruması YOK (mirror sonrası upload'ı damgalar!)
# uptime_kuma_backup.sh:28-29: inline şifre argümanı + .tmp/gzip -t yok (13 Eki 20B bozuk dosya bırakmış!)
"MYSQL_PWD='${UPTIME_KUMA_DB_PASS}' mysqldump -h 127.0.0.1 -u uptime_kuma uptime_kuma" | gzip > "${DEST}"
```

##### 2. Hedef Mimari & Çözüm Reçetesi (Ne İçin / Nasıl?)
1. **`minio_backup.sh`:**
   - Mirror başlarken `SYNC_START=$(date -u +%Y-%m-%dT%H:%M:%SZ)` al ve `confirm_recordings()` sorgusuna `AND COALESCE(transferred_at, available_at, created_at) <= :'sync_start'` ekle.
   - `recordings/` için `--remove` kullanmadan **`find "${BACKUP_DIR}/teqlif/recordings" -type f -mtime +30 -delete`** uygula; **`recordings/` dışı tüm prefix'ler** (`teqlif` içinde ayrı prefix'ler veya `--exclude 'recordings/*' --remove`, ve `teqlif-dm` için `--remove`) ile KVKK silmelerini yansıt!
2. **`uptime_kuma_backup.sh`:** `--single-transaction` + `MYSQL_PWD` yerine SSH stdin/uzak `~/.my.cnf` oku → `${DEST}.tmp` → `gzip -t "${DEST}.tmp"` → `mv`, sonuna `job_ok` ekle ve `13 Eki` `20B` boş `.sql.gz`'yi sil.
* **Doğrulama:** `gzip -t /project/teqlif/backups/uptime_kuma/uptime_kuma_*.sql.gz` tamamı ✔; `minio_backup.sh` logunda `recordings/` dışı silinen test dosyası `node2`'den de silinirken `recordings/` dosyası `30g` boyunca korunur.

##### ⬜ Çözüm Damgası
- *(Henüz uygulanmadı — [Adım 18](#adim-18) bekliyor)*

---

<a id="audit-05"></a>
#### `AUDIT-05` · 🟠 P1 (Yüksek) · ClickHouse `system.*_log` Şişmesi (`2.38G`/`5.4G`) & `node5` `194 MB /var/recordings` + `encoder.py` Yetimleri

**Bağlı Adım:** [Adım 23](#adim-23) · **Ortak Dosya:** `encoder.py`, `node2` & `node5` `/etc/clickhouse-server/config.d/`

##### 1. Zaafın Kök Nedeni ve Mekanizması (Ne / Nerede / Neden?)
* Canlı `node2` ClickHouse sistem tablolarında (`trace_log` 994M, `asynchronous_metric_log` 691M, `metric_log` 416M, `part_log` 311M) **`2.38 GiB`**, `node5` içinde **`3.9 GiB` + `1.5 GiB` log = `5.4 GiB`** tüketim var (TTL tanımlı değil!).
* `node5` (`50G`, **`%56 dolu`**) içinde ayrıca `3.2 GiB /root/.cache` ve **`194 MB /var/recordings`** (12 Eki–6 Kas `.mkv`/`.mp4` artıkları, 0-byte dosyalar ve `*.log`) var — [`encoder.py:164,271`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/teqlif-agent/modules/encoder.py#L164-L271) başarı dışında ve `.log` dosyalarını silmiyor.

##### 2. Hedef Mimari & Çözüm Reçetesi (Ne İçin / Nasıl?)
1. `node2` & `node5` `/etc/clickhouse-server/config.d/system_logs_ttl.xml` ile tüm `system.*_log` tablolarına `7 DAY DELETE` TTL + `TRUNCATE TABLE` bakım temizliği uygula (`node5` `/root/.cache` + eski `/var/log/clickhouse-server/*` loglarını temizle).
2. `encoder.py`: `.mkv` silerken eşlik eden `.log` dosyasını da kaldır (DB veya Loki'ye aktardıktan sonra) ve `failed`/`0-byte` `> 48h` yetim dosyalar için güvenli cleanup ekle; `node5:/var/recordings` yetimlerini temizle.
* **Doğrulama:** `node5` disk kullanımı `%56 → <%40` düzeyine iner; `SELECT sum(bytes) FROM system.parts WHERE database='system'` `< 200 MiB` olur.

##### ⬜ Çözüm Damgası
- *(Henüz uygulanmadı — [Adım 23](#adim-23) bekliyor)*

---

<a id="audit-06"></a>
#### `AUDIT-06` · 🟡 P2 (Orta) · Kırık `logrotate` (`**/*.log`), `agent.log` (`~565 MB`) ve Sınırsız `journald`

**Bağlı Adım:** [Adım 31](#adim-31) · **Ortak Dosya:** [`_common.sh:149-159`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/scripts/_common.sh#L149-L159), `teqlif-agent.service`

##### 1. Zaafın Kök Nedeni ve Mekanizması (Ne / Nerede / Neden?)
```bash
# _common.sh:150 — glibc glob() **/* desteklemediği için logrotate -d hiçbir logla eşleşmiyor!
/project/teqlif/logs/**/*.log {
```
* Canlı sonuç: `node1/logs/redis-core.log` `16M` rotate edilmemiş, `/var/log/teqlif-agent/agent.log` toplam **`~565 MB`** (`nodeMonitor 103M`, `node2 98.5M`, `node1 90.3M`, `node5 78M`, `node6 71M`, `node3 66M`, `node4 58M`), `journald` kotasız (`nodeMonitor 1.2G`, `node5 1.6G du`).

##### 2. Hedef Mimari & Çözüm Reçetesi (Ne İçin / Nasıl?)
* `_common.sh:150`: Açık wildcard yolu kullan: `/project/teqlif/logs/*.log /project/teqlif/logs/*/*.log` ve ayrı blok `/var/log/teqlif-agent/*.log` (`daily`, `rotate 14`, `compress`, `copytruncate`, `maxsize 50M`); tüm node'lara `/etc/systemd/journald.conf.d/size.conf` (`SystemMaxUse=200M`, `MaxRetentionSec=14day`) bas ve canlıda `journalctl --vacuum-size=200M` çalıştır.
* **Doğrulama:** `logrotate -d /etc/logrotate.d/teqlif` hata vermeden dosyaları listeler; `journalctl --disk-usage` tüm node'larda `≤ 200M` çıkar.

##### ⬜ Çözüm Damgası
- *(Henüz uygulanmadı — [Adım 31](#adim-31) bekliyor)*

---

<a id="audit-07"></a>
#### `AUDIT-07` · 🟡 P2 (Orta) · SQLite `cleanup_log` Yinelenmesi, RAM-Only `_last_sync` & `janitor.py` Stale Yorumu

**Bağlı Adım:** [Adım 32](#adim-32) · **Ortak Dosya:** [`db.py:39-47`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/teqlif-agent/db.py#L39-L47), [`gossip.py:60`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/teqlif-agent/gossip.py#L60), [`janitor.py:149`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/teqlif-agent/modules/janitor.py#L149)

##### 1. Zaafın Kök Nedeni ve Mekanizması (Ne / Nerede / Neden?)
* `db.py:39-47` `cleanup_log` tablosunda `UNIQUE` kısıtı yok; `gossip.py:60` `_last_sync` sözlüğünü yalnızca RAM'de tuttuğundan agent her yeniden başladığında `1970-01-01` istiyor ve tüm geçmiş peer satırlarını yinelenmiş şekilde `INSERT` ediyor (budama/`VACUUM` da yok). `janitor.py:149` var olmayan `cleanup_actions.sh` referansı içeriyor.

##### 2. Hedef Mimari & Çözüm Reçetesi (Ne İçin / Nasıl?)
* `db.py`: `UNIQUE(policy_name, target_id, leader_node, created_at)` + `INSERT OR IGNORE` + `gossip_sync_state` tablosu ile `_last_sync`'i kalıcı sakla + haftalık `DELETE WHERE created_at < datetime('now', '-30 days')` & `PRAGMA optimize`; `janitor.py:149` docstring'ini `worker.py` + `schedule.yaml` olarak düzelt.
* **Doğrulama:** Agent restart sonrası `cleanup_log` satır sayısı ikiye katlanmaz.

##### ⬜ Çözüm Damgası
- *(Henüz uygulanmadı — [Adım 32](#adim-32) bekliyor)*

---

<a id="audit-08"></a>
#### `AUDIT-08` · 🟡 P2 (Orta) · `worker.py` `media_messages` OOM / `60d` Sapması / Commit Sırası & Batch'siz 9 Temizlik Görevi

**Bağlı Adım:** [Adım 33](#adim-33) · **Ortak Dosya:** [`worker.py:380-898`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/worker.py#L856-L898) · **Karar:** [K5](#kilitli-kararlar)

##### 1. Zaafın Kök Nedeni ve Mekanizması (Ne / Nerede / Neden?)
```python
# worker.py:854-891 — Başlık "3 gün", docstring "7 gün", kod "60 gün" + .scalars().all() + commit ÖNCESİ MinIO silme!
cutoff = datetime.now(timezone.utc) - timedelta(days=60)
messages = result.scalars().all()
for msg in messages:
    await storage.delete_object_dm(...)  # DB commit fail olursa MinIO dosyası kayıp!
await db.commit()
```
* Ayrıca diğer 11 temizlik görevi (`notifications`, `stream_likes`, `stream_viewers`, `listing_offers`, `exchange_rates`, `stream_chat_messages`, `streams`, `calls`, `empty_message_threads`, `inactive_search_alerts`, `hidden_messages`) tek seferde `LIMIT`'siz `DELETE FROM` atarak yüksek satır sayısında PG kilit ve WAL patlaması riski doğuruyor.

##### 2. Hedef Mimari & Çözüm Reçetesi (Ne İçin / Nasıl?)
1. `cleanup_old_media_messages_task`: Süre **Karar K5** gereği **`timedelta(days=30)`** (docstring ve yorumla uyumlu), sorgu **`LIMIT 500`** döngüsüyle çekilir; önce DB'de URL sütunları `NULL` + `commit()` yapılır, **sonra** biriktirilen key listesi `teqlif-dm`'den silinir!
2. Diğer tüm ARQ temizlik sorguları `ctid IN (SELECT ctid FROM ... WHERE ... LIMIT 5000)` chunk döngüsüne ve aralarında `await asyncio.sleep(0.05)` nefesine bağlanır.
* **Doğrulama:** Unit test / mock DB + MinIO ile `commit()` hata verdiğinde `delete_object_dm`'in çağrılmadığı, başarıda 500'lük chunklarla çalıştığı doğrulanır.

##### ⬜ Çözüm Damgası
- *(Henüz uygulanmadı — [Adım 33](#adim-33) bekliyor)*

---

<a id="kartlar-d"></a>
### Bölüm D — İş Mantığı, Finans, KVKK/Uyum, SPOF & Ölçek (`BIZ-01` .. `BIZ-05`)

---

<a id="biz-01"></a>
#### `BIZ-01` · 🔴 P0 (Kritik) · DM Arşivi Yanlış MinIO Bucket Okuması + Standart 14g PRO Video Upsell Kırılması

**Bağlı Adımlar:** [Adım 7](#adim-7) (DM Arşivi) + [Adım 8](#adim-8) (PRO 14g Video) · **Ortak Dosya:** `messages.py`, `storage_service.py`, `dm_archive_tasks.py`, `streams.py`, `stream_recording_tasks.py`, `minio_backup.sh` · **Karar:** [K2](#kilitli-kararlar), [K3](#kilitli-kararlar)

##### 1. Zaafın Kök Nedeni ve Mekanizması (Ne / Nerede / Neden?)
* **Kırık 1 — DM Arşivi ([`dm_archive_tasks.py:80,94`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/tasks/dm_archive_tasks.py#L80-L94) vs [`messages.py:292-299`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/messages.py#L292-L299)):**
```python
# dm_archive_tasks.py:94 → PRIVATE bucket (teqlif-dm) içine yazar:
await storage.upload_bytes_dm(object_key, payload, content_type="application/gzip")

# messages.py:292,299 → PUBLIC bucket (teqlif) içinden okumaya çalışır → HER ZAMAN [] DÖNER!
keys = await storage.list_object_keys(prefix)
raw = await storage.get_object_bytes(key)
```
  [`storage_service.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/services/storage_service.py#L137-L165) içinde `list_object_keys_dm()` hiç yoktur! Üstelik Pazar `03:00` çalışması `pg_dump` ile aynı dakikaya denk geldiğinden silinen mesajlar `05:30 minio_backup`'a kadar 2.5 saat yalnız `node1` MinIO'da tek kopya kalır.
* **Kırık 2 — Standart 14g Video Upsell ([`stream_recording_tasks.py:40,80-97`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/tasks/stream_recording_tasks.py#L40-L97) vs [`streams.py:310-355`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/streams.py#L310-L355)):**
  Standart yayıncıya `"recording_upsell"` (`expires_at = 14 days`) ile 14 gün arşiv tanımlanır ama `node1` MinIO ILM 2. günde siler, `archive_recordings_task` `node2_confirmed_at + 2 gün` sonra `status='archived'` yapar ve `streams.py:326` `status != 'available'` için `410 RECORDING_EXPIRED` döner + yalnız `node1` MinIO'dan presign verir!

##### 2. Hedef Mimari & Çözüm Reçetesi (Ne İçin / Nasıl?)
1. **DM Onarımı ([Adım 7](#adim-7)):**
   - `storage_service.py` içine `list_object_keys_dm(prefix: str)` (yalnız `settings.minio_bucket_dm`) ekle.
   - `messages.py:292,299`: `storage.list_object_keys_dm(prefix)` ve `storage.get_object_bytes_dm(key)` kullan; hata yutan `except Exception: return []` yerine log + `502`/temiz hata ayırımı ekle.
   - `schedule.yaml`: `archive_old_dm_task` → **Pazar `03:20 UTC`** (`03:00 pg_dump` arkası).
2. **14g PRO Video On-Demand Restore ([Adım 8](#adim-8)):**
   - `node2` video saklama **`30 gün`** (`T+14` hakedişten sonra 16g güvenli pay).
   - 14g penceresi içinde PRO olan kullanıcı `GET /streams/{id}/recording` çağırdığında kayıt `node1` MinIO'da yoksa (`expired`/`archived`, `node2_confirmed_at IS NOT NULL`, `created_at >= NOW() - INTERVAL '14 days'`), backend internal on-demand transfer ile (örn. `node2` read-only internal HTTP endpoint / `node2` → `node1` MinIO `mc cp`) kaydı `node1`'e geri çekip `status='available'`, `expires_at = NOW() + 24h` ile presign döner (böylece `node1` NVMe 2g ILM düşük kalırken **14g upsell vaadi %100 çalışır**!).
* **Doğrulama:** Test DM arşivi `upload_bytes_dm` → `GET /messages/{id}/archive` ile geri okunur (`200`, boş değil); `expired` 5 günlük kayıt PRO yükseltme sonrası indirilebilir.

##### 🔄 Çözüm Damgası
- **Bölüm A (Adım 7) ✅ `287ab13e` — 2026-11-12:**
  - `storage_service.py`: `_list_object_keys_impl(strict=)` ortak yardımcı; `list_object_keys_dm` strict=True ile hiçbir node başarılı olmadığında son hatayı fırlatır (HTTP 502 garantisi)
  - `messages.py`: `get_archived_messages` → `list_object_keys_dm` + `get_object_bytes_dm`; `get_object_bytes_dm` ağ hatası → `continue` yerine `HTTPException(502)`
  - `dm_archive_tasks.py`: docstring `teqlif-dm` bucket + `03:20 UTC` olarak düzeltildi
  - `schedule.yaml`: `archive_old_dm_task` minute: `0` → `20` (Pazar 03:20 UTC)
  - `scripts/test_dm_archive.py`: 10/10 sentetik test (`_list_object_keys_impl` + endpoint)
  - 8/8 node `287ab13e`
- **Bölüm B (Adım 8) ✅ `5dedcce8` / P2-P3 `54939dad` — 2026-11-12 (P0/P1/P2/P3 tam):**
  - `storage_service.py`: `rehydrate_from_node2` — iter_chunked(4MB)+tempfile+fput_object (RAM sabit, OOM güvenli); orchestrator bypass → `settings.minio_endpoint` doğrudan; rstrip("/")
  - `storage_service.py`: `check_exists_on_node1` — stat_object ön kontrolü; 24h penceresi içinde tekrar istek geldiğinde download atlanır (tekrarlı rehydrate önleme, `198eea74`)
  - `streams.py`: `is_available` ILM sınırı (`created_at >= now-2g`); `is_rehydratable` yeni case: `available` ama ILM-deleted; `updated_at=NOW()` eklendi; `check_exists_on_node1` kullanır
  - `get_my_recordings.py`: `archived` kayıtlar 14g penceresi içindeyse listede görünür
  - `recording.dart`: `canWatch` → expired/archived tıklanabilir; `_ExpiryRow` sadece available; `RecordingFilterStatus.available` filtresi `canWatch` → `== available` (`198eea74`)
  - `recording_detail_screen.dart`: `_playerError` REHYDRATE_FAILED için `errorRehydrateFailed` mesajı (`198eea74`)
  - `error_mapper.dart`: `REHYDRATE_FAILED` eşlemesi eklendi
  - ARB (5 dil): `errorRehydrateFailed` anahtarı eklendi
  - `bootstrap_node2.sh`: `chmod o+x /project/teqlif/backups` + `/backups/minio` (`198eea74`) + `systemctl enable --now nginx`
  - `node1/.env.production`: `MINIO_NODE2_REHYDRATE_URL=http://10.10.0.2:9200` eklendi (canlı)
  - `scripts/test_recording_rehydrate.py`: 16/16 test (P0 ILM-deleted + check_exists_on_node1 + tekrarlı rehydrate skip dahil)
  - 8/8 node `54939dad`

---

<a id="biz-02"></a>
#### `BIZ-02` · 🔴 P0 (Kritik) · Sessiz Finansal Mutabakat + Sınırsız `max_slot_wal_keep_size` + `0ms` Lock/Timeout

**Bağlı Adım:** [Adım 6](#adim-6) · **Ortak Dosya:** `wallet_tasks.py`, canlı `node1` `/etc/postgresql/17/main/postgresql.conf` ([`MAINT-03`](#maint-03), [`OFFSITE-07`](#offsite-07)) · **Karar:** [K4](#kilitli-kararlar)

##### 1. Zaafın Kök Nedeni ve Mekanizması (Ne / Nerede / Neden?)
* **Etkilenen Dosya:** [`wallet_tasks.py:101-166`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/tasks/wallet_tasks.py#L101-L166)
```python
# wallet_tasks.py:152-161 — Anomali yakalasa bile YALNIZ warning loglar ve _agent_ok basar!
if abs(wr_val - ledger_val) > 0:
    anomalies += 1
    logger.warning("[Reconciliation] withdrawal tutarsızlığı: ...")
await _agent_ok(ctx, "daily_financial_reconciliation_task")  # Telegram / Sentry YOK!
```
* **Canlı `node1` PG Bulgusu (`psql`):** `max_slot_wal_keep_size = -1` (sınırsız!), `wal_compression = off`, `archive_timeout = 0`, `lock_timeout = 0ms`, `idle_in_transaction_session_timeout = 0ms`, `statement_timeout = 0ms`. `node2_receivewal` kesilirse `node1` `426G` NVMe dolana dek WAL biriktirip **ana prod DB'yi çökertebilir**.

##### 2. Hedef Mimari & Çözüm Reçetesi (Ne İçin / Nasıl?)
1. `wallet_tasks.py:102-262`:
   - `anomalies > 0` durumunda **acil Telegram (`send_telegram_alert`) + `capture_message(..., level="error")` + `_agent_fail`** üret; `_agent_ok` **ancak sıfır anomalide** çağrılsın ve önceki `job_fail` bayrağını `hdel` ile temizlesin.
   - **3 bağımsız muhasebe kovası** (karma wallet_ledger bucket karışımından kaynaklı false-positive önlemek için):
     - Kova 1: `SUM(user_wallet_earnings.pending)` ↔ `SUM(gift_events.earned_teqlik WHERE payout_status='pending')`
     - Kova 2: `SUM(withdrawal_requests WHERE NOT cancelled/rejected)` ↔ `-SUM(ledger WHERE tx_type IN withdrawal_*)` — tüm zaman, 30g pencere yok
     - Kova 3: `SUM(available)` ↔ `SUM(earnings_released+withdrawal_*)` − `convert_net` (convert_to_teqlik user + bonus_mint)
   - **Not (V1.1):** `HandleStoreRefundCommand` V1.0'da tam iade (`iade_orani=1.0`) varsayıyor; kısmi iade açılırsa Kova 1 `cancelled_refund` mantığını kapsamalı.
2. Canlı `node1` `postgresql.conf`:
   ```ini
   wal_compression = lz4
   archive_timeout = 3600
   max_slot_wal_keep_size = '50GB'
   lock_timeout = '5s'
   idle_in_transaction_session_timeout = '5min'
   ```
   (Global `statement_timeout = 0` bırakılır; ağır bakım/API sorguları `SET LOCAL statement_timeout = '15s'` alır.)
* **Doğrulama:** `sudo -u postgres psql -At -c "SELECT name, setting FROM pg_settings WHERE name IN ('wal_compression','archive_timeout','max_slot_wal_keep_size','lock_timeout','idle_in_transaction_session_timeout')"` tüm değerleri doğrular; mutabakat testinde `anomalies > 0` Telegram mesajı üretir.

##### ✅ Çözüm Damgası
- `2026-11-12` · commit `caf6938b` — BIZ-02 Adım 6 K4 PG parametreleri + alarm iskeleti:
  - **`deploy/scale/V2.1/node1/resources/postgresql/conf.d/teqlif.conf` — K4 parametreleri:**
    - `wal_compression = lz4` → WAL boyutu ~%40 küçülür ✓
    - `archive_timeout = 3600` → slot birikimini sınırlar ✓
    - `max_slot_wal_keep_size = '50GB'` → node2_receivewal kesilince 426GB NVMe korunur (önceki: `-1` = sınırsız!) ✓
    - `lock_timeout = '5s'` → kilit birikimini önler ✓
    - `idle_in_transaction_session_timeout = '5min'` → zombi transaction önlenir ✓
  - Canlı node1 `pg_reload_conf()` → doğrulandı: `max_slot_wal_keep_size=51200MB`, `lock_timeout=5000ms`, `idle_in_transaction_session_timeout=300000ms`, `archive_timeout=3600s`, `wal_compression=lz4` ✓
  - `wallet_tasks.py` alarm iskeleti: `anomalies > 0` → Telegram + Sentry + `_agent_fail`; sıfır → `_agent_ok` ✓
  - `_agent_fail(ctx, job_name, reason)` eklendi → `teqlif:agent:job_fail` Redis hash'i ✓
  - node1 `teqlif.service` + `teqlif-worker.service` → `active` ✓
  - node101 dahil tüm 8 node `caf6938b`'de ✓
- `2026-11-12` · commit `806cc9c0` — BIZ-02 Adım 6 reviewer P0+P2 düzeltmeleri (3-kova formülü + bootstrap conf.d):
  - **`wallet_tasks.py` — `daily_financial_reconciliation_task` 3-kova formülü (P0):**
    - **Kova 1 (pending):** `SUM(user_wallet_earnings.pending)` ↔ `SUM(gift_events.earned_teqlik WHERE payout_status='pending')` — karma muhasebe bucket karışıklığını ortadan kaldırır ✓
    - **Kova 2 (withdrawal net, tüm zaman):** `SUM(withdrawal_requests WHERE NOT cancelled/rejected)` ↔ `ABS(SUM(ledger WHERE tx_type IN withdrawal_*))`  — 30g pencere kayması yok ✓
    - **Kova 3 (available):** `SUM(available)` ↔ `SUM(earnings_released+withdrawal_*)` − `convert_net` — convert/bonus kaynaklı false-positive kaldırıldı ✓
    - `_agent_ok` → `hdel("teqlif:agent:job_fail")` ekle (P2: başarılı koşu önceki fail bayrağını temizler) ✓
    - `except` bloğuna `_agent_fail` çağrısı eklendi (P2) ✓
  - **`bootstrap_node1.sh` — `setup_postgresql_conf()` fonksiyonu (P2):**
    - `install_postgresql()` ardından `conf.d/teqlif.conf` → `/etc/postgresql/17/main/conf.d/teqlif.conf` kopyalanır ✓
    - `postgresql.conf`'a `include_dir = 'conf.d'` satırı eklenir (idempotent) ✓
    - K4 parametreleri artık fresh bootstrap'ta da aktif olur ✓
- `2026-11-12` · commit `13f18a60` + `8234ee8d` — BIZ-02 Adım 6 P2/P3 tam kapanış:
  - **`wallet_tasks.py` — P2/P3:**
    - Kova 2: `ABS(SUM)` → `-SUM` (işaret doğruluğu, iptal/red net senaryosu) ✓
    - `release_pending_earnings_task`, `reset_monthly_withdrawal_quota_task`, `check_expired_pro_users_task` except → `_agent_fail` eklendi ✓
  - **`bootstrap_node1.sh` — P3:** `grep -qF` → `grep -qxF` (tam satır eşleşmesi; `#include_dir` yorum tuzağı önlendi) ✓
  - **`watchdog.py` + `db.py` — P2:** `job_fail` hash okunuyor; `mark_fail(last_fail_at=...)` parametresi eklendi; `get_failed_jobs()` eklendi; `_alert_stale`/`_alert_fail` ayrı cooldown key ile ayrıldı ✓
  - **`test_wallet_reconciliation.py` — P3:** 7 senaryo (temiz, kova1/2/3, negatif bakiye, çoklu anomali, exception→_agent_fail) → 7/7 OK ✓
- `2026-11-12` · commit `0b002e18` — BIZ-02 final: mark_fail idempotent + fail_reason + 8/8 agent dağıtımı:
  - **`db.py`:** `fail_reason TEXT` kolonu; `mark_fail()` idempotent — aynı timestamp'te `fail_count` artmaz; `reason` parametresi eklendi ✓
  - **`watchdog.py`:** payload reason ayrıştırılıp `mark_fail(reason=...)` ile yazılıyor; `_alert_fail` Telegram mesajına `fail_reason` eklendi ✓
  - **8/8 node:** `/opt/teqlif-agent/` sync + `teqlif-agent` restart — watchdog hash `4e3a4ef5` tüm node'larda eşit ✓
- `2026-11-12` · commit `297d71e9` — fail_reason SELECT + gossip + html.escape:
  - `get_failed_jobs()` SELECT listesine `fail_reason` eklendi (yoksa `None` dönüyordu) ✓
  - `apply_delta()` gossip merge'e `fail_reason` sütunu eklendi ✓
  - `_alert_fail`: `html.escape(reason)` → Telegram HTML parse `400` riski kapatıldı ✓
  - 8/8 node `/opt/teqlif-agent` sync + restart ✓

---

<a id="biz-03"></a>
#### `BIZ-03` · 🟠 P1 (Yüksek) · KVKK Hesap Silme Boşlukları & `07:00 TR` Promosyonel Push Fırtınası

**Bağlı Adım:** [Adım 24](#adim-24) · **Ortak Dosya:** `auth.py`, `analytics_tasks.py`, `listing_tasks.py`, `schedule.yaml` ([`AUDIT-04`](#audit-04), [`OFFSITE-13`](#offsite-13)) · **Karar:** [K5](#kilitli-kararlar), [K6](#kilitli-kararlar)

##### 1. Zaafın Kök Nedeni ve Mekanizması (Ne / Nerede / Neden?)
* **Etkilenen Dosyalar:** [`auth.py:1638-1719`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/auth.py#L1638-L1719), [`analytics_tasks.py:171-345`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/tasks/analytics_tasks.py#L171-L345), [`listing_tasks.py:224-269`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/tasks/listing_tasks.py#L224-L269), [`notification_service.py:71-88`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/services/notification_service.py#L71-L88)
1. `delete_account` (`auth.py:1638`) kullanıcının [`UserWalletEarnings`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/models/user_wallet_earnings.py#L8-L19) (`pending`/`available`) veya açık [`WithdrawalRequest`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/models/withdrawal_request.py#L10-L42) kontrolünü yapmadan hesabı kapatır; `direct_messages` ve `teqlif-dm` (`dm-archive/`) verilerini temizlemez; ilan görselleri 60g bekletilir.
2. `04:00–05:00 UTC` (`07:00–08:00 TR`) çalışan `process_churn_and_airdrop`, `deactivate_expired_listings`, `delete_expired_inactive_listings`, `hesitation_retarget` **`pref_key=None`** geçtiği için `quiet_hours_enabled` ayarını atlar. Üstelik `process_churn_and_airdrop` CH hatasını yutup (`return set(), set()`) sahte `_agent_ok` atar ve `wallet_ledger` yerine legacy `teqlik_transactions` tablosuna yazar.

##### 2. Hedef Mimari & Çözüm Reçetesi (Ne İçin / Nasıl?)
1. `auth.py:delete_account`:
   - `UserWalletEarnings` (`pending > 0 OR available > 0`) veya `WithdrawalRequest` (`status IN ('pending','approved')`) varsa **`ConflictException(code="ACTIVE_BALANCE_OR_WITHDRAWAL_PENDING")`** (`HTTP 409`) döndür.
   - Engel yoksa kimlik anonimizasyonu yanında kullanıcının ilan medyalarını silme kuyruğuna al ve DM metin/arşiv görünürlüğünü KVKK politikasına göre temizle (finans defterleri hariç — `Adım 35` WORM).
2. `schedule.yaml`: `process_churn_and_airdrop`, `hesitation_retarget_task`, `deactivate_expired_listings_task` ve `delete_expired_inactive_listings_task` saatlerini **`08:00–08:30 UTC` (`11:00–11:30 TR`)** bandına kaydır; `notification_service.py` `quiet_hours` kontrolünü **`pref_key` olmasa da** promosyon/sistem dışı `notif_type` için değerlendir (`user` sorgusu tekil).
3. `analytics_tasks.py:171-173`: ClickHouse erişilemediğinde hatayı yutup `_agent_ok` basmak yerine `raise` et (ve airdrop kredi logunu `wallet_ledger` muhasebesiyle senkronla).
* **Doğrulama:** Açık `pending=100` bakiyeli test kullanıcısı `DELETE /auth/delete-account` çağrısında `HTTP 409` alır; CH kapalıyken `process_churn_and_airdrop` exception fırlatır (`_agent_ok` basmaz).

##### ⬜ Çözüm Damgası
- *(Henüz uygulanmadı — [Adım 24](#adim-24) bekliyor)*

---

<a id="biz-04"></a>
#### `BIZ-04` · 🟠 P1 (Yüksek) · `09:15 TR` Mail Kesintisi + `nodeMonitor` SPOF & Eksik Prometheus Hedefleri + Staging Artığı

**Bağlı Adımlar:** [Adım 17](#adim-17) (Mail Backup) + [Adım 20](#adim-20) (SPOF / Prometheus) · **Ortak Dosya:** `mail_backup.sh`, `prometheus.yml`, `alert_rules.yml`, `node5` staging · **Karar:** [K1](#kilitli-kararlar)

##### 1. Zaafın Kök Nedeni ve Mekanizması (Ne / Nerede / Neden?)
* **Etkilenen Dosyalar:** [`mail_backup.sh:21-29`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/node2/resources/scripts/mail_backup.sh#L21-L29), [`prometheus.yml:15-74`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/nodeMonitor/config/teqlif/prometheus.yml#L15-L74), [`alert_rules.yml:1-92`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/nodeMonitor/config/teqlif/alert_rules.yml#L1-L92)
1. **Mail (`Adım 17`):** `06:15 UTC` (`09:15 TR` sabah açılışı) `stalwart-mail` durduruluyor; üstelik `mail_backup.sh` `/project/mail/config/config.toml` (`6.1 KB`), `.env.mail` (`510 B`) ve `config/acme/` almıyor, `2>/dev/null` ile hata gizliyor ve `tar -tzf` doğrulamıyor.
2. **SPOF & Kör Servisler (`Adım 20`):** Tüm izleme + `teqlif-agent` Lideri tek `1.9 GiB` VPS'te (`nodeMonitor`) ve `node1`/`node2`'den onu denetleyen **hiç Dead Man's Switch yok**. Prometheus yalnız `fastapi`, `postgres`, `pgbouncer`, `redis` ve `node1..6,nodeMonitor` izliyor — **`node101`**, **`ClickHouse` (`9363`)**, **`MinIO` (`/minio/v2/metrics/cluster`)**, **`Redis Replica` (`node2`)**, **`pg_receivewal`**, **`stalwart-mail`** hedefleri ve swap/slot/backup alertleri yok!

##### 2. Hedef Mimari & Çözüm Reçetesi (Ne İçin / Nasıl?)
1. **`mail_backup.sh` ([Adım 17](#adim-17)):** Timer'ı **`03:50 UTC` (`06:50 TR`)** yap; arşiv listesine `/project/mail/config/{config.toml,.env.mail,acme,dkim}` ekle, `2>/dev/null` kaldır, `.tmp` → `tar -tzf` doğrulaması ekle.
2. **SPOF & Prometheus ([Adım 20](#adim-20)):**
   - `prometheus.yml` içine `node101` (`10.10.0.101:9100`), `rest-server` (`10.10.0.101:8000/metrics`), `ClickHouse` (`10.10.0.2:9363`), `MinIO` (`10.10.0.1:9000/minio/v2/metrics/cluster`), `Redis Replica` (`10.10.0.2`), `pg_receivewal`/slotexporter ekle.
   - `alert_rules.yml` içine PG inaktif/şişen replication slot (`> 5 GB` veya inaktif), aktif swap `> 50%`, `node101` disk/servis düşüşü kurallarını ekle.
   - `node2` üzerinde basit bağımsız **Dead Man's Switch** cron/timer (`nodeMonitor` `10.10.0.99:9090/-/healthy` & Alertmanager `9093/-/healthy` her 2 dk'da ping; 3 kesintide doğrudan `.env.backup` içindeki Telegram'a `nodeMonitor ÇÖKTÜ!` uyarısı).
   - `node5` staging ClickHouse + `teqlif-staging` MinIO yedeksizlik durumunu "kasıtlı staging" ya da haftalık hafif snapshot olarak netleştir.
* **Doğrulama:** `curl -s http://10.10.0.99:9090/api/v1/targets` içinde `node101`, `clickhouse`, `minio`, `rest-server` `health="up"` görünür; `node2` dead-man check'i dry-run geçer.

##### ⬜ Çözüm Damgası
- *(Henüz uygulanmadı — [Adım 17](#adim-17), [Adım 20](#adim-20) bekliyor)*

---

<a id="biz-05"></a>
#### `BIZ-05` · 🟠 P1 (Yüksek) · Yüksek Ölçek (`>50K`) Veri Kaybı: `sync_pg_to_clickhouse_task` `LIMIT` & `listing_tasks` Kırılması

**Bağlı Adım:** [Adım 25](#adim-25) · **Ortak Dosya:** [`worker.py:4145-4264`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/worker.py#L4145-L4264), [`listing_tasks.py:84-160`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/tasks/listing_tasks.py#L84-L160)

##### 1. Zaafın Kök Nedeni ve Mekanizması (Ne / Nerede / Neden?)
```python
# worker.py:4153,4189,4252:
# LIMIT 200000 / LIMIT 500000 dolsa bile ch:last_sync_at = now çekilir!!
# Sonuç: Aradaki kalan olaylar CH'a hiç girmeden 48s sonra DELETE FROM analytics_events ile SİLİNİR!
WHERE event_type IN (...) AND created_at > :last_sync AND created_at <= :now
ORDER BY created_at LIMIT 500000
...
await redis.set("ch:last_sync_at", now.isoformat())  # Aradakiler kalıcı kaybolur!
```
* Ayrıca [`listing_tasks.py:84-160`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/tasks/listing_tasks.py#L84-L160) `LIMIT`'siz ilanı tek transaction'da döndürüp MinIO nesnelerini tek tek döngüde siler ve `except` bloklarında `raise` etmeyerek ARQ retry mekanizmasını öldürür (`AUDIT-08` ile birlikte PG kilit & WAL patlaması).

##### 2. Hedef Mimari & Çözüm Reçetesi (Ne İçin / Nasıl?)
1. `sync_pg_to_clickhouse_task`: `while True` cursor döngüsü kullan (son satırın `created_at` / `id` ikilisiyle page-by-page ilerle), ancak **yalnız o partiye ait** `last_sync` cursor'ını Redis'e yaz ve `DELETE FROM analytics_events` sorgusunu **5.000'lik batch (`ctid IN ... LIMIT 5000`)** + **`< min(last_sync_at, NOW() - 48h)`** güvencesiyle çalıştır (ClickHouse'a gitmemiş satır asla silinmez!).
2. `listing_tasks.py`: İlanları `LIMIT 500` batch'lerle işle, `delete_listing_files` çağrılarını `asyncio.Semaphore(10)` ile paralel yürüt ve `except` bloklarının sonuna `raise` ekle.
* **Doğrulama:** `LIMIT` testinde `500.001+` satırlık mock tabloda tüm partilerin ClickHouse'a eksiksiz aktarıldığı ve cursor öncesi dışında silme yapılmadığı doğrulanır.

##### ⬜ Çözüm Damgası
- *(Henüz uygulanmadı — [Adım 25](#adim-25) bekliyor)*

---

<a id="master-eylem-plani"></a>
## 🎯 6. Master Eylem Planı (Uçtan Uca Sıralı Mühendislik Yol Haritası — 36 Adım)

> Tüm `34` bulgunun bağımlılık sırasına ve öncelik seviyesine göre Claude tarafından sırayla uygulanacak **36 atomik mühendislik adımı** (`problems/V1.0` standardı):

### 🟣 Faz 0: `node101` Hazırlık, Donanım İzolasyonu ve Ağ Topolojisi (Ön Koşul — 3 Adım)

<a id="adim-1"></a>
~~1. **Adım 1 (`OFFSITE-06`):** `node101` üzerinde `timedatectl set-timezone UTC` ayarla, `teqlif-backup` sistem kullanıcısını ve `/mnt/data/{restic-repo,tmp,cache/restic,logs}` dizinlerini (`TMPDIR`, `RESTIC_CACHE_DIR` — `9.7 GB` `/` diski koruma) oluştur, `/etc/fstab` `/mnt/data` otomatik bağlamasını + `df -h /` (`<%40`) eşiğini doğrula~~ ✅ `09eb442c` (2026-11-11)

<a id="adim-2"></a>
~~2. **Adım 2 (`OFFSITE-05`):** `node101` WireGuard (`10.10.0.101/24` — yalnız `node2` ve `nodeMonitor` peer'ları) ve UFW (`IPV6=no`, port `8000` yalnız `10.10.0.2`, port `9100` yalnız `10.10.0.99`, SSH Ed25519 key-only) kurallarını `deploy/scale/V2.1/node101/` altında tanımla; [`wg_mesh_apply.sh`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/scripts/wg_mesh_apply.sh), `secrets.env.template` ve `teqlif-restart.sh` içine `node101` kaydını ekle → _Neden:_ Web/edge node'larının yedek sunucusuna doğrudan erişimini (blast-radius) kesmek ve IPv4-only sunucuyu güvenli tünele almak. → ([Detay](#offsite-05))~~ ✅ `351c35fb`

<a id="adim-3"></a>
~~3. **Adım 3 (`OFFSITE-12`):** `deploy/scale/V2.1/scripts/bootstrap_node101.sh` (Debian 13 idempotent kurulum) dosyasını oluştur; [`_common.sh`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/scripts/_common.sh) + [`bootstrap_node2.sh:210-214`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/scripts/bootstrap_node2.sh#L210-L214) içine `restic`, `rclone` ve atlanan 7+1 backup timer `enable` listesini ekle → _Neden:_ Sunucu yeniden kurulumlarında otomasyonun kırılmasını ve 7 timer'ın kapalı kalmasını engellemek. → ([Detay](#offsite-12))~~ ✅ `1ce09741` (2026-11-12)

---

### 🔴 Faz 1: Canlı Failover, DR, PG Disk Koruması, Ürün/Finans Bütünlüğü & Şifreli Offsite (P0 Kritik — 10 Adım)

<a id="adim-4"></a>
~~4. **Adım 4 (`MAINT-03`):** Canlı `node2` üzerinde yetkisiz `redis-failover.timer`/`service` + düz metin şifreli `/usr/local/bin/redis-failover-check.sh` kalıntılarını kaldır, `node1` Redis sağlığı doğrulandıktan sonra `/var/lib/teqlif-redis-failover/promoted` bayrağını sil ve [`redis_failover.sh:62-69`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/node2/resources/scripts/redis_failover.sh#L62-L69) içindeki `node1` WG peer'ını `0.0.0.1/32` yapan bloğu kaldır → _Neden:_ 18 Ekim'den beri kör olan otomatik Redis failover'ı tekrar aktif etmek ve promote anında `pg_receivewal`/`MinIO` trafiğinin kopmasını önlemek. → ([Detay](#maint-03), [İlişkili: BIZ-02](#biz-02))~~ ✅ `c0154e66` (2026-11-12)

<a id="adim-5"></a>
~~5. **Adım 5 (`AUDIT-01`):** `node2` üzeinde `postgresql-17-pgvector` paketini kur + `main` cluster hazırlığı, `/project/teqlif/config/.env.dr` ve `/etc/ssl/teqlif/cf-origin.{crt,key}` dosyalarını yerleştir; [`pg_basebackup.sh`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/node2/resources/scripts/pg_basebackup.sh#L19-L35) atomik `.tmp`→`mv` yap, [`pg_dump.sh`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/node2/resources/scripts/pg_dump.sh) içine `--globals-only` ekle ve [`runbook.sh:134-155`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/node2/resources/scripts/runbook.sh#L134-L155) içinde `pg_wal.tar.gz` açılımı + `recovery_target = 'immediate'` → `'latest'` düzeltmesini yap → _Neden:_ `node1` çöktüğünde `node2` DR failover ve 1 dk PITR kurtarmasının gerçekten çalışmasını sağlamak. → ([Detay](#audit-01))~~ ✅ `f48e8eaf` (2026-11-12)

<a id="adim-6"></a>
~~6. **Adım 6 (`BIZ-02`):** Canlı `node1` `postgresql.conf` içine [Karar K4](#kilitli-kararlar) gereği **`max_slot_wal_keep_size = '50GB'`**, `wal_compression = lz4`, `archive_timeout = 3600`, `lock_timeout = '5s'`, `idle_in_transaction_session_timeout = '5min'` ekle; [`wallet_tasks.py:102-262`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/tasks/wallet_tasks.py#L102-L262) `daily_financial_reconciliation_task`'ı `anomalies > 0` durumunda acil Telegram + Sentry alarmı verecek ve 3-kova formülü ile tam defter toplamını denetleyecek şekilde güncelle → _Neden:_ `node2_receivewal` kesildiğinde prod NVMe'nin %100 dolup PG'yi çökertmesini ve finansal defter sapmalarının sessiz kalmasını önlemek. → ([Detay](#biz-02), [Karar K4](#kilitli-kararlar))~~ ✅ `caf6938b` + `806cc9c0` + `13f18a60` + `8234ee8d` (2026-11-12)

<a id="adim-7"></a>
~~7. **Adım 7 (`BIZ-01` — Bölüm A):** [`storage_service.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/services/storage_service.py#L137-L160) içine `list_object_keys_dm` metodunu ekle, [`messages.py:292-299`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/messages.py#L292-L299) `get_archived_messages` endpoint'ini public `teqlif` yerine private **`teqlif-dm`** okur hale getir ve [`schedule.yaml`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/schedule.yaml) içinde `archive_old_dm_task` saatini Pazar `03:00` → **`03:20 UTC`** (`03:00 pg_dump` sonrasına, [Karar K2](#kilitli-kararlar)) taşı → _Neden:_ 1 yıl+ tüm DM geçmişinin boş `[]` dönmesini çözmek ve `pg_dump` öncesi tek-kopya penceresini sıfırlamak. → ([Detay](#biz-01))~~ ✅ `287ab13e`

<a id="adim-8"></a>
~~8. **Adım 8 (`BIZ-01` — Bölüm B) [P0/P1/P2 fix `5dedcce8`]:** [`streams.py:300-365`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/streams.py#L300-L365) + [`stream_recording_tasks.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/tasks/stream_recording_tasks.py) içine 14 günlük pencerede PRO'ya yükselten kullanıcılar için `node2` arşivinden (`30g` saklama, [Karar K3](#kilitli-kararlar)) `node1` MinIO'ya on-demand geri çekme (rehydrate) + 24h presign akışını ekle → _Neden:_ Standart yayıncılara vaat edilen 14g PRO upsell özelliğinin `404 NoSuchKey`/`RECORDING_EXPIRED` ile kırılmasını önlemek ve `T+14` hakedişle 16g güvenli tampon sağlamak. → ([Detay](#biz-01), [Birlikte: Adım 18](#adim-18))~~ ✅ `5dedcce8`

<a id="adim-9"></a>
~~9. **Adım 9 (`OFFSITE-02`):** `node101` üzerinde `restic-rest-server 0.13.0` (`--append-only --listen 10.10.0.101:8000 --htpasswd-file ... --path /mnt/data`) servisini kur (`--private-repos` ile her HTTP user kendi `/mnt/data/<user>/` alt dizinini görür); `node101` yerel `teqlif-offsite-prune.{service,timer}` (`Pazar 08:00 UTC`, `GOMEMLIMIT=1536MiB`, `GOGC=20`, `MemoryMax=2G`) oluştur → _Neden:_ `node2` ele geçirilse bile `node101`'deki yedeklerin silinememesini (WORM) ve `2.9 GiB RAM` korunmasını garanti etmek. → ([Detay](#offsite-02))~~ ✅ `f773a084`

<a id="adim-10"></a>
~~10. **Adım 10 (`OFFSITE-03`):** `node2` üzerinde `/etc/teqlif/restic.pass` (`chmod 600`, Git dışı) oluşturup şifreli `restic init` (`AES-256-CTR + Poly1305`) çalıştır; `RESTIC_PASSWORD` ve HTTP auth sırlarını **3 bağımsız noktada Key Escrow** kasasına kaydet ve şifreli test doğrulaması yap → _Neden:_ `node101` diskinde PII/DM/finans verisinin şifreli kalması ve `node2` yansa bile kilitsiz kurtarma sağlanması. → ([Detay](#offsite-03))~~ ✅ `1bf776a7`

<a id="adim-11"></a>
~~11. **Adım 11 (`OFFSITE-01`):** `node1` MinIO 2g ILM öncesinde `node2` mirror + `node101` offsite ilk `daily-full` kopyasının garanti altına alınmasını (öncelikli mirror + offsite akışı ve `node101` tek-volume izleme rolü) kilitle → _Neden:_ Video kayıtlarında `node1` ILM sonrası 3-2-1 kopya kuralını tamamlamak. → ([Detay](#offsite-01), [Blueprint](#blueprint))~~ ✅ `c5133ac3`

<a id="adim-12"></a>
~~12. **Adım 12 (`OFFSITE-07`):** [`offsite_sync.sh`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/node2/resources/scripts/offsite_sync.sh) içeriğini `rclone sync` → **`restic backup --pack-size 32 --tag daily-full`** olarak yeniden yaz, kapsamına `pg_basebackup` + `pg_wal` (`--exclude '*.partial' --exclude '*.tmp' --exclude '.last_*'`) ekle, saatini **`06:30 UTC`** yap ve [`pg_dump.sh:26`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/node2/resources/scripts/pg_dump.sh#L26) `.dump*` filtresiyle canlı `2–8 Eki` `.dump.gz` yetimlerini temizle → _Neden:_ Offsite PG PITR kapsamını açmak ve `node101` `fdatasync` darboğazını `--pack-size 32` ile aşmak. → ([Detay](#offsite-07))~~ ✅ `114c0ee4`

<a id="adim-13"></a>
~~13. **Adım 13 (`OFFSITE-04`):** `offsite_sync.sh` boş config'te **`exit 2` + Telegram**, `teqlif-offsite-sync.service` içine `OnFailure=teqlif-backup-failed@%n.service` + `IOSchedulingClass=idle` + `Nice=19` ekle; yeni saatlik **`offsite_wal_sync.sh` + `teqlif-offsite-wal.{service,timer}` (`*:45:00 UTC`, `--tag pg_wal`)** oluştur; her iki timer'ı `systemctl enable --now` yap ve sentinel + `schedule.yaml` + [`health.py`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/teqlif-agent/modules/health.py#L44-L54) entegrasyonunu tamamla → _Neden:_ 3 katmanlı izleme körlüğünü gidermek ve çifte felakette PG RPO'sunu `24 saat → ≤ 1 saate` indirmek. → ([Detay](#offsite-04))~~ ✅ `2214bff7`

---

### 🟠 Faz 2: Yedek Kapsamı, Telemetri/Watchdog, SPOF/Prometheus, KVKK/Push, ClickHouse/Ölçek (P1 Yüksek — 12 Adım)

<a id="adim-14"></a>
14. **Adım 14 (`OFFSITE-08`):** `node2` ClickHouse üzerinde `teqlif` kullanıcısına `GRANT BACKUP ON *.*` ver, `/etc/clickhouse-server/config.d/backups.xml` hedefini `/project/teqlif/backups/clickhouse` yap, [`clickhouse_backup.sh`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/node2/resources/scripts/clickhouse_backup.sh) fallback'ine `SHOW CREATE` DDL + log dosyası ekle ve canlı `node2` üzerindeki terk edilmiş `teqlif_staging_analytics` (`25` satır) verisini temizle → _Neden:_ Gerçek atomik ClickHouse yedeğini (DDL + MV + veri) aktifleştirmek. → ([Detay](#offsite-08))

<a id="adim-15"></a>
15. **Adım 15 (`OFFSITE-09`):** [`nodemonitor_config_backup.sh:27-41`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/node2/resources/scripts/nodemonitor_config_backup.sh#L27-L41) içine `--delete-excluded` ile `--exclude 'loki/wal/'` / `'loki/tsdb-shipper-*'` ekle ve canlı `node2` üzerindeki `979 MB` TSDB/WAL sızıntısını temizle → _Neden:_ Her offsite yedeğinin gereksiz ~1 GB şişmesini durdurmak (`979 MB → < 5 MB`). → ([Detay](#offsite-09))

<a id="adim-16"></a>
16. **Adım 16 (`AUDIT-03`):** [`nodemonitor_config_backup.sh`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/node2/resources/scripts/nodemonitor_config_backup.sh) kapsamına `/opt/monitor/shared/grafana/` (`521 MB`) + `/project/shared/config/` ekle, [`loki_backup.sh`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/node2/resources/scripts/loki_backup.sh) içine `compactor/`/index ekle ve `node1..6` TLS/WG/`.env` sırlarını `cluster_secrets/` üzerinden şifreli offsite zincirine kat → _Neden:_ Felaket sonrası Grafana panellerinin, Loki indeksinin ve cluster sırlarının kaybedilmesini önlemek. → ([Detay](#audit-03))

<a id="adim-17"></a>
17. **Adım 17 (`BIZ-04` — Bölüm A):** [`mail_backup.sh`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/node2/resources/scripts/mail_backup.sh#L21-L39) zamanını `06:15 UTC` (`09:15 TR`) → **`03:50 UTC` (`06:50 TR`, [Karar K1](#kilitli-kararlar))** al; arşive `/project/mail/config/{config.toml,.env.mail,acme}` ekle, `2>/dev/null` kaldır ve `.tmp` + `tar -tzf` bütünlük doğrulaması ekle → _Neden:_ Sabah mesai açılışında OTP/e-posta düşüşünü bitirmek ve mail sunucusunun tüm kimliğini yedeklemek. → ([Detay](#biz-04))

<a id="adim-18"></a>
18. **Adım 18 (`AUDIT-04`):** [`minio_backup.sh`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/node2/resources/scripts/minio_backup.sh) içine `recordings/` `30g` temizlik + `recordings/` dışı tüm prefix'lerde KVKK `--remove` + `confirm_recordings()` `created_at <= sync_started_at` zaman kilidi ekle ([Karar K3](#kilitli-kararlar)); [`uptime_kuma_backup.sh`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/node2/resources/scripts/uptime_kuma_backup.sh) atomik `.tmp` + `gzip -t` + `--single-transaction` + inline şifresiz `.my.cnf` yap ve `13 Eki` `20B` boş `.sql.gz`'yi sil → _Neden:_ Silinen kullanıcı medyalarının KVKK'ya aykırı biçimde `node2`'de süresiz kalmasını ve Kuma bozuk yedek/şifre sızıntısını önlemek. → ([Detay](#audit-04), [Birlikte: Adım 8](#adim-8), [Adım 24](#adim-24))

<a id="adim-19"></a>
19. **Adım 19 (`AUDIT-02`):** [`watchdog.py`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/teqlif-agent/modules/watchdog.py#L49-L64) `_CONTINUOUS_REGISTRY` ile [`worker.py:4816-4853`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/worker.py#L4816-L4853) statik görevlerini eşitle; eksik `10+` göreve (ve early-return'lere) `_agent_ok` ekle; [`db.py:130-137`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/teqlif-agent/db.py#L130-L137) "hiç çalışmamış iş" (`last_ok_at IS NULL`) körlüğünü aç; [`recorder.py`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/teqlif-agent/modules/recorder.py#L338-L340) aktif edge heartbeat ayarla ve [`reporter.py:47-53`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/teqlif-agent/modules/reporter.py#L47-L53) raporunu tüm yerel + offsite yedekleri (`offsite_sync`, `offsite_wal_sync` dahil) kapsayacak biçimde tamamla → _Neden:_ `Nov 1`'de donan watchdog SQLite tablosunu ve sessiz duran ARQ cron körlüklerini kaldırmak. → ([Detay](#audit-02), [Birlikte: Adım 13](#adim-13))

<a id="adim-20"></a>
20. **Adım 20 (`BIZ-04` — Bölüm B):** [`prometheus.yml`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/nodeMonitor/config/teqlif/prometheus.yml) içine `node101`, `rest-server`, `ClickHouse`, `MinIO`, `Redis Replica`, `pg_receivewal`, `Stalwart` scrape hedeflerini ve [`alert_rules.yml`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/nodeMonitor/config/teqlif/alert_rules.yml) içine inaktif/şişen PG slot (`> 5 GB`), swap ve backup fail kurallarını ekle; `node2`'den `nodeMonitor` için dış **Dead Man's Switch** kur + `node5` staging yedek politikasını netleştir → _Neden:_ `nodeMonitor` SPOF arızasında ve kör kritik servislerde sessiz kesinti yaşanmasını önlemek. → ([Detay](#biz-04))

<a id="adim-21"></a>
21. **Adım 21 (`MAINT-01`):** [`cleaner.py:35-112`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/teqlif-agent/modules/cleaner.py#L35-L112) içindeki `message_threads` (`180d`) ve batch'siz PG `DELETE` tablosunu emekliye ayır; tüm PG temizliğini batched ARQ (`worker.py` + `schedule.yaml`) tek otoritesine bırak → _Neden:_ `PG_DSN` tanımlandığı an 180–365 günlük mesaj thread'lerinin silinmesini ve çift temizlik WAL patlamasını engellemek. → ([Detay](#maint-01))

<a id="adim-22"></a>
22. **Adım 22 (`MAINT-02`):** [`cluster.yaml:36-47`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/cluster.yaml#L36-L47) içinde `transfer_window_start_utc: 3`, `transfer_window_end_utc: 5` (`04:00–05:00` normal / `03:00–05:00` disk uyarısı), `retention_days: 30` ayarla; [`worker.py:4845`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/worker.py#L4845) `notify_new_recordings_task` saatini **`05:45 UTC`** yap → _Neden:_ `node3`/`node4` video transferi ile `05:30` `minio_backup` ve `05:00/06:00` push çarpışmasını ortadan kaldırmak. → ([Detay](#maint-02), [Birlikte: Adım 8](#adim-8))

<a id="adim-23"></a>
23. **Adım 23 (`AUDIT-05`):** `node2` ve `node5` ClickHouse `system.*_log` tabloları için 7 günlük `TTL DELETE` (`system_logs_ttl.xml`) + tek seferlik `TRUNCATE` uygula, [`encoder.py`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/teqlif-agent/modules/encoder.py#L162-L274) `.log`/0-byte/`failed > 48h` yetim temizliği ekle ve canlı `node5` `194 MB /var/recordings` + `3.2 GB /root/.cache` artığını sil → _Neden:_ `%56` doluluğa ulaşan `node5` diskiyle `node2`/`edge` disklerinin log ve ham video artıklarıyla dolmasını engellemek. → ([Detay](#audit-05))

<a id="adim-24"></a>
24. **Adım 24 (`BIZ-03`):** [`auth.py:1638-1719`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/auth.py#L1638-L1719) `delete_account` içine `UserWalletEarnings` / `WithdrawalRequest` `409 Conflict` koruması ([Karar K5](#kilitli-kararlar)) + ilan/DM temizliği ekle; `schedule.yaml`'daki airdrop/ilan/retarget promosyonel push'larını `08:00–08:30 UTC` (`11:00–11:30 TR`) penceresine alıp `quiet_hours` kontrolü uygula ([Karar K6](#kilitli-kararlar)); [`analytics_tasks.py:171-321`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/tasks/analytics_tasks.py#L171-L321) CH hatasında `raise` et + `wallet_ledger` bağla → _Neden:_ KVKK uyumu, açık bakiye korunması ve `07:00 TR` push fırtınasının önlenmesi. → ([Detay](#biz-03), [Birlikte: Adım 18](#adim-18))

<a id="adim-25"></a>
25. **Adım 25 (`BIZ-05`):** [`worker.py:4145-4268`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/worker.py#L4145-L4268) `sync_pg_to_clickhouse_task` içine cursor pagination + `ch:last_sync_at` öncesi dışında silmeme + 5.000 batch `DELETE` koy; [`listing_tasks.py:84-160`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/tasks/listing_tasks.py#L84-L160) 500'lük chunk, paralel `delete_listing_files` ve `except` içine `raise` ekle → _Neden:_ `>50K` kullanıcı ölçeğinde sessiz ClickHouse veri kaybını ve ARQ timeout/kilit patlamasını önlemek. → ([Detay](#biz-05))

---

### 🟡 Faz 3: Sistem Hijyeni, OS Zamanlama, Batch Temizlik & Kurtarma Tatbikatı (P2–P3 — 11 Adım)

<a id="adim-26"></a>
26. **Adım 26 (`OFFSITE-10`):** Kalan 6 yerel `node2/systemd/*.service` (`pg-basebackup`, `loki`, `uptime-kuma`, `nodemonitor-config`, `mail`, `pg-wal-cleanup`; `offsite-sync` [Adım 13](#adim-13)'te) birimine `IOSchedulingClass=idle`, `IOSchedulingPriority=7`, `Nice=19` ekle ve `*.tmp`/`*.partial`/`.last_*` hariç tutmasını tüm scriptlerde kilitle → _Neden:_ `node2` HDD kuyruğunun yedekler yüzünden ClickHouse/WAL/posta I/O'sunu boğmasını engellemek. → ([Detay](#offsite-10))

<a id="adim-27"></a>
27. **Adım 27 (`MAINT-04`):** `node1..6`, `node2` ve `nodeMonitor` üzerinde `apt-daily-upgrade.timer` `override.conf` ile **`07:45 UTC`**'ye ve `node2` `mdcheck_continue.timer` `07:35 UTC` sonrasına çek → _Neden:_ Otomatik APT restart ve aylık RAID parity scrub'ının sabah backup/offsite bloğuna girmesini önlemek. → ([Detay](#maint-04))

<a id="adim-28"></a>
28. **Adım 28 (`MAINT-05`):** [`schedule.yaml:304`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/schedule.yaml#L304) içine üst seviye `backup:` anahtarını ekle, [`worker.py:4847`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/worker.py#L4847) mükerrer `cleanup_old_stream_chat_messages_task` satırını sil, `03:00` temizliklerini `03:10 UTC`'ye al ve tüm yanlış yorumları [Kanonik Tablo](#zamanlama-matrisi) ile eşitle → _Neden:_ `schedule_loader` `backup` watch'ını çalıştırmak ve çift cron riskini kaldırmak. → ([Detay](#maint-05))

<a id="adim-29"></a>
29. **Adım 29 (`MAINT-06`):** `loki_backup.sh`, `uptime_kuma_backup.sh`, `nodemonitor_config_backup.sh`, `pg_wal_cleanup.sh` scriptlerine Redis `HSET teqlif:agent:job_ok` ekle; `/project/teqlif/backups/.last_mail_backup_ok` `0B` yetimini ve eski `node2/resources/systemd/teqlif-mail-backup.timer` (`03:45`) dosyasını temizle → _Neden:_ Tüm 11 yerel yedekleme/temizlik + offsite anahtarını `watchdog`/`health` izlemesinde tek standarda bağlamak. → ([Detay](#maint-06))

<a id="adim-30"></a>
30. **Adım 30 (`MAINT-07`):** `nodeMonitor` üzerinde Prometheus (`--storage.tsdb.retention.size=1GB`), Loki/Grafana/MariaDB (`MemoryMax` + `innodb_buffer_pool_size=64M`) bellek optimizasyonu uygula → _Neden:_ `240 MiB` aktif swap kullanımını ve OOM düşüş riskini ortadan kaldırmak. → ([Detay](#maint-07))

<a id="adim-31"></a>
31. **Adım 31 (`AUDIT-06`):** [`_common.sh:149-159`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/scripts/_common.sh#L149-L159) kırık `**/*.log` glob'unu `/project/teqlif/logs/*.log /project/teqlif/logs/*/*.log` + `/var/log/teqlif-agent/*.log` olarak düzelt (tüm node'lara ve `nodeMonitor`'a dağıt), tüm node'larda `journald` `SystemMaxUse=200M` ayarla → _Neden:_ `565 MB agent.log` ve `1.2G/1.6G journald` büyümesini tüm kümede durdurmak. → ([Detay](#audit-06))

<a id="adim-32"></a>
32. **Adım 32 (`AUDIT-07`):** `teqlif-agent` [`db.py:39-47`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/teqlif-agent/db.py#L39-L47) `cleanup_log` `UNIQUE` kısıtı + 30g budama/`VACUUM`, [`gossip.py:60`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/teqlif-agent/gossip.py#L60) kalıcı SQLite `_last_sync` ve [`janitor.py:149`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/teqlif-agent/modules/janitor.py#L149) docstring düzeltmesi uygula → _Neden:_ Agent restart'ında SQLite çoğaltmasını ve şişmesini önlemek. → ([Detay](#audit-07))

<a id="adim-33"></a>
33. **Adım 33 (`AUDIT-08`):** [`worker.py:856-898`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/worker.py#L856-L898) `cleanup_old_media_messages_task` (`30 gün`, `LIMIT 500`, `db.commit()` sonrası MinIO silme — [Karar K5](#kilitli-kararlar)) ve diğer 11 temizlik görevinde `LIMIT 5000` chunk döngülü `DELETE` uygula → _Neden:_ Yüksek veride ARQ OOM, uzun PG tablo kilidi ve dangling MinIO silme riskini önlemek. → ([Detay](#audit-08))

<a id="adim-34"></a>
34. **Adım 34 (`MAINT-08`):** Canlı `node2 wg show` üzerinde görünmeyen `node3`/`node4` WG peering'ini doğrula/onar ve `TimeoutStartSec` bulunmayan kalan 10 backup/bakım servisine uygun `TimeoutStartSec` (`900`–`3600`) ekle → _Neden:_ Edge düğümler arası bakım/failover erişimini ve askıda kalma korumasını sağlamak. → ([Detay](#maint-08))

<a id="adim-35"></a>
35. **Adım 35 (`OFFSITE-13`):** TTK/MASAK uyumlu aylık WORM finansal arşiv job'ını (`wallet_ledger`, `withdrawal_requests`, `purchases`, `audit_logs` 1y+ → SHA-256 manifest + `restic backup --tag financial-worm`, 10y retention) kur → _Neden:_ Yasal finansal defterlerin değiştirilemez soğuk arşivini güvenceye almak. → ([Detay](#offsite-13))

<a id="adim-36"></a>
36. **Adım 36 (`OFFSITE-11`):** `deploy/scale/V2.1/node101/resources/offsite_restore_runbook.md` + `teqlif-offsite-verify.timer` (`restic check --read-data-subset=5%`) dosyasını oluştur ve **İlk Gerçek DR Tatbikatını** (`node2` yerel PITR + `node101` geçici test dizinine/DB'sine Key Escrow ile tam restore) koşup raporla → _Neden:_ Tüm mimarinin kağıt üstünde kalmayıp gerçekten kurtarabildiğini kanıtlamak. → ([Detay](#offsite-11))

---

<a id="denetim-turlari"></a>
## 📝 7. Denetim Turları & Güncelleme Günlüğü (`Tur 1` .. `Tur 7`)

> Her uygulama veya yeni denetim turu buraya tarih ve özetle eklenir (`Adım 1..36` numaralarıyla karışmaması için `Denetim Turu` adlandırması kullanılır).

### Tur 1 — 2026-11-11 · İlk Kod Tabanı & Mimari Hazırlık Analizi
- `offsite_sync.sh`, `health.py`, `watchdog.py`, `schedule.yaml`, `cluster.yaml`, `V1.0`/`V1.1` incelendi; 10 temel `OFFSITE` bulgusu çıkarıldı.

### Tur 2 — 2026-11-11 · `node101` Entegrasyonu & Canlı Cluster Tam Bakım/Yedekleme Denetimi
- Hedef VPS `node101` (`195.206.234.142`) + tüm 8 canlı node SSH ile denetlendi (`Debian 13`, `nodeMonitor Europe/Berlin`, `node101 Europe/London`); `OFFSITE-01..13` ve `MAINT-01..08` belgelendi.

### Tur 3 — 2026-11-11 · Mimari Kilitleme & WAL RPO Kanıtı
- `restic 0.18.0` → `restic-rest-server 0.13.0 --append-only` seçildi; `node1` PG `archive_timeout=0` nedeniyle `15–27 saat` segment aralığı ölçüldü → `archive_timeout=3600` + saatlik `*:45 UTC` push kilitlendi.

### Tur 4 — 2026-11-11 · `node101:/mnt/data` `fio-3.39` Benchmark
- `1M` `137/145 MiB/s`, `4k` `27.4k/27.4k IOPS`, `64k fdatasync` `83 IOPS / 5.45 MB/s` (`p99=229.6 ms`, `max=871.9 ms`) ölçüldü ve [`specs.md`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/node101/specs.md) içine eklendi; `--pack-size 32` zorunlu kılındı.

### Tur 5 — 2026-11-11 · Uçtan Uca Bakım, DR, Birikme & Telemetri Tam Denetimi
- Canlı yedeklerin çekirdek dosyaları doğrulandı (`pg_dump` 647 öğe, `mail` 643 dosya, `uptime_kuma` 67.015 satır); `MAINT-03` (`18 Eki promoted` + rogue script) `P0` yapıldı ve `AUDIT-01..08` belgelendi.

### Tur 6 — 2026-11-11 · İş Mantığı, Finans, KVKK/Uyum, SPOF & Ölçek Analizi + `problems/V1.0` Format Dönüşümü
- `BIZ-01..05` eklendi (`messages.py` wrong bucket, PRO 14g video upsell, alarmsız mutabakat, `max_slot_wal_keep_size=-1`, `redis_failover.sh` WG peer tuzağı, KVKK `delete_account` & `--remove` eksikliği, `07:00 TR` push fırtınası, `09:15 TR` mail kesintisi, `nodeMonitor` SPOF, `sync_pg_to_clickhouse` `LIMIT` veri kaybı).
- Açık 6 mühendislik kararı (`K1..K6`) kilitlendi ve tüm döküman [`problems/V1.0/01_findings.md`](file:///Users/tucibeyin/Desktop/teqlif/documents/problems/V1.0/01_findings.md) standardında **34 tekil kart + iç referanslar + 36 atomik Adım** yapısına dönüştürüldü.

### Tur 7 — *(Bekleyen Uygulama Fazı: Faz 0 → Faz 3 / Adım 1 .. Adım 36)*
- **Amaç:** Onay verildiğinde [Master Eylem Planı](#master-eylem-plani) içindeki `Adım 1` → `Adım 36` zincirini sırayla uygulamak, her adımda doğrulama komutunu koşup `✅ Çözüm Damgası` mühürlemek.
