# teqlif Platformu — Offsite Backup (`node101`) ve Sistem Geneli Bakım / Yedekleme Penceresi Bulgular Raporu (V1.2)

**Tarih:** 11 Kasım 2026  
**Sürüm:** `V1.2` *(Geliştirilebilir yaşayan doküman — her analiz/uygulama adımında üzerine eklenir)*  
**Durum:** 🔍 Tasarım Kilitli + **Adım 5 & Adım 6 Tam Teknik + İş/Finans/Uyum Denetimi Tamamlandı** *(İmplementasyon Sonraki Adımda Başlayacak)*  
**Hedef Offsite Sunucusu:** `node101` — `195.206.234.142` (`ssh node101` / DELUXHOST AS214677, Kerkrade NL / Debian 13 `trixie`, `restic 0.18.0` + `restic-rest-server 0.13.0`)  
**Repo Config Yolu:** `deploy/scale/V2.1/node101/` (`specs.md`, `config/`, `resources/`)  
**Şablon:** `documents/problems/V1.0/01_findings.md`  
**Önceki / İlişkili Raporlar:** `documents/backup/V1.0/01_findings.md`, `documents/backup/V1.1/01_findings.md`, `documents/system_timing/V1.0/01_findings.md`, `documents/wallet/V1.0/01_findings.md`, `deploy/scale/V2.1/documents/01_architecture.md`

> **Doküman Kullanım Kuralı (Appendable Convention):** Bu dosya uçtan uca offsite backup mimarisinin (`node2` → `node101`) ve kümedeki **tüm** zamanlanmış bakım, temizlik, ML/batch ve OS bakım pencerelerinin tek ana referansıdır. Yeni adımlar geldikçe mevcut ID'lerin (`OFFSITE-*`, `MAINT-*`, `AUDIT-*`, `BIZ-*`) durumu tablo üzerinden güncellenir ve alt bölümdeki **Devam Analizleri & Güncelleme Günlüğü**'ne eklenir; kod/altyapı değişikliği yalnızca ilgili adım onaylandığında yapılır.

---

## 📌 Önceliklendirme ve Özet Tablosu

### A. Offsite Backup & `node101` Mimari Bulguları

| ID | Seviye | Bileşen / Dosya | Zaaf / Hata / Bulgu Türü | Etki Alanı | Durum |
| :---: | :---: | :--- | :--- | :--- | :---: |
| **OFFSITE-01** | 🔴 **P0 (Kritik)** | `cluster.yaml`, `economics.md`, `node101/specs.md` | MinIO 2g ILM Sonrası Tek-Kopya Riski + `node101` Tek Volume (`vdb`, RAID yok), IPv4-Only ve Root `/` (`6.1 GB` boş) Kısıtı | `node2`+`node1` kaybında veri kurtarma; `node101` disk dolumu veya tek volume arızası | ⬜ Açık |
| **OFFSITE-02** | 🔴 **P0 (Kritik)** | `offsite_sync.sh`, `pg_dump.sh`, `redis_backup.sh`, `node101` (`ext4`) | `rclone sync` ile Ransomware Silme Yayılımı + `node101:/mnt/data` `ext4` Native Snapshot Yokluğu + 7g Retention Kırpması | `node2` ele geçirilir veya erken hata yaşanırsa offsite yedeklerin saat `07:00 UTC`'de silinmesi | ⬜ Açık |
| **OFFSITE-03** | 🔴 **P0 (Kritik)** | `offsite_sync.sh`, `bootstrap_node2.sh`, `secrets.env.template` | İstemci Taraflı Şifreleme (`restic` / `borg` / `rclone crypt`) ve Sunucu Dışı Anahtar Emaneti (Key Escrow) Eksikliği | PII, DM ve finans verisinin `node101` diskinde açık durması veya `node2` ölünce şifreli yedeğin kilitli kalması | ⬜ Açık |
| **OFFSITE-04** | 🔴 **P0 (Kritik)** | `teqlif-offsite-sync.service`, `watchdog.py`, `health.py`, `schedule.yaml` | Üç Katmanlı İzlemede Tam Körlük (`watchdog`, `health`, `OnFailure` yok), Sessiz `exit 0` ve Canlı `node2` Timer Sapması (`disabled` dosya / `active` RAM) | Başarısız, atlanmış veya reboot sonrası duran offsite transferlerinin hiç fark edilmemesi | ⬜ Açık |
| **OFFSITE-05** | 🟠 **P1 (Yüksek)** | `wg_mesh_apply.sh`, `secrets.env.template`, `teqlif-restart.sh`, `node101` | `node101` İçin WireGuard (`10.10.0.101`), Blast-Radius İzolasyonu, UFW/SSH Sertleştirmesi ve Prometheus Monitoring Eksikliği | Web/API/streaming node'larının `node101`'e doğrudan erişim riski; `node101` public SSH ve doluluk körlüğü | ⬜ Açık |
| **OFFSITE-06** | 🟠 **P1 (Yüksek)** | `node101` (`2.9 GiB RAM`, `2 vCPU`, `/mnt/data`) | Düşük RAM (`2.9 GiB`), Tek CPU Sınırı (`Geekbench 676/1165`) ve **`fdatasync` Tail Gecikmesi (`83 IOPS / 5.4 MB/s`, `p99=230ms`)** | Prune/check sırasında OOM Killer; küçük senkron yazmalarda `5.4 MB/s` boğulması; `/` (`9.7 GB`) taşması | ⬜ Açık |
| **OFFSITE-07** | 🟠 **P1 (Yüksek)** | `offsite_sync.sh`, `pg_basebackup.sh`, `pg_receivewal.sh`, `pg_dump.sh` | Offsite Kapsamında PostgreSQL PITR (`pg_basebackup` + `pg_wal`) Eksikliği (24s RPO) + `pg_dump.sh`'ta 7 Eski `.dump.gz` Yetimi | Çifte kayıpta son `03:00` sonrası finansal/cüzdan verisi kaybı ve gereksiz `.dump.gz` birikimi | ⬜ Açık |
| **OFFSITE-08** | 🟠 **P1 (Yüksek)** | `offsite_sync.sh`, `clickhouse_backup.sh`, `health.py`, canlı `node2` | ClickHouse Dizin Uyuşmazlığı + Method 1/2 Devre Dışı (`~285 B` Boş Fallback Arşivler, `teqlif_prod_analytics` Tabloları Canlıda 0 Satır) | Method 1/2 açılsa `/var/lib/clickhouse/backups` offsite'a hiç gitmez; şu an fallback boş arşiv üretiyor | ⬜ Açık |
| **OFFSITE-09** | 🟠 **P1 (Yüksek)** | `nodemonitor_config_backup.sh`, canlı `node2` | **`nodemonitor_config` Dizininde 979 MB TSDB/WAL Sızıntısı** (`prometheus/data` 823 MB + `loki/wal` & `tsdb-shipper` 156 MB) | `--delete-excluded` yokluğu nedeniyle her offsite sync gereksiz ~1 GB şişiyor | ⬜ Açık |
| **OFFSITE-10** | 🟡 **P2 (Orta)** | `teqlif-offsite-sync.service`, `offsite_sync.sh`, `pg_wal_cleanup.sh` | Gündüz `07:00 UTC` (`10:00 TR`) Sync + `IOSchedulingClass=idle`/`Nice=19` Eksikliği + `.tmp`/`.last_*` Filtresizliği | HDD I/O ve ClickHouse/API rekabeti, yarım `.tmp` dosyalarının `node101`'e taşınması | ⬜ Açık |
| **OFFSITE-11** | 🟡 **P2 (Orta)** | `node2/resources/scripts/runbook.sh`, `deploy/scale/V2.1/node101/` | Offsite (`node101` → Yeni `node1`/`node2`) Felaket Kurtarma Runbook'u ve Periyodik Decrypt + Restore Tatbikatı Eksikliği | `node1`+`node2` ortak kaybında yeni makineden hızlı ayağa kalkış prosedürü yok | ⬜ Açık |
| **OFFSITE-12** | 🟡 **P2 (Orta)** | `_common.sh`, `bootstrap_node2.sh`, `bootstrap_node101.sh` (yok) | Bootstrap Eksikleri (`rclone v1.75.1` canlıda var ama pakette yok; `node101`'de `rsync`/`restic`/`ufw`/`wg` hiç yok; `.env.backup` farkları) | Yeniden kurulumda (`node2` veya `node101`) otomasyon kırılması | ⬜ Açık |
| **OFFSITE-13** | 🟢 **P3 (Düşük)** | `documents/wallet/V1.0`, `node101` | Yasal Finansal Arşiv (`financial_archives`) WORM Akışı ve GFS (7g / 4h / 12a) Soğuk Saklama Politikası Eksikliği | 1 yıl+ finansal cüzdan/audit defterinin ayrı şifreli mühürlü arşiv zincirine alınmaması | ⬜ Açık |

### B. Sistem Geneli Bakım, Zamanlama & Donanım Anomalileri

| ID | Seviye | Bileşen / Node | Tespit Edilen Anomali / Çakışma | Etki Alanı | Durum |
| :---: | :---: | :--- | :--- | :--- | :---: |
| **MAINT-01** | 🟠 **P1 (Yüksek)** | `teqlif-agent/modules/cleaner.py` vs `schedule.yaml` | **Çift & Çakışan PG Temizlik Riski:** `cleaner.py` batchsiz `DELETE` atar; **`message_threads` 180d `has_archive=false` siler (DM arşivi 365d!)**; `live_stream_viewers` 3650d vs haftalık task; `03:00` çakışması. *(Canlıda `nodeMonitor` `Environment=` boşsa pasif; `PG_DSN` girildiği an patlar)* | Veri kaybı riski (`message_threads` erken silinmesi), `RowExclusiveLock` & WAL sıçraması | ⬜ Açık |
| **MAINT-02** | 🟠 **P1 (Yüksek)** | `cluster.yaml`, `encoder.py:357`, `teqlif-minio-backup.timer`, `worker.py:4845` | **Video Transfer vs MinIO Backup Çakışması:** `encoder.py` normal diskte `start_utc + 1 = 05:00–07:00 UTC` arası `mc cp` atar (düşük diskte `04:00`); `minio_backup` `05:30 UTC` ve `notify_new_recordings_task` `05:00 & 06:00 UTC` ile doğrudan çakışır | `node1` MinIO üzerinde eşzamanlı yazma/okuma, `node2_confirmed_at` gecikmesi/kaçırma | ⬜ Açık |
| **MAINT-03** | 🔴 **P0 (Kritik)** | `node2` systemd (`redis-failover.timer` + `teqlif-redis-failover.timer`), `redis_failover.sh` | **Canlı `node2` Redis Otomatik Failover Fiilen Çalışmıyor + Zehirlenmiş Flag:** Resmi `teqlif-redis-failover.service` **`Oct 18 15:06`** tarihli `/var/lib/teqlif-redis-failover/promoted` bayrağı yüzünden (`L20-22` `exit 0`) 24 gündür hiç kontrol yapmıyor! Paralel yetkisiz `redis-failover.timer` ise `/usr/local/bin/redis-failover-check.sh` içinde düz metin Redis şifresiyle `root` olarak çalışıyor ve fail durumunda VIP `10.10.0.1/32` / `iptables` / `wg` / Telegram kurmuyor | `node1` Redis çöküşünde otomatik failover gerçekleşmemesi + düz metin sır maruziyeti | ⬜ Açık |
| **MAINT-04** | 🟡 **P2 (Orta)** | `node1`..`node6`, `nodeMonitor`, `node2` OS Timer'ları & `03:00 UTC` | **OS Bakım & `03:00` Çarpışması:** `apt-daily-upgrade` (`06:05–06:50 UTC` backup/ML bitişinde), **`node2` `mdcheck` RAID-1 scrub** (1. Pazar `21:58 UTC` → Pzt `06:46 UTC`), `e2scrub`/`xfs_scrub` (Paz `03:10 UTC`), `nodeMonitor` CET (`UTC+1`) saat kayması, Pazar `03:00` PG yığılması | Disk/I/O ve APT restart kesintilerinin tam sabah yedek/ML penceresine denk gelmesi | ⬜ Açık |
| **MAINT-05** | 🟡 **P2 (Orta)** | `schedule.yaml`, `schedule_loader.py`, `worker.py` | **`schedule.yaml` Yapısal & Yorum Sapmaları:** Üst seviye `backup:` anahtarı yok (backup'lar `batch:` altında!); `cleanup_old_stream_chat_messages_task` hem `schedule.yaml` hem `worker.py:4847`'de (`_SCHEDULE_FUNCTIONS` yokluğu yüzünden tesadüfen çift çalışmıyor); stale yorumlar (`01:30`, `08:30`, `CH delete`, `start:2`, docstring `04:00`) | Yanlış saat kabulü ve tek satır eklemede çift cron riski | ⬜ Açık |
| **MAINT-06** | 🟡 **P2 (Orta)** | `watchdog.py`, `health.py`, `loki_backup.sh`, `uptime_kuma_backup.sh`, `pg_wal_cleanup.sh`, `node2/resources/` | **Watchdog / Sentinel Tutarsızlığı:** `loki`, `uptime_kuma`, `nodemonitor_config` yalnızca dosya sentinel yazar (`job_ok` Redis'e yazmaz); `pg_wal_cleanup` ve `offsite_sync` hiç watchdog'ta yok; `/project/teqlif/backups/.last_mail_backup_ok` (0B yetim); eski `node2/resources/systemd/teqlif-mail-backup.timer` (`03:45 UTC`) | Eksik `job_ok` telemetrisi ve repoda çelişkili timer dosyası | ⬜ Açık |
| **MAINT-07** | 🟡 **P2 (Orta)** | `nodeMonitor` (`1.9 GiB RAM`) | **`nodeMonitor` Bellek Darboğazı:** 2 GiB RAM sunucuda yalnızca `165 MiB` free + **`240 MiB Swap` kullanımda** (`prometheus/data 1.4G + loki 314M`), `MemoryMax` toplamları `~1.4 GB` (`mariadb` + `grafana` hariç) | OOM / yüksek swap gecikmesi riski; offsite aracı burada çalıştırılamaz | ⬜ Açık |
| **MAINT-08** | 🟢 **P3 (Düşük)** | `node2/systemd/*.service`, canlı `node2` `wg show` | **I/O Önceliği ve WG Peer Görünürlüğü:** `IOSchedulingClass=idle`/`Nice=19` 9 backup servisinin yalnız 4'ünde var; `TimeoutStartSec` yalnız `pg_basebackup`'ta; `node2` `wg show` canlıda yalnız 4 aktif peer (`node1, 5, 6, nodeMonitor`) gösteriyor | HDD kuyruğunun diğer backup/offsite görevlerinde önceliksiz kalması; `node3`/`node4` WG sessizliği incelenmeli | ⬜ Açık |

### C. Uçtan Uca Bakım, DR, Birikme & Telemetri Denetimi (Adım 5 — `AUDIT-*`)

| ID | Seviye | Bileşen / Node | Tespit Edilen Eksik / Bozuk İşleyiş / Birikme | Etki Alanı | Durum |
| :---: | :---: | :--- | :--- | :--- | :---: |
| **AUDIT-01** | 🔴 **P0 (Kritik)** | `node2` DR (`runbook.sh`, `pg_basebackup.sh`, `pg_dump.sh`) | **Yerel Felaket Kurtarma (DR) & PITR Tamamen Kırık:** Canlı `node2`'de `pg_lsclusters` boş (`/etc/postgresql/17/main` conf yok), **`postgresql-17-pgvector` kurulu değil** (`pg_restore` `EXTENSION vector` gerektirir!), `/project/teqlif/config/.env.dr` ve `/etc/ssl/teqlif/cf-origin.*` yok; `runbook.sh` `pg_wal.tar.gz`'yi atlayıp **`recovery_target = 'immediate'`** basıyor (PITR kesiliyor); `pg_dumpall --globals-only` yok; `pg_basebackup.sh` non-atomik | `node1` kaybında `node2` DR failover komutunun doğrudan başarısız olması ve 1 dk RPO WAL kaybı | ⬜ Açık |
| **AUDIT-02** | 🟠 **P1 (Yüksek)** | `watchdog.py`, `db.py`, `worker.py`, `reporter.py`, `recorder.py` | **Telemetri & Watchdog Körlüğü:** `_CONTINUOUS_REGISTRY` `train_item2vec_task` & `train_swipe_live_als_task` eksikleri nedeniyle Redis `8 Kas`'ta güncelse de `nodeMonitor` SQLite **`1 Kas`'ta donmuş** (`get_stale_jobs()` ise `IS NOT NULL` nedeniyle hiç çalışmamış işi alarm vermez); `worker.py`'de 10 statik `cron_jobs` + 4 idle-return + `train_listing_quality_model_task` (`n<50`) hiç `_agent_ok` basmıyor; `recorder.node*` (`10080m`) yayında olmayan edge'de falselist riski; `reporter.py` yalnız 5/11 yedek raporluyor | Sessiz task durmalarının alarm üretmemesi + donmuş SQLite sonrası yanıltıcı/sahte stale uyarıları | ⬜ Açık |
| **AUDIT-03** | 🟠 **P1 (Yüksek)** | `nodemonitor_config_backup.sh`, `mail_backup.sh`, `loki_backup.sh`, `clickhouse_backup.sh` | **Yedek Kapsamı Kritik Eksikleri:** Grafana (`/opt/monitor/shared/grafana/` **`521 MB`** — `grafana.db` `3.7 MB` dahil + `/project/shared/config/{grafana.ini,uptime-kuma.env}`) hiç yedeklenmiyor; `mail_backup.sh` `config.toml` (`6.1 KB`), `.env.mail` (`510 B`) ve `acme/` almıyor (`2>/dev/null`, `tar -tzf` kontrolü yok); `loki_backup.sh` `compactor/` & TSDB index almıyor; `clickhouse_backup.sh`'da `teqlif` kullanıcısının `BACKUP` yetkisi yok ve fallback `SHOW CREATE` DDL içermiyor; `node1..6` cert/`.env`/WG yedeği yok | Felaket sonrası Grafana dashboard'ları, mail sunucusu ayarı/TLS, CH şeması ve cluster sırlarının kaybedilmesi | ⬜ Açık |
| **AUDIT-04** | 🟠 **P1 (Yüksek)** | `minio_backup.sh`, `uptime_kuma_backup.sh` | **15g Video Temizliği Eksik + Confirmation Race + Kuma Hijyeni:** `minio_backup.sh` `node2` üzerinde 15 günden eski kayıtları hiç silmiyor (`cluster.yaml:47` `retention_days: 15` yalnızca kağıt üzerinde); `confirm_recordings()` `mc mirror` penceresi sonrası yeni kayıtları yanlış damgalama race riskine sahip; `uptime_kuma_backup.sh` atomik `.tmp`/doğrulama yapmadığı için `13 Ekim` `20 B` boş `.sql.gz` bırakmış ve inline `MYSQL_PWD` geçiriyor | `node2` diskinde kontrolsüz video birikimi, 2g ILM veri kaybı riski ve Kuma DB şifre maruziyeti | ⬜ Açık |
| **AUDIT-05** | 🟠 **P1 (Yüksek)** | `node2` & `node5` ClickHouse, `encoder.py`, `node5:/var/recordings` | **ClickHouse Sistem Log Şişmesi & `node5` `%56` Disk Baskısı:** TTL olmayan `system.*_log` tabloları (`trace_log`, `text_log`, `metric_log`, `asynchronous_metric_log`, `part_log`) canlıda `node2`'de **`2.38 GiB`**, `node5`'te **`3.9 GiB`** (+ `1.5 GiB` `/var/log/clickhouse-server` = **`5.4 GiB`**) tüketiyor! `node5` (`50G`, `%56` dolu) içinde ayrıca `3.2 GiB /root/.cache` ve `encoder.py`'nin silmediği `.log`/0-byte/12 Eki–6 Kas `.mkv`/`.mp4` yetimleri (**`194 MB` `/var/recordings`**) birikmiş | Disklerin gereksiz log ve ham video artıklarıyla dolması (özellikle `node5` `50G` ve canlı yayınlarda `node3/4`) | ⬜ Açık |
| **AUDIT-06** | 🟡 **P2 (Orta)** | `_common.sh` (`logrotate`), `teqlif-agent.service`, `journald` | **Kırık `logrotate` + `agent.log` (~`565 MB`) + Sınırsız `journald`:** `/etc/logrotate.d/teqlif` içindeki `**/*.log` kalıbı `logrotate -d` testinde **eşleşmiyor** (`node1` `redis-core.log` `16 MB` rotate edilmemiş, `nodeMonitor`'da kural hiç yok); `/var/log/teqlif-agent/agent.log` için logrotate yok (`nodeMonitor 103M`, `node2 98.5M`, `node1 90.3M`, `node5 78M`, `node6 71M`, `node3 66M`, `node4 58M`); `journald` default kotasız (`nodeMonitor 1.2G`, `node5 1.6G du`, `node4 622.5M`, `node3 617.9M`, `node6 320.1M`) | Tüm cluster node'larında sessiz ve sınırsız log büyümesi | ⬜ Açık |
| **AUDIT-07** | 🟡 **P2 (Orta)** | `teqlif-agent` (`db.py`, `gossip.py`, `janitor.py`), `bootstrap_node2.sh` | **SQLite Gossip Çoğaltma & Bootstrap Eksikleri:** `db.py` `cleanup_log` tablosunda `UNIQUE` kısıtı yok ve `GossipClient._last_sync` yalnız RAM'de tutulduğundan her agent restart'ında peer satırları tekrar eklenir (budama/`VACUUM` yok); `janitor.py:149` var olmayan `cleanup_actions.sh`'ye atıf yapıyor; `bootstrap_node2.sh:210-214` 7 backup/cleanup timer'ını `enable` etmeyi unutmuş | Prod temizlik kayıtları büyüdüğünde `state.db` şişmesi; `node2` yeniden kurulumda 7 timer'ın kapalı kalması | ⬜ Açık |
| **AUDIT-08** | 🟡 **P2 (Orta)** | `backend/app/worker.py` (`cleanup_*` görevleri) | **Batch'siz PG Silme & Docstring Sapması:** `cleanup_old_media_messages_task` (`L856-898`) tüm kayıtları `.scalars().all()` ile belleğe çeker ve docstring `"3/7 gün"` derken kod **`timedelta(days=60)`** uygular; `cleanup_old_stream_chat_messages_task` dahil 9 temizlik görevi batch'siz tek `DELETE` çalıştırır | Yüksek satır sayısında ARQ worker OOM, uzun PG tablo kilidi ve WAL sıçraması | ⬜ Açık |

### D. İş Mantığı, Finans, KVKK/Uyum & Ölçek Riskleri (Adım 6 — `BIZ-*`)

| ID | Seviye | Bileşen / İş Akışı | Tespit Edilen İş Mantığı / Uyum / Ölçek Riski | Business & Gelir / Risk Etkisi | Durum |
| :---: | :---: | :--- | :--- | :--- | :---: |
| **BIZ-01** | 🔴 **P0 (Kritik)** | `messages.py:292-299` vs `dm_archive_tasks.py:80,94` + `streams.py:351` vs `stream_recording_tasks.py:40,97` | **DM Arşivi Yanlış MinIO Bucket Okuyor + PRO 14g Video Upsell Kırık:** `archive_old_dm_task` arşivleri **`teqlif-dm`** private bucket'a yazar, ancak kullanıcı `GET /{other_user_id}/archive` çağırdığında `messages.py` **public `teqlif` bucket** (`list_object_keys` / `get_object_bytes`) okuduğu için **her zaman boş `[]` döner** (`list_object_keys_dm` yok!). Standart yayıncılara "14 gün hukuki arşiv / PRO'ya geç aç" vaat edilmesine rağmen `node1` MinIO ILM **2. günde** siler ve `streams.py:351` yalnızca `node1` MinIO'dan presign üretir (`404 NoSuchKey`!) | 1 yıl+ DM geçmişinin kullanıcıya tamamen kayıp görünmesi; PRO yükseltmesi sonrası video indirme kırılması; T+14 hakediş ile `node2` 15g saklama arası yalnız 1 gün pay kalması | ⬜ Açık |
| **BIZ-02** | 🔴 **P0 (Kritik)** | `wallet_tasks.py:101-166`, canlı `node1` PG ayarları, `redis_failover.sh:65-68` | **Sessiz Finansal Mutabakat + Sınırsız `max_slot_wal_keep_size` + `wg` İzolasyon Tuzağı:** `daily_financial_reconciliation_task` (`00:00 UTC`) bakiye/çekim tutarsızlığı yakalasa bile **yalnız `logger.warning` atıp `_agent_ok` basar (alarm yok!)** ve yalnız son 30 günü denetler; canlı `node1` PG **`max_slot_wal_keep_size = -1`** olduğu için `node2_receivewal` kesilirse PG WAL diski %100 doldurup prod DB'yi çökertebilir; `redis_failover.sh` promote anında `node2`'de `node1` WG peer'ını `0.0.0.1/32` yapıp WAL/MinIO trafiğini de keser; PG `lock_timeout`/`statement_timeout` `0ms` | Finansal defter sapmalarının fark edilmemesi; yedek sunucu kesintisinde ana prod PG'nin diski doldurup çökmesi | ⬜ Açık |
| **BIZ-03** | 🟠 **P1 (Yüksek)** | `auth.py:1638`, `minio_backup.sh:20`, `analytics_tasks.py`, `listing_tasks.py` | **KVKK/Hesap Silme Boşlukları & `07:00 TR` Push Fırtınası:** `delete_account`, aktif cüzdan/pending çekim kontrolü yapmaz, `teqlif-dm` (`dm-archive/`) içindeki silinmiş kullanıcı mesajlarını temizlemez ve `minio_backup` `--remove` olmadığı için silinen avatar/ilan medyaları `node2`'de süresiz kalır; `04:00–05:00 UTC` (`07:00–08:00 TR`) arası airdrop/ilan/retarget push'ları `pref_key=None` ile `quiet_hours_enabled` ayarını atlar (`process_churn_and_airdrop` ise `users.teqlik_balance + teqlik_transactions` yazar, CH hatasını yutup `_agent_ok` basar) | KVKK silme hakkı ihlali, açık ödemede hesap kilitlenmesi, sabah 07:00 promosyon push yorgunluğu, TTK/MASAK 5–10 yıl finansal arşiv açığı (`V11-10`) | ⬜ Açık |
| **BIZ-04** | 🟠 **P1 (Yüksek)** | `nodeMonitor` SPOF, Prometheus kapsamı, `mail_backup.sh`, `node5` staging | **`nodeMonitor` Tek-Nokta Arıza (SPOF) & Kör Servisler + `09:15 TR` Mail Stop:** Prometheus, Alertmanager, Loki, Uptime Kuma ve `teqlif-agent` Lideri tek `1.9 GiB` VPS'tedir ve dışarıdan (`node1`/`node2`) izleyen hiç Dead Man's Switch yoktur; Prometheus `ClickHouse`, `MinIO`, `Redis Replica`, `pg_receivewal`, `stalwart-mail`'i hiç izlemez; `mail_backup.sh` Türkiye sabahı **`09:15 TR`'de** `stalwart-mail` durdurur (boşta bile `4.9M→5.3M` artıyor, GB ölçekte dakikalara çıkacak); `node5` staging yedeksiz, `node2`'de terk edilmiş `teqlif_staging_analytics` (`25` satır) duruyor | İzleme sunucusu çöktüğünde tüm küme alarmlarının sessiz kalması; sabah mesai başlangıcında OTP/e-posta düşüşü | ⬜ Açık |
| **BIZ-05** | 🟠 **P1 (Yüksek)** | `worker.py:4153,4189,4252`, `listing_tasks.py:84,145`, ölçek ekonomisi | **Yüksek Ölçekte İlk Kırılacak Tıkanma Noktaları (`>50K` Kullanıcı):** `sync_pg_to_clickhouse_task` `LIMIT 500000` (`analytics_events`) veya `LIMIT 200000` (`user_interactions`) dolsa bile `ch:last_sync_at`'ı `now()`'a çekip aradaki veriyi **48s sonra PG'den batch'siz kalıcı siler**; `delete_expired_inactive_listings_task` sınırsız ilanı tek tek siler ve exception yutar; `stale`/`idle` RocksDB + MinIO birikimi `node2` & `node101` (`934G`) kapasite planını bozar | Büyüme anında sessiz BI/analitik veri kaybı, ARQ/PostgreSQL kilit tıkanması ve tahmin dışı disk dolumu | ⬜ Açık |

---

## 🎯 Ana Karar Özeti

> **1. "Offsite backup planlamak gerekir mi?"**
> **Evet — zorunlu ve kritik.** Üretim verisi bugün tek bir sağlayıcıdaki (OVH) iki komşu sunucuya (`node1` ↔ `node2`) ve video tarafında **2 günlük MinIO ILM penceresinden sonra yalnızca `node2`'deki tek kopyaya** dayanmaktadır.
>
> **2. "`node101` ile altyapı buna hazır mı?"**
> **Ağ ve yerel `node2` yedek toplama hattı %80 hazır; ancak `node101` entegrasyonu ve güvenlik katmanları sıfırdan kurulmalıdır.** Canlı denetimde şunlar doğrulanmıştır:
> - **Güçlü Yanlar (`node101` + `node2`):** `node101` DELUXHOST (`AS214677`, Kerkrade NL) üzerinde tamamen **OVH dışı ayrı sağlayıcı/ülkededir**, `node2 ↔ node101` gecikmesi yalnızca **`12.5 ms`**, `1 Gbps` ağ hattı mevcuttur, CPU **`AES-NI ✔`** desteklidir ve `/mnt/data` **`934 GiB` boş alana** sahiptir. `node2`'de canlı veriler şu an yalnızca **~2.1 GB** yer kaplamaktadır ve `pg_receivewal`, `postgresql`, `clickhouse-server`, `teqlif-redis-replica`, `stalwart-mail` servislerinin tamamı aktiftir.
> - **Engelleyici Eksikler:** `node101` şu an **minimal Debian 13** kurulumudur (`wireguard`, `ufw`, `restic`/`rest-server`/`rsync` yok; `/mnt/data` `fio` benchmark'ı tamamlandı ve `137/145 MiB/s` + `27.4k IOPS` ile disk yeterli çıktı, ancak `fdatasync` `p99=230ms` sınırı var), **`2.9 GiB RAM` + `6.1 GB` boş `/` diski** sıkı disiplin ister; `node2` tarafında `offsite_sync.sh` şifresiz/WORM koruması olmayan `rclone sync` kullanır, `pg_basebackup`+`pg_wal`'ı hiç içermez, `nodemonitor_config` ise **979 MB TSDB/WAL sızıntısı** taşır ve 3 izleme katmanı (`watchdog`, `health`, `OnFailure`) tamamen kördür.

---

## 📊 Sistem Geneli Mevcut Donanım, Disk ve Bakım / Yedekleme Penceresi Envanteri

Bu bölüm; kod tabanında (`schedule.yaml`, `worker.py`, `cleaner.py`, `janitor.py`, `encoder.py`, `cluster.yaml`, `node2/systemd/*`) ve canlı cluster'da (`ssh` ile 11 Kasım 2026 `~05:07–05:11 UTC` aralığında gözlemlenen) **gerçekleşen tüm donanım, disk ve zamanlama durumunu** tek tabloda toplar.

### 1. Cluster Geneli Donanım, Disk, Ağ & Bakım Rolü Matrisi

| Node | Sağlayıcı / Konum | Donanım (Spec & Canlı) | RAM / Swap (Canlı) | Disk & Boş Alan (Canlı) | İşletim Sistemi / TZ | Ağ / WG IP | Bakım & Yedekleme Rolü |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **`node1`** | OVH Dedicated | `6c/12t`, `32GB RAM`, `2×512GB NVMe` | `31 GiB` (`19 GiB` avail) | `/dev/md3` **`467G`** (`17G` kullan., **`426G` boş**, `%4`). PG: `1.1G`, MinIO: `360K`, Log: `16M` | Debian 13 (`trixie`) / `UTC` | `10.10.0.1` | Primary DB (PG 17.11), Redis Core, MinIO, FastAPI, ARQ (`default`, `critical`, `video`) |
| **`node2`** | OVH Dedicated (Saarbrücken DE) | `4c/8t` Xeon D-2123IT @ 2.20GHz, `32GB RAM`, `2×4TB HDD` | `31 GiB` (`25 GiB` avail) / `1.0 GiB` Swap | `/dev/md3` RAID-1 HGST **`3.6T`** (`8.9G` kullan., **`3.4T` boş**, `%1`). Backups: `~2.1G` | Debian 13 (`trixie`) / `UTC` | `10.10.0.2` | Merkezi Yerel Yedekleme, WAL Archive, DR Standby, Redis Replica, ClickHouse, Stalwart Mail |
| **`node3`** | OVH VPS | `6 vCPU`, `12GB RAM`, `100GB` | `11 GiB` (`10 GiB` avail) | **`99G`** (`85G` boş). `/var/recordings/{raw,encoded}` | Debian 13 (`trixie`) / `UTC` | `10.10.0.3` | LiveKit Edge 1 + Video Encode (`05:00–07:00 UTC` transfer → `node1` MinIO) |
| **`node4`** | OVH VPS | `6 vCPU`, `12GB RAM`, `100GB` | `11 GiB` (`10 GiB` avail) | **`99G`** (`85G` boş). `/var/recordings/{raw,encoded}` | Debian 13 (`trixie`) / `UTC` | `10.10.0.4` | LiveKit Edge 2 + Video Encode (`05:00–07:00 UTC` transfer → `node1` MinIO) |
| **`node5`** | zap-hosting Lifetime | `4 vCPU`, `8GB RAM`, `50GB` | `7.8 GiB` (`5.5 GiB` avail) / `4.0 GiB` Swap (`0B`) | `/dev/sda1` **`50G`** (`27G` kullan., **`22G` boş**, `%56`) | Debian 13 (`trixie`) / `UTC` | `10.10.0.5` | Staging + AI Proxy (`10.10.0.5:8001`) + Redis VIP |
| **`node6`** | zap-hosting Lifetime | `4 vCPU`, `4GB RAM`, `50GB` | `3.8 GiB` (`3.2 GiB` avail) / `4.0 GiB` Swap (`0B`) | `/dev/sda1` **`50G`** (`18G` kullan., **`30G` boş**, `%37`) | Debian 13 (`trixie`) / `UTC` | `10.10.0.6` | AI Proxy 2 + Redis VIP |
| **`nodeMonitor`** | Netcup | `2 vCPU`, `2GB RAM`, `60GB` | `1.9 GiB` (`165Mi` free / `866Mi` avail) / **`240Mi` Swap aktif** | `/dev/vda3` **`58G`** (`13G` kullan., **`43G` boş**). Prom: `1.4G`, Loki: `314M` | Debian 13 (`trixie`) / **`Europe/Berlin` (`UTC+1/+2`)** | `10.10.0.99` | Prometheus, Loki, Grafana, Uptime Kuma, `teqlif-agent` Lider (`watchdog`, `health`, `janitor`, `cleaner`) |
| **`node101`** | **DELUXHOST** (`AS214677`, Kerkrade NL) | `2 vCPU` Xeon E5-2699 v4 @ 2.20GHz (**AES-NI ✔**), Geekbench `676/1165` | **`2.9 GiB`** (`2.6 GiB` avail) / `1.0 GiB` Swap (`/swapfile`) | `vda` `10G` SSD (`/` `9.7G`: `3.3G` kullan., **`6.1G` boş** `%36`, 64k ~1.6 GB/s) + **`vdb` `1000G` (`/mnt/data` `ext4` `984G`: `2.1M` kullan., **`934G` boş** `%1`; `fio` 1M `137/145 MiB/s`, 4k `27.4k` IOPS, `fdatasync` `83/s`)** | Debian 13 (`trixie`), Kernel `6.12.111` / **`Europe/London` (`UTC` önerilir)** | `195.206.234.142` (IPv4-only; IPv6 Offline; WG `10.10.0.101` planlı) | **Onaylı Offsite Hedefi** (`restic-rest-server 0.13.0 --append-only`; `12.5 ms` ping, `~1 Gbps` EU ağ) |

---

### 2. Canlı `node2` `/project/teqlif/backups/` Gerçek Disk Dökümü ve Anomaliler (11 Kasım 2026)

| Dizin | Canlı Boyut | Saklama Polit. (Script) | Gerçek Durum ve Tespit Edilen Anomaliler |
| :--- | ---: | :--- | :--- |
| `nodemonitor_config` | **`979 MB`** | Kalıcı (süresiz) | 🔴 **`prometheus/data` (`823 MB`, 18 Ekim'den kalma) + `loki/` (`156 MB`, 2 Ekim–11 Kasım arası `wal/`, `tsdb-shipper-active/`, `tsdb-shipper-cache/` dahil!)** — `rsync --delete-excluded` olmadığı için kalıcı sızıntı. Gerçek config (`teqlif-config` `12K` + `alertmanager` `8K` + YAML) `< 1 MB`. |
| `pg_wal` | **`561 MB`** | En eski `pg_basebackup`'a kadar | 🟡 `34` WAL segmenti (`545 MB`), günlük `06:30` `pg_archivecleanup` ile temizleniyor (`000000010000000000000080` referans). Offsite kapsamı dışında! |
| `loki` | **`393 MB`** | `90 gün` | Normal (`chunks/`, günlük ~9–15 MB artış). `job_ok` Redis'e yazmıyor; yalnızca `.last_backup_ok`. |
| `stalwart` | **`136 MB`** | `90 gün` | Günlük `tar.gz` ~3.1–5.3 MB (`1-2 sn` `stalwart-mail` stop/start ile). Kök `/project/teqlif/backups/.last_mail_backup_ok` içinde 18 Ekim'den kalma `0 byte` stray dosya var. |
| `uptime_kuma` | **`14 MB`** | `180 gün` | Günlük `~588 KB` `.sql.gz`. `job_ok` Redis'e yazmıyor. |
| `pg_basebackup` | **`14 MB`** | Son `2` adet (~14 gün) | Haftalık Pazar `02:00 UTC` (~`6.7 MB`/adet gzip). Offsite kapsamı dışında! |
| `pg_dump` | **`8.2 MB`** | `7 gün` | Günlük `.dump` ~`740 KB`. 🔴 **10-2..10-8 tarihli 7 adet eski `.dump.gz` (`~236 KB`/adet) asla silinmiyor** çünkü `pg_dump.sh:26` yalnızca `-name "teqlif_*.dump"` eşleştiriyor. |
| `redis` | **`2.9 MB`** | `7 gün` | Günlük `~328 KB` `.rdb.gz` (`redis-replica` BGSAVE). |
| `clickhouse` | **`40 KB`** | `7 gün` | 🔴 Method 1 (`clickhouse-backup` yok) ve Method 2 (`/var/lib/clickhouse/backups` boş `total 8`) çalışmıyor; Method 3 fallback her gün ~`285 byte` boş `.tar.gz` üretiyor (`teqlif_prod_analytics` 7 tablosu da 0 satır, `teqlif_staging_analytics` 25 satır). `clickhouse_backup.log` yok (journal'a yazıyor). |
| `minio` | **`12 KB`** | `ILM=2g` (fail→`7g`) | `teqlif` (`4K`) + `teqlif-dm` (`4K`); loglarda `0 B` transfer, ILM `db3tiuskndq8as06c0e0` güncellendi, `node2_confirmed_at set: 0 kayıt`. |
| **TOPLAM** | **`~2.1 GB`** | — | Gerçek temiz yedek çekirdeği (`nodemonitor` TSDB çöpü hariç) şu an **~1.1 GB**. |

---

### 3. Sistem Geneli 24 Saatlik Kronoloji (UTC ve Türkiye `UTC+3`)

> **Önemli Zaman Dilimi Notu:** `node1`..`node6` **UTC** kullanır; **`nodeMonitor` OS saat dilimi `Europe/Berlin` (`UTC+1` kış / `UTC+2` yaz)**, **`node101` OS saat dilimi ise şu an `Europe/London` (`UTC` kış / `UTC+1` yaz)** dir. Kurulum sırasında `node101` saat dilimi `UTC` yapılmalı veya systemd timer'larda mutlaka açık `... UTC` kullanılmalıdır. Türkiye saati yıl boyu **`UTC+3`** dür.

#### Katman S — 7/24 Sürekli ve Dakikalık Görevler

| Periyot | Bileşen / Dosya | Görev | Host | Donanım / Kaynak Tüketimi ve Not |
| :--- | :--- | :--- | :--- | :--- |
| Sürekli | `teqlif-pg-receivewal.service` | `pg_receivewal --no-sync` (`node2_receivewal` slot) | `node2` ← `node1` | WG üzerinden canlı WAL stream; aktif ve çalışıyor |
| `5 sn` | `teqlif-agent` (`health`, `leader`, `watchdog`, `cleaner`, `janitor`) | HW metrik toplama, heartbeat, liderlik | Tümü + `nodeMonitor` | Lider yalnız `nodeMonitor` (`PG_DSN` şimdilik boş) |
| **`10 sn`** | **`redis-failover.timer` + `teqlif-redis-failover.timer`** | Redis Core sağlık kontrolü | **`node2`** | 🔴 **DUPLICATE: İki ayrı timer aynı anda her 10 sn çalışıyor (`MAINT-03`)** |
| `10 sn` | `teqlif-redis-vip.timer` | Redis VIP senkronizasyonu | `node3`, `node4`, `node5`, `node6` | Hafif `redis-cli`/VIP check |
| `10 sn` | `worker.py:4834` | `direct_sale_overdue_check_task` | `node1` | Hafif PG + Redis güncelleme |
| `30 sn` | `worker.py:4832` | `flush_clickhouse_buffers_task` | `node1` → `node2` | Redis buffer → ClickHouse batch insert |
| `2 dk` | `worker.py:4840, 4955` | `cleanup_stale_streams_task`, `stream_concat_task` | `node1` | `video` bulkhead (`max_jobs=2`, timeout `1800s`) |
| `4 dk` | `worker.py:4838` | `refresh_i18n_cache_task` | `node1` | Hafif bellek/Redis önbellek |
| `5 dk` | `worker.py:4836` | `flush_interactions_to_db` | `node1` | Redis → PG batch |
| `10 dk` | `worker.py:4830` | `sync_ad_campaigns_task` | `node1` | Reklam kampanya senkronizasyonu |
| `15 dk` | `worker.py:4824–4826` | `cleanup_ghost_calls_task`, `check_search_alerts_task`, `:05/:20/:35/:50 invalidate_swipe_live_configs_task` | `node1` | DB/Redis sorgu |
| `20 dk` | `worker.py:4828` | `sync_swipelive_interests_task` | `node1` | İlgi alanı senkronu |
| `30 dk` (`:00,:30`) | `worker.py:4842, 4849` | `expire_recordings_task`, `retry_failed_chat_dumps_task` | `node1` | Yayın kayıt state `available → expired` |
| `60 dk` (`:00`) | `worker.py:4819–4820` | `cleanup_expired_stories_task`, `cleanup_hype_highlights_task` | `node1` | MinIO + PG hikaye/highlight temizliği |
| `60 dk` (`:15`) | `worker.py:4843` | `archive_recordings_task` | `node1` | MinIO ILM sonrası `expired → archived` |
| `60 dk` (`:45`) | `worker.py:4822` | `backfill_listing_quality_scores_task` | `node1` | İlan kalite skoru |

#### Katman G — Günlük Bakım, Temizlik, ML ve Yedekleme Penceresi (`00:00 – 16:00+ UTC`)

| UTC | TR (`+3`) | Kaynak / Katman | İş / Timer Adı | Host / Hedef | Gün | Not & Çakışma Analizi |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `00:00` | `03:00` | `schedule.yaml` (ARQ) | `daily_financial_reconciliation_task` | `node1` (PG) | Her gün | Gece yarısı wallet mutabakatı |
| `00:00` | `03:00` | `cleaner.py` *(koşullu)* | `notifications` (`30d, is_read`) DELETE | `nodeMonitor` → PG | Her gün | ⚠️ `PG_DSN` doluysa batchsiz; ARQ `03:00` ile çifte silme (`MAINT-01`) |
| `00:00–00:55` | `03:00–03:55` | Debian/Ubuntu OS | `dpkg-db-backup`, `crowdsec-hubupdate`, `logrotate` | Tüm node'lar (`node2` `00:43`, `node5` `00:52`, `node6` `00:55`) | Her gün | Log rotate & paket DB |
| `00:05` | `03:05` | `schedule.yaml` (ARQ) | `reset_monthly_withdrawal_quota_task` | `node1` (PG) | **Ayın 1'i** | PRO çekim kotası sıfırlama |
| `00:05–00:07` | `03:05–03:07` | `cleaner.py` *(koşullu)* | `analytics_events 90d`, `user_interactions 90d` | `nodeMonitor` → PG | Her gün | ⚠️ `schedule.yaml` haftalık Pzt/Sal `05:00` ile çakışır (`MAINT-01`) |
| `00:06–01:40` | `03:06–04:40` | OS `fstrim.timer` | SSD TRIM (`node2` `00:06`, `node5` `00:44`, `node6` `01:39`) | `node2, 5, 6` | **Pazartesi** | I/O bakım |
| `01:00–01:10` | `04:00–04:10` | `cleaner.py` *(koşullu)* | `listing_offers 60d`, `live_stream_viewers 3650d` | `nodeMonitor` → PG | Her gün | ⚠️ 10 yıl vs haftalık silme çelişkisi (`MAINT-01`) |
| `01:50` | `04:50` | `schedule.yaml` (ARQ) | `sync_pg_to_clickhouse_task` | `node1` → `node2` CH | Her gün | `schedule.yaml` "01:30 CH backup biter" yorumu hatalı (CH `03:20`) |
| `02:00` | `05:00` | `node2` systemd | **`teqlif-pg-basebackup.timer`** (`--max-rate=40M`, `~4 sn` şu an) | `node1` → `node2` | **Pazar** | WG ~320 Mbps. `schedule.yaml:260`'da "08:30" yorumu hatalı |
| `02:00–02:20` | `05:00–05:20` | `cleaner.py` *(koşullu)* | `exchange_rates`, `live_streams`, `search_alerts`, `message_threads` (`180d, !has_archive`), `listing_impressions` | `nodeMonitor` → PG | Her gün | 🔴 Pazar `02:00` `pg_basebackup` ile çakışır; **`message_threads 180d` veri silme tuzağı!** |
| `02:10 UTC` | `05:10` | OS `e2scrub_all.timer` | `e2scrub` (`nodeMonitor` `03:10 CET = 02:10 UTC`) | `nodeMonitor` | **Pazar** | LVM snapshot yoksa skip / dosya sistemi taraması |
| `02:15` | `05:15` | `schedule.yaml` (ARQ) | `release_pending_earnings_task` | `node1` (PG) | Her gün | T+14 bekleyen → çekilebilir bakiye (`pg_basebackup` `02:00` sonrası) |
| `02:30–02:45` | `05:30–05:45` | `schedule.yaml` (ARQ) | `compute_analytics_cache_task`, `precompute_premium_user_analytics_task` | `node1` / CH | Her gün | `01:50` sync bittikten sonra |
| `03:00` | `06:00` | `node2` systemd | **`teqlif-pg-dump.timer`** (`-Fc`, `Nice=19`, `IO=idle`) | `node1` → `node2` | Her gün | 🔴 **Yığılma (`MAINT-04`)**: Aynı dakikada PG dump + 2 günlük temizlik + Pazar `archive_old_dm_task` + (`cleaner` `stream_recordings`) |
| `03:00` | `06:00` | `schedule.yaml` (ARQ) | `cleanup_old_notifications_task`, `cleanup_old_stream_likes_task`, **`Pazar: archive_old_dm_task`** | `node1` (PG/MinIO) | Her gün / **Paz** | PG kilit & WAL yükü `pg_dump` anına biner |
| `03:10` | `06:10` | `schedule.yaml` (ARQ) | `check_expired_pro_users_task` | `node1` (PG) | Her gün | PRO expiry sigortası (`03:00`'dan 10 dk ötelendi) |
| `03:10` | `06:10` | OS `e2scrub`/`xfs_scrub` | Disk scrub (`node1, 2, 5, 6`) | `node1, 2, 5, 6` | **Pazar** | `pg_dump` sonrasına/sırasına yakın disk taraması |
| `03:20` | `06:20` | `node2` systemd | **`teqlif-clickhouse-backup.timer`** (`Nice=19`, `IO=idle`) | `node2` | Her gün | `schedule.yaml` `job_ok: clickhouse_backup` (şu an fallback ~285B) |
| `03:20–03:50` | `06:20–06:50` | `schedule.yaml` (ARQ) | `compute_seller_badges`, `calculate_user_budgets`, `compute_trust_scores` (`03:20`); `user_interests`, `trending_categories` (`03:40`); `user_condition_prefs` (`03:50`) | `node1` / `node2` CH | Her gün | Hafif/orta analitik okumalar |
| `03:40` | `06:40` | `node2` systemd | **`teqlif-redis-backup.timer`** (`BGSAVE`, `Nice=19`, `IO=idle`) | `node2` replica | Her gün | Local RDB snapshot + gzip |
| `03:55` | `06:55` | `schedule.yaml` (ARQ) | `populate_foryou_feed_task` (1. koşum; 2. koşum `15:55 UTC`) | `node1` (Redis) | Her gün | Feed ön-ısıtma |
| `04:00` | `07:00` | `cluster.yaml` + `encoder` | **Acil (Düşük Disk) Video Transfer Başlangıcı** (`free_gb < 15`) | `node3, 4` → `node1` MinIO | Her gün | Normalde `05:00` başlar (`encoder.py:357`) |
| `04:00–04:30` | `07:00–07:30` | `schedule.yaml` & `worker` | `compute_trending_listings`, `process_churn_and_airdrop` (`04:00`); `optimize_notification_timing` (`04:10`); `deactivate_expired_listings` (`04:15`); `delete_expired_inactive_listings` (`04:20`); `cleanup_old_impressions`, `rebuild_faiss_index`, `cleanup_old_stream_chat_messages` (`04:30`) | `node1` | Her gün | FAISS `4:30` + ilan temizliği; `chat_messages` iki yerden tanımlı (`MAINT-05`) |
| `05:00–07:00` | `08:00–10:00` | `cluster.yaml` + `encoder` | **Normal Video Transfer Penceresi** (`start_utc + 1` → `05:00–07:00 UTC`) | `node3, 4` → `node1` MinIO | Her gün | 🔴 **`05:30` `minio_backup` ile doğrudan çakışır (`MAINT-02`)!** |
| `05:00–05:15` | `08:00–08:15` | `schedule.yaml` (ARQ) | Günlük: `nsfw_backfill`, `backfill_listing_embeddings`, `hesitation_retarget` (`05:00`); `cleanup_old_media_messages`, `cleanup_hidden_messages` (`05:10`). **Haftalık (`05:00`):** Pzt `cleanup_old_analytics`, Sal `user_interactions`, Per `stream_viewers`, Cum `calls`, Cmt `listing_offers`, Paz `empty_message_threads` + `run_ml_training_pipeline` (`05:00`), Paz `cleanup_inactive_search_alerts` (`05:15`). **Ayın 1'i:** `cleanup_old_exchange_rates` (`05:00`), `cleanup_old_streams` (`05:10`) | `node1` | Gün/Hf/Ay | CPU-yoğun ARQ bloku başlar (NOT: `cleanup_old_analytics` PG siler, CH değil!) |
| `05:00 & 06:00` | `08:00 & 09:00` | `worker.py:4845` | `notify_new_recordings_task` | `node1` | Her gün | Yorum "transfer penceresi `05:00`'de biter" der ama `cluster.yaml` `07:00`'ye kadar sürer! |
| `05:15–05:45` | `08:15–08:45` | `schedule.yaml` (ARQ) | ML Eğitim: Pzt/Çar/Cum `train_bpr_task` (`05:15`), Pzt `train_churn_model_task` (`05:45`), Çar `train_kmeans_cold_start_task` (`05:45`) | `node1` | Pzt/Çar/Cum | CPU/RAM yoğun (`~06:30 UTC`'de biter) |
| **`05:30`** | **`08:30`** | `node2` systemd | **`teqlif-minio-backup.timer`** (`mc mirror`, ILM=`2d`, `node2_confirmed_at`, `Nice=19`, `IO=idle`) | `node1` → `node2` | Her gün | 🔴 **Transfer (`05:00–07:00`) devam ederken mirror yapar (`MAINT-02`)!** |
| `05:40 UTC` | `08:40` | OS `apt-daily-upgrade` | `apt-daily-upgrade` on **`nodeMonitor`** (`06:40 CET`) | `nodeMonitor` | Her gün | Güvenlik güncelleme / servis restart |
| **`06:00`** | **`09:00`** | `node2` systemd | **`teqlif-loki-backup.timer`** (`rsync --ignore-existing`) | `nodeMonitor` → `node2` | Her gün | `Nice=19`/`IO=idle` YOK, Redis `job_ok` YOK |
| **`06:05`** | **`09:05`** | `node2` systemd | **`teqlif-uptime-kuma-backup.timer`** (`mysqldump | gzip`) | `nodeMonitor` → `node2` | Her gün | `Nice=19`/`IO=idle` YOK, Redis `job_ok` YOK |
| `06:05–06:50` | `09:05–09:50` | OS `apt-daily-upgrade` | `apt-daily-upgrade` (`node3 06:05`, `node1 06:21`, `node6 06:36`, `node2 06:37`, `node5 06:49`, `node4 06:45`) | `node1..6` | Her gün | ⚠️ `node2` `06:37` upgrading tam `pg_wal_cleanup` (`06:30`) ile `offsite_sync` (`07:00`) arasına girer |
| **`06:10`** | **`09:10`** | `node2` systemd | **`teqlif-nodemonitor-config-backup.timer`** (`rsync --delete`) | `nodeMonitor` → `node2` | Her gün | 🔴 **`979 MB` TSDB/WAL sızıntısı biriktirir (`OFFSITE-09`)!** |
| **`06:15`** | **`09:15`** | `node2` systemd | **`teqlif-mail-backup.timer`** (`stalwart-mail` stop ~2s + `tar.gz`) | `node2` | Her gün | Repodaki `node2/resources/systemd/...timer` `03:45` eski kalıntı |
| **`06:30`** | **`09:30`** | `node2` systemd | **`teqlif-pg-wal-cleanup.timer`** (`pg_archivecleanup`) | `node2` | Her gün | Watchdog/sentinel YOK (`MAINT-06`) |
| `06:46` *(1. Pzt)* | `09:46` | OS `mdcheck_continue` | `mdadm` RAID-1 parity kontrol devamı (`node2`) | `node2` | **Her ay 1. Pazartesi** | ⚠️ **Tam `07:00` offsite başlangıcına denk gelen ağır HDD read yükü!** |
| **`07:00`** | **`10:00`** | `node2` systemd | **`teqlif-offsite-sync.timer`** *(dosya `disabled`, RAM `active`!)* | `node2` → **(boş `SKIP`)** | Her gün | 🔴 Her sabah `07:00`'de `SKIP` yazıp çıkıyor; TR saati `10:00` mesai içi! |
| `07:35` *(1. Paz)* | `10:35` | OS `mdcheck` | `node1` NVMe RAID scrub (`certbot` `09:33` günlük) | `node1` | Ayın 1. Pazarı | Disk scrub |
| `15:55` | `18:55` | `schedule.yaml` (ARQ) | `populate_foryou_feed_task` (2. koşum — prime-time önü) | `node1` | Her gün | Akşam trafiği hazırlığı |
| `21:58` *(1. Paz)* | `00:58` | OS `mdcheck_start` | `node2` `mdadm` RAID-1 kontrol başlangıcı (6 saat sürer, `06:46`'da devam) | `node2` | Ayın 1. Pazarı | 2×3.6TB HDD scrub |

---

## 🔍 Detaylı Bulgular ve Çözüm Reçeteleri

### OFFSITE-01 · 🔴 P0 (Kritik) · Tek Sağlayıcı Bağımlılığı (`node101` ile Çözülüyor), MinIO 2g ILM ve `node101` Tek-HDD Riskleri

#### 1. Sorunun Tanımı ve Risk Analizi
- **OVH Tek-Sağlayıcı Riski (`node1` + `node2`):** Her iki sunucu da OVH hesabında/ağında duruyor. Video kayıtları için `cluster.yaml:51` üzerinde `minio_expiry_days: 2`, `minio_backup.sh:39` üzerinde `MINIO_ILM_NORMAL_DAYS=2` ayarlı. Kayıt 2 gün içinde `node1` MinIO'dan silindiğinde yalnız `node2`'de kopyası kalıyordu (`V1.1/01_findings.md`).
- **`node101` Bunu Nasıl Çözer ve Hangi Riskler Kalır?** `node101` (DELUXHOST `AS214677`, Kerkrade NL) eklendiğinde **sağlayıcı + fatura/hesap + ülke/veri merkezi izolasyonu** tam olarak sağlanır. Ancak **`node101` canlı denetimde 3 yeni donanım gerçeği** tespit edilmiştir:
  1. `/mnt/data` (`/dev/vdb`) **tek bir virtio volume** (`984G`, `ROTA=1`, `ext4`); `node2`'deki gibi yerel RAID-1 değildir. **Adım 4'te ölçülen `fio` testi** `137/145 MiB/s` sıralı ve `27.4k/27.4k IOPS` rastgele 4K performans vermiş olsa da tek sağlayıcı/tek volume riskinden dolayı **`node101` birincil tek kopya değil, 3-2-1 kuralının "1 offsite kopyası"** olarak konumlandırılmalıdır.
  2. Root diski `/dev/vda3` yalnız **`9.7 GB`** (`3.3G` dolu, **`6.1G` boş**). Yedek temp dosyası, repo veya rclone/restic önbelleği yanlışlıkla `/tmp` veya `~/.cache`'e düşerse root disk dakikalar içinde dolar ve SSH dahil sistem kilitlenir.
  3. **`node101` IPv4-only'dir (`195.206.234.142`, IPv6 Offline)**. Araç konfigürasyonlarında Dual-Stack/IPv6 binding kullanılmamalıdır.

#### 2. Çözüm / Mimari Reçete
1. Video kayıtları için `node1` MinIO → `node2` mirror tamamlanıp `node101`'e **en az bir başarılı offsite snapshot** alınmadan `node2_confirmed_at` / ILM 2 gün mekanizmasına aşırı güvenmemek; ilk `offsite` kopyası yazılana dek kritik kayıtları korumak veya günlük `offsite_sync`'in MinIO'yu önceliklendirmesi.
2. `node101`'de **`/mnt/data`** üzerine ayrı dizin hiyerarşisi (`/mnt/data/restic-repo`, `/mnt/data/cache`, `/mnt/data/tmp`, `/mnt/data/logs`) kurmak; `TMPDIR=/mnt/data/tmp`, `RESTIC_CACHE_DIR=/mnt/data/cache/restic` tanımlayarak root (`/`) diske byte dahi yazmamak.
3. ~~Üretime geçmeden önce `/mnt/data` üzerinde `fio` IOPS + sıralı yazma + fsync testi koşmak (`node101/specs.md`'ye eklemek)~~ → **Adım 4'te tamamlandı (`specs.md` güncellendi).**

---

### OFFSITE-02 · 🔴 P0 (Kritik) · `rclone sync` Yıkıcı Senkronizasyon + `ext4` Native Snapshot Eksikliği

#### 1. Sorunun Tanımı ve Arıza Modu
`deploy/scale/V2.1/node2/resources/scripts/offsite_sync.sh:61`:
```bash
rclone sync "${src}" "${DEST}/$(basename "${src}")" \
```
`rclone sync` **destrüktif tek yönlü ayna**dır: kaynakta silinen dosya hedeften de silinir.
- `node2` root/SSH ele geçirilirse (`rm -rf /project/teqlif/backups/*` veya şifreleme) bir sonraki `07:00` sync `node101`'deki iyi yedekleri de imha eder.
- `pg_dump.sh:26` ve `redis_backup.sh:31` **yalnızca 7 gün**, `clickhouse_backup.sh:58` **7 gün** yerel tutar. Sync varsa `node101`'de de 8 günlük geçmiş oluşmaz; sessiz veri bozulması 8. günde geri dönülemez olur.
- Ayrıca canlı `node101`'de `/mnt/data` **`ext4`** formatındadır — ZFS/Btrfs gibi sunucu tarafında sıfır maliyetli read-only snapshot alamaz!

#### 2. Çözüm / Refactoring Reçetesi
`node101` gibi kontrolümüz altındaki bir VPS için düz `rclone sync` yerine immutable bir model seçilmelidir *(Adım 3'te **Model A: `restic` + `rest-server --append-only`** onaylandı; detaylar Bölüm 🏗️'de)*:
1. **Model A *(Önerilen)* — `restic` + `rest-server --append-only` (WireGuard üzerinden HTTP REST):**
   - `node101`'de `rest-server --append-only --listen 10.10.0.101:8000 --path /mnt/data/restic-repo` systemd servisi olarak çalışır (`no-auth` değil `--htpasswd-file` veya WG IP + basic auth ile).
   - `node2`, `restic backup` ile **ekleme (append)** yapabilir ancak `--append-only` bayrağı nedeniyle **`forget` / `prune` / geçmiş snapshot silme API çağrıları sunucu tarafından reddedilir**!
   - Eski snapshot temizliği (`forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune`) **yalnızca `node101` içindeki yerel bir systemd timer ile** yapılır — yani `node2` tam ele geçirilse bile `node101`'deki geçmiş yedekleri silemez!
2. **Model B *(Alternatif)* — `borg` (`borg serve --append-only`) veya `node101` Pull (`node101` → `node2` read-only `rrsync`)**:
   - `node2` hiçbir write/delete SSH key'ine sahip olmaz; `node101` saatlik/gecelik pull çeker veya `borg serve --append-only --restrict-to-path /mnt/data/borg-repo` ile yalnız append kabul eder.

---

### OFFSITE-03 · 🔴 P0 (Kritik) · İstemci Taraflı Şifreleme & Sunucu Dışı Anahtar Emaneti Eksikliği

#### 1. Sorunun Tanımı ve Arıza Modu
- Mevcut `offsite_sync.sh` şifrelemesiz `rclone sync` yapar. `pg_dump` (`teqlif_*.dump`), `stalwart` (kullanıcı e-postaları), `minio` (`teqlif-dm` medyaları), `nodemonitor_config` (`/project/teqlif/config/` içindeki tüm env/secret'lar!) şifrelenmeden `node101` diskine yazıldığında, üçüncü parti KVM host (DELUXHOST) düzeyinde tüm platform sırları ve PII okunabilir hale gelir.
- Şifreleme parolası yalnız `node2` (`/project/teqlif/config/.env.backup` veya `~/.config/rclone`) içinde saklanırsa `node2` yandığında **`node101`'deki tüm veriler kurtarılamaz** (key loss deadlock).

#### 2. Çözüm / Refactoring Reçetesi
1. `restic` (yerleşik AES-256-CTR + Poly1305, AES-NI ile `node101` ve `node2`'de donanım hızlandırmalı) veya `borg` (`repokey-blake2`) / `rclone crypt` ile **istemci tarafında (`node2` RAM'inde) şifreleme** zorunlu kılınmalı.
2. **Üçlü Anahtar Emaneti (Key Escrow):** Repo parolası/master key mutlaka **en az 2 sunucu dışı fiziksel/bağımsız ortamda** (ör. yerel Mac Password Manager + offline şifreli USB / kağıt çıktı + ayrı yönetici kasası) tutulmalıdır; repo içi `.env` / Git'e asla commit edilmemelidir.
3. Kurulum sonrası doğrulama testinde yalnızca şifreyle sıfır bir dizine restore edebilme (anahtarsız sunucu kurtarma simülasyonu) şart koşulmalıdır.

---

### OFFSITE-04 · 🔴 P0 (Kritik) · Üç Katmanlı İzleme Körlüğü + `OnFailure` Eksikliği + Canlı `node2` Timer Sapması

#### 1. Sorunun Tanımı ve Kanıtlar
1. **Canlı `node2` Çelişkisi:** `offsite_sync.sh:4` ve `01_architecture.md` timer'ın "devre dışı" olduğunu yazar. Canlı denetimde `systemctl status teqlif-offsite-sync.timer`:
   - `Loaded: loaded (/etc/systemd/system/teqlif-offsite-sync.timer; disabled; preset: enabled)` (reboot'ta başlamaz!)
   - `Active: active (waiting) since Sun 2026-10-18 16:37:43 UTC` (şu an her gün `07:00 UTC` tetikleniyor ve `/project/teqlif/logs/offsite_sync.log`'a `SKIP — RCLONE_REMOTE/RCLONE_BUCKET tanımlı değil` yazıp **`exit 0`** dönüyor!).
2. **`schedule.yaml` + `watchdog.py` (Katman A):** `offsite_sync.sh:84` `HSET teqlif:agent:job_ok offsite_sync` atar; ancak `schedule.yaml`'da `offsite_sync` kaydı olmadığı için `JobWatchdog` bu anahtarı hiç izlemez (ayrıca `SKIP` durumunda `job_ok` basılmaması doğrudur ama alarm üretmediği için 23 gündür sessiz kalmıştır!).
3. **`health.py` (`_BACKUP_MAX_MIN` + `_backup_ages`, Katman B):** `health.py:44-54, 402-418` içinde `offsite_sync` hiç yoktur.
4. **`teqlif-offsite-sync.service` (`systemd OnFailure`, Katman C):** Diğer tüm `node2/systemd/teqlif-*-backup.service` birimlerinde `OnFailure=teqlif-backup-failed@%n.service` olmasına rağmen `teqlif-offsite-sync.service` dosyasında **`OnFailure` eksiktir**! Ayrıca `EnvironmentFile=/project/teqlif/config/.env.backup` servis biriminde değil yalnızca script içinde `source` edilir.

#### 2. Çözüm / Refactoring Reçetesi
1. `offsite_sync.sh`: Yapılandırma eksikse `exit 0` yerine **`exit 2` + Telegram/syslog uyarısı** (`OFFSITE_MODE=disabled` açıkça verilmedikçe).
2. `teqlif-offsite-sync.service`:
   - `OnFailure=teqlif-backup-failed@%n.service` ekle.
   - `After=network.target wg-quick@wg0.service teqlif-pg-dump.service teqlif-clickhouse-backup.service teqlif-redis-backup.service teqlif-minio-backup.service teqlif-loki-backup.service teqlif-uptime-kuma-backup.service teqlif-nodemonitor-config-backup.service teqlif-mail-backup.service teqlif-pg-wal-cleanup.service` (veya tek zincirli sıralı çalışma; aşağıdaki Zaman Çizelgesi önerisine bkz.).
3. `offsite_sync.sh` sonunda `/project/teqlif/backups/.last_offsite_sync_ok` (veya `/project/teqlif/backups/offsite/.last_backup_ok`) sentinel dosyası + Redis `HSET teqlif:agent:job_ok offsite_sync`; `schedule.yaml` (`watchdog_m: 1500`) + `health.py` (`_BACKUP_MAX_MIN["offsite_sync"] = 25 * 60`) içine ekle.
4. Timer'ı `systemctl enable --now` ile reboot-kalıcı yap.

---

### OFFSITE-05 · 🟠 P1 (Yüksek) · `node101` Ağ Topolojisi, WireGuard (`10.10.0.101`) ve Güvenlik İzolasyonu

#### 1. Sorunun Tanımı ve Kanıtlar
- `deploy/scale/V2.1/scripts/wg_mesh_apply.sh` yalnız `node1..node6`'yı bilir; `secrets.env.template` içinde `node101` WG IP/pubkey alanı yoktur; `scripts/teqlif-restart.sh` bilinmeyen hostname'de hata verir.
- Canlı `node101`: `ufw`, `wg`, `node_exporter` kurulu değildir; yalnızca 12 temel servis çalışır. `node2` `wg show` canlıda `10.10.0.1, 5, 6, 99` eşlerini tutmaktadır.

#### 2. Çözüm / Mimari Reçete (Blast-Radius Kontrolü)
- **`node101` Tüm Mesh'e Açılmamalıdır!** En sık yapılan hata yeni yedek sunucusunu tam WG mesh içine eklemektir. Oysa **`node1` / `node3` / `node4` / `node5` / `node6`'nın `node101`'e hiçbir erişim ihtiyacı yoktur**.
- Doğru topoloji:
  - `node101` WG IP: **`10.10.0.101/24`** (UDP `51820`).
  - `node101`'in `/etc/wireguard/wg0.conf` dosyasında **yalnızca 2 peer** olmalı: `node2` (`10.10.0.2/32`) ve `nodeMonitor` (`10.10.0.99/32` — disk/RAM/systemd metrikleri ve Prometheus `node_exporter:9100` / `teqlif-agent` için). *(Acil/DR durumunda geçici peer veya SSH bastion/mac kullanılabilir)*.
  - `node101` UFW: Default `deny incoming`, `allow out`; Allow `22/tcp` (yalnız SSH Ed25519 key, `PasswordAuthentication no`), Allow `51820/udp` (`node2`, `nodeMonitor` ve yönetim için WG); Restic `rest-server` (`8000/tcp`) / SSH backups **sadece `in on wg0 from 10.10.0.2`**; `node_exporter` (`9100/tcp`) **sadece `in on wg0 from 10.10.0.99`**.
- `deploy/scale/V2.1/node101/` altında tüm WireGuard, UFW, `bootstrap_node101.sh` ve Prometheus scrape hedefleri versiyonlanmalı; `secrets.env.template` içine `WG_PUBKEY_NODE101` ve `NODE101_IP=195.206.234.142` eklenmelidir.

---

### OFFSITE-06 · 🟠 P1 (Yüksek) · `node101` Donanım Kısıtları (`2.9 GiB RAM`, `6.1 GB` `/`, `fdatasync` Tail Gecikmesi)

#### 1. Sorunun Tanımı ve Kanıtlar
- `node101/specs.md` & canlı `df -hT` / `free -h` / `fio`:
  - RAM: `2.9 GiB` (`2.6 GiB` boş), Swap `1.0 GiB`.
  - Root (`/`): `/dev/vda3` `9.7G` (`3.3G` dolu, **yalnızca `6.1G` boş**).
  - Data (`/mnt/data`): `/dev/vdb` `984G` (`934G` boş, **sahiplik şu an `tucibeyin:tucibeyin`**; `fio` ölçümü: `1M` R/W `137/145 MiB/s`, `4k` R/W `27.4k/27.4k IOPS`, `64k fdatasync` `83 IOPS / 5.45 MB/s` ve `p99=229.6 ms`, `max=871.9 ms`).
  - CPU: `2 vCPU` (`E5-2699 v4`, Geekbench 6 `676 / 1165`, `AES-NI ✔`).
- Restic repo boyutu büyüdüğünde (`100 GB+`) `restic prune` veya `restic check` sunucu tarafında varsayılan ayarlarla 2+ GB RAM tüketebilir → `node101` (2.9 GiB) OOM ile çökebilir. Yedek dosyaları yanlışlıkla `/tmp` veya `/var/cache` yolunu kullanırsa `6.1 GB` root disk anında dolar. Ayrıca yüksek `fdatasync` tail latency (`p99=230ms`) nedeniyle küçük senkron dosyalar yerine büyük pack dosyaları (`--pack-size 32`) şarttır.

#### 2. Çözüm / Refactoring Reçetesi
1. `/mnt/data` `fio` benchmark'ı tamamlandı ve `deploy/scale/V2.1/node101/specs.md` altına işlendi; **`restic backup --pack-size 32`** (veya `auto`) kullanarak binlerce küçük Loki/WAL dosyasını büyük paketler halinde gönder (küçük-dosya `83/s` `fdatasync` tuzağından kaçın).
2. Tüm runtime yollarını `/mnt/data` altına sabitle:
   - Repo: `/mnt/data/restic-repo`
   - Temp: `/mnt/data/tmp` (`TMPDIR=/mnt/data/tmp`)
   - Cache: `/mnt/data/cache` (`RESTIC_CACHE_DIR=/mnt/data/cache/restic` veya `--no-cache`)
   - Logs: `/mnt/data/logs`
3. Restic RAM koruması (kullanılırsa): `node101` üzerindeki lokal `prune`/`check` systemd servisinde `Environment="GOGC=20" "GOMEMLIMIT=1536MiB"`, `MemoryMax=2G`, `IOSchedulingClass=idle`, `Nice=19` tanımla. (`rest-server --append-only` normal alım modunda neredeyse `< 50 MB` RAM harcar.)

---

### OFFSITE-07 · 🟠 P1 (Yüksek) · PostgreSQL PITR (`pg_basebackup` + `pg_wal`) Eksikliği ve `pg_dump` `.dump.gz` Yetimleri

#### 1. Sorunun Tanımı ve Kanıtlar
- `offsite_sync.sh:72-79` yalnızca şu 8 dizini senkronize eder: `pg_dump`, `minio`, `clickhouse`, `redis`, `loki`, `stalwart`, `uptime_kuma`, `nodemonitor_config`.
- **`pg_basebackup` (`14 MB`) ve `pg_wal` (`561 MB` / 34 segment) listede YOKTUR!** `node1` ve `node2` birlikte kaybedilirse cüzdan/IAP/müzayede işlemlerinde en az son `03:00` dump'ından bu yana **24 saate kadar veri kaybı** doğar.
- Ayrıca canlı `node2` `/project/teqlif/backups/pg_dump/` içinde 2–8 Ekim tarihli **7 adet `.dump.gz`** dosyası durmaktadır; `pg_dump.sh:26` yalnızca `find "${BACKUP_DIR}" -name "teqlif_*.dump" -mtime +7 -delete` yaptığı için bunlar sonsuza dek kalmıştır.

#### 2. Çözüm / Refactoring Reçetesi
1. Eski `.dump.gz` yetimlerini temizle (`pg_dump.sh` filtresini gerekirse `teqlif_*.dump*` yap).
2. **`pg_basebackup` + `pg_wal`'ı offsite zincirine dahil et:**
   - **Kritik İnce Ayrıntı:** `pg_receivewal` canlı çalışırken en son aktif WAL segmentini **`*.partial`** uzantısıyla yazar. Offsite motoru (`restic` / `rclone` / `rsync`) **mutlaka `--exclude '*.partial'`** uygulamalıdır; tamamlanmış (`00000001...`) WAL segmentleri offsite'a taşınmalıdır.
   - **RPO İyileştirmesi:** Günlük tek `07:00 UTC` sync ile offsite PITR RPO'su yine ~24 saat kalır *(Adım 3'te `node1` `archive_timeout=3600` + saatlik `*:45:00 UTC` `--tag pg_wal` push onaylandı)*. PG finansal/wallet RPO'sunu **≤ 1 saate** düşüren saatlik WAL push yalnız yeni kapanan ~16 MB (sıkıştırılmış KB düzeyinde) segmenti taşıdığı için bant genişliğini neredeyse hiç kullanmaz.

---

### OFFSITE-08 · 🟠 P1 (Yüksek) · ClickHouse Yedek Dizin Uyuşmazlığı & Canlıda Boş Fallback Arşivler

#### 1. Sorunun Tanımı ve Kanıtlar
- `clickhouse_backup.sh:13-14`: Method 1 (`clickhouse-backup`) ve Method 2 (`BACKUP DATABASE ... TO Disk('backups', ...)`) çıktılarını `/var/lib/clickhouse/backups`'a yazar; Method 3 (fallback) ise `/project/teqlif/backups/clickhouse`'a `.tar.gz` yazar.
- `offsite_sync.sh:74`, `health.py:407` ve `runbook.sh` yalnızca `/project/teqlif/backups/clickhouse` dizinine bakar.
- **Canlı `node2` Durumu:** `/var/lib/clickhouse/backups` tamamen boştur (`total 8`). Her gün Method 3 fallback çalışmaktadır, üstelik canlı ClickHouse'ta `teqlif_prod_analytics` içindeki 7 tablonun tamamı şu an **0 satır** olduğu için her gün `~285 byte`'lık boş `.tar.gz` arşivlenmektedir (`teqlif_staging_analytics`'te `14 + 11 = 25` satır vardır).

#### 2. Çözüm / Refactoring Reçetesi
1. ClickHouse üzerinde Method 2 (`BACKUP DATABASE` -> `/etc/clickhouse-server/config.d/backups.xml`) etkinleştirilecekse hedef dizin `/project/teqlif/backups/clickhouse/` içine yönlendirilmeli veya symlink/copy ile tek kanonik dizine toplanmalıdır.
2. `teqlif_prod_analytics` neden 0 satır (prod henüz flush alıyor mu yoksa worker `CLICKHOUSE_DB`/buffer hedefi mi farklı) ayrı bir adımda doğrulanmalıdır; `clickhouse_backup.sh` çıktısı `/project/teqlif/logs/clickhouse_backup.log` dosyasına da yönlendirilmelidir.

---

### OFFSITE-09 · 🟠 P1 (Yüksek) · `nodemonitor_config_backup.sh` İçinde `979 MB` TSDB/WAL Sızıntısı

#### 1. Sorunun Tanımı ve Kanıtlar
`node2/resources/scripts/nodemonitor_config_backup.sh:39-41`:
```bash
rsync_from_nodemonitor "/opt/monitor/teqlif/" "${BACKUP_DIR}/monitor-config" \
    --exclude 'prometheus/data/' \
    --exclude 'loki/data/'
```
Canlı `node2` `/project/teqlif/backups/nodemonitor_config/` denetiminde boyut **`979 MB`** çıkmıştır (`monitor-config/prometheus/data` **823 MB** — 18 Ekim'den kalma eski TSDB blokları; `monitor-config/loki/` **156 MB** — `data/`, `tsdb-shipper-active/`, `tsdb-shipper-cache/`, ve her gün tazelenen `wal/`!).
- **Kök Neden 1:** `rsync --delete` verilmiş ama **`--delete-excluded` verilmemiş**! Dolayısıyla `--exclude` eklenmeden önceki 2–18 Ekim dosyaları `node2`'de sonsuza dek kalmış ve her sync'te kontrol edilip offsite'a gidecek duruma gelmiştir.
- **Kök Neden 2:** Loki dizininde yalnız `loki/data/` hariç tutulmuş; `loki/wal/`, `loki/tsdb-shipper-active/`, `loki/tsdb-shipper-cache/` hariç tutulmadığı için aktif WAL her gün taşınmaya devam etmektedir.

#### 2. Çözüm / Refactoring Reçetesi
1. `nodemonitor_config_backup.sh:27-41`: `rsync -az --delete --delete-excluded` kullan ve exclude listesine `'loki/wal/'`, `'loki/tsdb-shipper-active/'`, `'loki/tsdb-shipper-cache/'` ekle.
2. Canlı `node2`'deki kalıntı `prometheus/data` (`823 MB`) ve `loki/data`/`wal` temizlendiğinde `nodemonitor_config` **979 MB → < 1 MB**'a düşer (toplam temiz offsite hacmi neredeyse yarıya iner!).

---

### OFFSITE-10 · 🟡 P2 (Orta) · Gündüz `07:00 UTC` Sync Çakışması, I/O Sınıfı ve `.tmp` Sızıntısı

#### 1. Sorunun Tanımı
- `07:00 UTC` = **`10:00 TR`** (Türkiye'de sabah iş/trafik açılışı) ile üstelik ayın 1. Pazartesi günü **`node2` `mdcheck_continue` (`06:46 UTC`)** RAID-1 HDD scrub üzerine biner.
- `teqlif-offsite-sync.service` içinde `IOSchedulingClass=idle` ve `Nice=19` yoktur (`node2` 2×HDD RAID-1 kullanır; ClickHouse sorguları ve `pg_receivewal` ile I/O yarışabilir).
- Mevcut `rclone sync` çağrısında `--exclude '*.tmp' --exclude '*.partial'` yoktur.

#### 2. Çözüm / Refactoring Reçetesi
- Yerel backup zincirini `06:00–06:40` yerine `06:15`'te bitirecek şekilde sıkılaştırıp ana günlük offsite çalışmasını **`06:30 UTC` (`09:30 TR`)** *(veya tüm bakım bloku bittiğinde ardışık tetiklemeyle)* tamamlamak; servis dosyasına `IOSchedulingClass=idle`, `Nice=19` eklemek ve `rclone`/`restic` kurallarında `*.tmp`, `*.partial`, `.last_*_ok` filtrelemek.

---

### OFFSITE-11 & OFFSITE-12 & OFFSITE-13 · Kurtarma Tatbikatı, Bootstrap Otomasyonu ve WORM Arşiv

1. **OFFSITE-11 (`runbook.sh` & Tatbikat):** `node2/resources/scripts/runbook.sh` yalnızca `node2` → `node1` yerel kurtarma içerir. Hem `node2` disk kaybında `node101` → yeni `node2`, hem de tam çift-kayıpta `node101` → yeni `node1` için şifreli restore runbook'u yazılmalı ve haftalık/aylık `cron`/`timer` ile `node101` üzerindeki en son `pg_dump` / `restic snapshot` bütünlük (`restic check --read-data-subset=5%` + test DB'ye `pg_restore --list`) otomatik doğrulanmalıdır.
2. **OFFSITE-12 (Bootstrap & Araçlar):** Canlı `node2`'de `rclone v1.75.1` manuel kurulmuştur ama `deploy/scale/V2.1/scripts/_common.sh` ve `bootstrap_node2.sh` bunu kurmaz. Benzer şekilde `node101` için `deploy/scale/V2.1/node101/` altında tekrarlanabilir **`bootstrap_node101.sh`** (`wireguard-tools`, `ufw`, `restic`/`rest-server` veya `borgbackup`, `rsync`, `prometheus-node-exporter`, `/mnt/data` dizin izinleri ve systemd birimleri) yazılmalıdır.
3. **OFFSITE-13 (`financial_archives` WORM):** `documents/wallet/V1.0` V11-10 kapsamında 1 yıldan eski wallet ledger/invoice hareketlerinin yılda/ayda bir soğuk JSON/Parquet paketleri olarak `node101`'deki `--append-only` repoya gönderilmesi planlanmalıdır.

---

### Sistem Geneli Bakım & Yedekleme Anomalileri Detayı (`MAINT-01` .. `MAINT-08`)

1. **`MAINT-01` · `cleaner.py` vs `schedule.yaml` Çakışması & `message_threads` Tuzağı:**
   - `agent.py` lider olan `nodeMonitor`'da `ScheduledCleaner` (`cleaner.py`) ve `TTLJanitor` (`janitor.py`) yükler. `janitor.py` yalnız *sayım* loglar; **`cleaner.py` ise `PG_DSN` env değişkeni varsa `DELETE FROM {table} WHERE {where}` çalıştırır (`cleaner.py:86-112`)**.
   - Canlı `nodeMonitor` `systemctl show teqlif-agent` şu an `Environment=` boş göstermiştir (`agent.log` içinde cleaner kaydı yok → `PG_DSN` tanımlı olmadığı için erken `return` ediyor görünmektedir). **Ancak `setup_node.sh` admin'e `/etc/teqlif-agent/env` içine `PG_DSN=` girmesini söyler!** `PG_DSN` girildiği gün:
     - `cleaner.py:59-61` `message_threads` için `created_at < NOW() - INTERVAL '180 days' AND has_archive = false` sorgusunu **mesaj olup olmadığına bakmadan (`direct_messages` kontrolsüz!)** çalıştırır; oysa `dm_archive_tasks.py:22` DM'leri **365 günde** arşivler → **180–365 günlük aktif konuşma başlıkları erken silinebilir!**
     - `cleaner.py:43-45` `live_stream_viewers` için `3650 days` (10 yıl!) tutar; `schedule.yaml:221` aynı işi Perşembe `05:00`'de farklı politikayla temizler.
     - `cleaner.py` `LIMIT`'siz `DELETE` attığı için `analytics_events`, `user_interactions`, `stream_recordings` tablolarında uzun WAL sıçraması ve kilit üretir; oysa `worker.py` `5.000`'lik batch delete kullanır.
     - `cleaner.py:67` saat `03:00`'da çalışıp `pg_dump` (`03:00`) ile çakışır.
     - **Çözüm:** `cleaner.py` içindeki PG silme tablosu ARQ (`worker.py` + `schedule.yaml`) lehine emekliye ayrılmalı veya tehlikeli `message_threads` / batchsiz `DELETE` satırları tamamen kaldırılmalıdır.
2. **`MAINT-02` · Video Transfer (`05:00–07:00 UTC`) vs `minio_backup` (`05:30 UTC`) Çakışması:**
   - `cluster.yaml:36-37`: `transfer_window_start_utc: 4`, `transfer_window_end_utc: 7`.
   - `encoder.py:357`: `effective_start = start_utc if free_gb < warn_gb else start_utc + 1` → Normal günde transfer **`05:00–07:00 UTC`** arasındadır.
   - `teqlif-minio-backup.timer` her gün **`05:30 UTC`**'de `node1` MinIO'dan `node2`'ye `mc mirror` yapar ve `node2_confirmed_at` damgalar. Transfer `05:30–07:00` arasında devam ederken yeni gelen kayıtlar bir sonraki güne kalır ve `notify_new_recordings_task` (`05:00 & 06:00 UTC`) transfer penceresi bitmeden çalışır!
   - **Çözüm:** Ya transfer `03:30–05:15 UTC` (düşük disk `03:00`) bandına çekilip `minio_backup` **`05:30`**'da temiz veri toplamalıdır; ya da `minio_backup` **`07:05 UTC`**, `offsite` ise hemen arkasına konumlanmalıdır *(aşağıdaki Zaman Çizelgesi önerisinde `03:45–05:15` → `05:30` daha uyumludur)*.
3. **`MAINT-03` (🔴 P0'a Yükseltildi) · Canlı `node2` Zehirlenmiş Redis Failover Bayrağı + Çift Timer:**
   - Resmi [`node2/resources/scripts/redis_failover.sh:15,20-22`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/node2/resources/scripts/redis_failover.sh#L15-L22), `STATE_DIR="/var/lib/teqlif-redis-failover"` içindeki `promoted` bayrağı varsa `exit 0` ile erken çıkar. **Canlı `node2`'de `/var/lib/teqlif-redis-failover/promoted` (`0 B`, `tucibeyin:tucibeyin`, `Oct 18 15:06`) mevcuttur!** Bu nedenle resmi `teqlif-redis-failover.service` 18 Ekim'den beri **sıfır sağlık kontrolü** yapmaktadır.
   - Paralel çalışan 1 Ekim tarihli yetkisiz `redis-failover.timer` → `/usr/local/bin/redis-failover-check.sh` ise `root` olarak her 10 sn çalışmakta (`/var/lib/redis-failover/fail_count` `Nov 11 05:35`), içinde **düz metin (plaintext) Redis şifresi** taşımakta ve kesintide VIP `10.10.0.1/32` (`lo`), `iptables DNAT`, WireGuard peer veya Telegram/`job_ok` ayarlamadan yalnızca `REPLICAOF NO ONE` atmaktadır (canlıda `lo` üzerinde `10.10.0.1` yok, Redis `role:slave`, `master_link_status:up`).
   - **Çözüm:** `redis-failover.timer`/`service` ve `/usr/local/bin/redis-failover-check.sh` kaldırılmalı, canlı `node1` sağlığı doğrulandıktan sonra `/var/lib/teqlif-redis-failover/promoted` temizlenmeli ve resmi `teqlif-redis-failover.timer` tek otorite yapılmalıdır.
4. **`MAINT-04` & `MAINT-05` & `MAINT-06` & `MAINT-07` & `MAINT-08`:**
   - `schedule.yaml:304` `backup:` YAML anahtarı eklenecek, `cleanup_old_stream_chat_messages_task` tekilleştirilecek (`worker.py` vs `schedule.yaml`), `cleanup_old_analytics_task` PG/CH yorumları düzeltilecek.
   - `node2`, `node1`..`node6` üzerinde `apt-daily-upgrade` `Override` ile `07:30 UTC` sonrası / veya `node2`'de offsite bittikten sonraya çekilecek; `mdcheck` (`node2`) penceresi gözetilecek.
   - `loki_backup.sh`, `uptime_kuma_backup.sh`, `nodemonitor_config_backup.sh`, `pg_wal_cleanup.sh` için `job_ok` Redis sinyali + `schedule.yaml` kaydı eklenecek; eski `node2/resources/systemd/teqlif-mail-backup.timer` (`03:45`) ve `/project/teqlif/backups/.last_mail_backup_ok` temizlenecek.
   - `nodeMonitor` (`1.9 GiB RAM`, `240 MiB` swap, `MemoryMax` toplamı `~1.4 GB` — `mariadb` ve `grafana` hariç) Prometheus TSDB retention/chunk bellek ayarı gözden geçirilecek ve asla offsite yedek köprüsü yapılmayacak.
   - `teqlif-loki-backup`, `mail-backup`, `nodemonitor-config-backup`, `uptime-kuma-backup`, `offsite-sync` servislerine `Nice=19` + `IOSchedulingClass=idle` eklenecek.

### Sistem Geneli Uçtan Uca Denetim Detayları (Adım 5 — `AUDIT-01` .. `AUDIT-08`)

> **Canlı Saat & Bütünlük Doğrulaması (`11 Kasım 2026 · 05:34–05:38 UTC = 08:34–08:38 TR`):**
> `node2` ve `node1..6` UTC saat dilimindedir; bu nedenle `06:00–07:00 UTC` (`09:00–10:00 TR`) timer'larının (`loki`, `uptime_kuma`, `nodemonitor_config`, `mail`, `pg_wal_cleanup`, `offsite_sync`) son çalışmasının `10 Kasım` görünmesi kaçırılmış değil henüz saatlerinin gelmemiş olmasındandır. Canlı bütünlük kontrollerinde **`pg_dump` (`pg_restore -l`: 647 öğe ✔)**, `pg_basebackup` (Pazar ✔), `pg_receivewal` (stream ✔), **`redis_backup` (`gzip -t` ✔)**, **`mail_backup` (`tar -tzf`: 643 dosya ✔)**, **`uptime_kuma` (`gzip -t`: 67.015 satır ✔; yalnız 13 Eki `20B` yetimi bozuk)**, `loki_backup`, `nodemonitor_config_backup` ve `minio_backup` dosya bütünlüğü doğrulanmıştır. Aşağıdaki `AUDIT-01..08` maddeleri ise **sessizce bozuk, eksik veya sınırsız biriken** kritik noktalardır.

1. **`AUDIT-01` (🔴 P0) · `node2` Yerel Felaket Kurtarma (DR) & PITR Tamamen Kırık:**
   - **Eksik Uzantı & Cluster:** Canlı `node2`'de `pg_lsclusters` **boştur**, `/etc/postgresql/17/main/postgresql.conf` ve `/var/lib/postgresql/17` verisi yoktur. `postgresql-17 (17.11)` kuruludur ancak **`postgresql-17-pgvector` paketi kurulu değildir** (`dpkg -l '*vector*'` boş) — oysa `pg_dump` `pg_restore -l` çıktısında `EXTENSION - vector` (`pg_trgm`, `unaccent`, `vector`) zorunludur.
   - **Kırık PITR Kurtarma Akışı ([`runbook.sh:94,134-149,167-168,206-208`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/node2/resources/scripts/runbook.sh#L94-L208)):** `pg_basebackup.sh --wal-method=stream` tarafından üretilen `pg_wal.tar.gz` yok sayılır; ayrıca `recovery_target = 'immediate'` yazıldığı için PostgreSQL yalnızca yedek bitiş checkpoint'inde durur, `/project/teqlif/backups/pg_wal` içindeki son WAL segmentlerini hiç replay etmez (`1 dk` yerel PITR RPO boşa düşer). `pg_dumpall --globals-only` alınmadığı için rol/şifre geri yüklemesi eksiktir.
   - **Eksik DR Dosyaları & Non-Atomik Basebackup:** `node2`'de `/project/teqlif/config/.env.dr` ve `/etc/ssl/teqlif/cf-origin.{crt,key}` yoktur. [`pg_basebackup.sh:27-35`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/node2/resources/scripts/pg_basebackup.sh#L27-L35) doğrudan `${BACKUP_DIR}/${TIMESTAMP}` içine yazar (`.tmp` + `mv` yok); yarıda kalırsa `runbook.sh:94` en son bozuk klasörü seçer.
2. **`AUDIT-02` (🟠 P1) · `teqlif-agent` & `worker.py` Telemetri Körlüğü:**
   - **Donmuş SQLite Kayıtları ([`watchdog.py:49-64,101-106`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/teqlif-agent/modules/watchdog.py#L49-L106)):** `_CONTINUOUS_REGISTRY`, `train_item2vec_task` ve `train_swipe_live_als_task` anahtarlarını içermez. Canlı `node1` Redis `teqlif:agent:job_ok` içinde bu ikisi **`2026-11-08`** tarihli güncelken `watchdog.py` registry'de olmayan key'i atladığı için **`nodeMonitor` SQLite `job_health` tablosunda `2026-11-01`'de donmuş kalmıştır** (`10.5g` eşiğinde tutarsız uyarı riski).
   - **Hiç Çalışmamış / Boş Dönmüş İş Körlüğü ([`db.py:130-137`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/teqlif-agent/db.py#L130-L137) + [`worker.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/worker.py)):** `get_stale_jobs()` `WHERE last_ok_at IS NOT NULL` sorgusu yüzünden hiç `job_ok` atmamış işi raporlamaz. Statik `cron_jobs` içindeki **10 görev** (`flush_clickhouse_buffers_task`, `expire_recordings_task`, `archive_recordings_task`, `notify_new_recordings_task`, `direct_sale_overdue_check_task`, `refresh_i18n_cache_task`, `backfill_listing_quality_scores_task`, `invalidate_swipe_live_configs_task`, `sync_swipelive_interests_task`, `stream_concat_task`) hiçbir zaman `_agent_ok` çağırmaz *(not: `cleanup_hype_highlights_task` çağırır)*. Ayrıca `cleanup_ghost_calls_task`, `cleanup_stale_streams_task`, `check_search_alerts_task`, `flush_interactions_to_db` (boşta erken return) ve `train_listing_quality_model_task` (`worker.py:209`, `n < 50`) erken döndükleri için canlı Redis & SQLite'ta tamamen eksiktir.
   - **`recorder` False-Positive Riski & Eksik Raporlama:** [`recorder.py`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/teqlif-agent/modules/recorder.py) yalnız yayın tamamlanınca `mark_ok("recorder.{node_id}", 10080)` yazar (`node5` `2026-11-06T14:16:30+00:00`); yayın olmayan edge 10.5 günde yanlış stale alarmı üretir. [`reporter.py:47-53`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/teqlif-agent/modules/reporter.py#L47-L53) 11 yedeğin yalnız 5'ini raporlar.
3. **`AUDIT-03` (🟠 P1) · Kritik Servis ve Konfigürasyon Yedek Eksikleri:**
   - **Grafana Tamamen Yedeksiz:** `/opt/monitor/shared/grafana/` (**`521 MB`** — `grafana.db` `3.7 MB`, dashboard ve plugin'ler dahil) ve `/project/shared/config/{grafana.ini,uptime-kuma.env}` hiçbir scriptte yoktur ([`nodemonitor_config_backup.sh`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/node2/resources/scripts/nodemonitor_config_backup.sh) yalnız `/opt/monitor/teqlif/`'i çeker).
   - **Mail & Loki & Cluster Sırları:** [`mail_backup.sh:24-27`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/node2/resources/scripts/mail_backup.sh#L24-L27) `/project/mail/config/config.toml` (`6.1 KB`), `.env.mail` (`510 B`) ve `config/acme/` dizinini almaz (`2>/dev/null` kullanır ve `tar -tzf` doğrulamaz). [`loki_backup.sh:24-28`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/node2/resources/scripts/loki_backup.sh#L24-L28) TSDB/v13 şemasına rağmen `compactor/` ve index'i almaz. `node1..6` TLS sertifikaları (`/etc/letsencrypt/live/uploads.teqlif.com`, `/etc/ssl/teqlif/cf-origin.*`), `.env*`, `/etc/teqlif-agent/env`, `/etc/wireguard/` sistemik olarak backup dışındadır (FAISS `/var/www/teqlif.com/faiss` ve ML `.pkl` modelleri ise yeniden üretilebilir olmakla birlikte soğuk başlatma sırası DR'a eklenmelidir).
   - **ClickHouse Grants & DDL:** Canlı `node2` `SHOW GRANTS FOR teqlif` çıktısında **`BACKUP` yetkisi yoktur**; Method 3 `FORMAT Native` fallback'i `SHOW CREATE` DDL ve Materialized View tanımlarını içermez (`teqlif_prod_analytics` 0 satır, `teqlif_staging_analytics` 25 satır; `node5` staging `~26.5k` satır / `~550 KiB`).
4. **`AUDIT-04` (🟠 P1) · MinIO 15g Retention Eksikliği + Confirmation Race + Kuma Hijyeni:**
   - [`minio_backup.sh`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/node2/resources/scripts/minio_backup.sh) içinde `--remove` yoktur ve `cluster.yaml:47` / `schedule.yaml:346`'da yazan **`retention_days: 15` kuralını `node2` diskinde uygulayan hiçbir temizlik komutu yoktur**. `confirm_recordings()` (`L88-96`) ise `mc mirror` bitişi ile `UPDATE` arasındaki pencerede yüklenen yeni kayıtları da indirmiş gibi damgalayabilir (`WHERE created_at <= :sync_started_at` şartı eksiktir).
   - [`uptime_kuma_backup.sh`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/node2/resources/scripts/uptime_kuma_backup.sh) atomik `.tmp` + `gzip -t` + `--single-transaction` kullanmadığından `13 Ekim` tarihli `20 byte` boş dosya bırakmıştır; ayrıca SSH argümanında inline `MYSQL_PWD` geçirir.
5. **`AUDIT-05` (🟠 P1) · ClickHouse Sistem Log Şişmesi & `node5` `%56` Disk Baskısı:**
   - `node2` ve `node5` ClickHouse iç tablolarında (`trace_log`, `text_log`, `asynchronous_metric_log`, `metric_log`, `part_log`) **TTL olmadığı** için canlıda **`node2`'de `2.38 GiB`** (`trace_log` 993.66 MiB / 74.8M satır, `asynchronous_metric_log` 691.17 MiB / 1.31B satır, `metric_log` 416.22 MiB, `part_log` 311.00 MiB), **`node5`'te `3.9 GiB`** (`trace_log` 1.09 GiB, `text_log` 1015.41 MiB, `asynchronous_metric_log` 602.46 MiB, `metric_log` 440.95 MiB, `part_log` 356.87 MiB) **+ `1.5 GiB` `/var/log/clickhouse-server` = `5.4 GiB`** yer tüketmektedir!
   - `node5` (`50G` diskin **`27G` / `%56` dolu**) üzerinde ayrıca **`3.2 GiB /root/.cache`** ve **`194 MB /var/recordings` çöpü** (`429..451_*.log`, 0-byte dosyalar ve 12 Ekim–6 Kasım arası `.mkv`/`.mp4` artıkları) vardır — [`encoder.py:164,271`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/teqlif-agent/modules/encoder.py#L164-L271) yalnız başarıda `.mkv`/`.mp4` siler, `.log` veya başarısız/0-byte dosyaları asla temizlemez.
6. **`AUDIT-06` (🟡 P2) · Kırık `logrotate`, `agent.log` (`~565 MB`) ve Sınırsız `journald`:**
   - [`_common.sh:149-159`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/scripts/_common.sh#L149-L159) `/etc/logrotate.d/teqlif` içine `/project/teqlif/logs/**/*.log` yazar; `logrotate -d` glibc `glob()` `**` özyinelemesini desteklemediği için eşleşmez (`node1/logs/redis-core.log` `16 MB`, `node2/logs/minio_backup.log` `43 KB`), `nodeMonitor`'da dosya hiç yoktur.
   - `teqlif-agent.service` `StandardOutput=append:/var/log/teqlif-agent/agent.log` için logrotate yoktur: **`nodeMonitor 103 MB`**, `node2 98.5 MB`, `node1 90.3 MB`, `node5 78 MB`, `node6 71 MB`, `node3 66 MB`, `node4 58 MB` (**~565 MB**).
   - `journald` tüm node'larda default (`[Journal]` boş) kotasızdır: `nodeMonitor 1.2 GB`, `node5 1.6 GB` (`du`, `journalctl` `614.3 MB`), `node4 622.5 MB`, `node3 617.9 MB`, `node6 320.1 MB`.
7. **`AUDIT-07` (🟡 P2) · SQLite `cleanup_log` Çoğaltma + Bootstrap Eksikleri:**
   - [`db.py:39-47,276-284`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/teqlif-agent/db.py#L39-L284) `cleanup_log` tablosunda `UNIQUE` anahtar tanımlamaz; [`gossip.py:60`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/teqlif-agent/gossip.py#L60) `_last_sync`'i yalnız RAM'de tuttuğu için agent restart'ında `1970-01-01` çekilip tüm `cleanup_log` satırları yinelenir (`VACUUM`/budama da yok). [`janitor.py:149`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/teqlif-agent/modules/janitor.py#L149) var olmayan `cleanup_actions.sh`'ye atıf yapar. [`bootstrap_node2.sh:210-214`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/scripts/bootstrap_node2.sh#L210-L214) 7 backup/cleanup timer'ını `enable` listesinde atlamıştır.
8. **`AUDIT-08` (🟡 P2) · `worker.py` Batch'siz Temizlik & Docstring Sapması:**
   - [`cleanup_old_media_messages_task`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/worker.py#L856-L898) tüm kayıtları `.scalars().all()` ile belleğe yükler ve docstring `"3/7 gün"` derken kod **`timedelta(days=60)`** kullanır. `cleanup_old_stream_chat_messages_task` + diğer 8 temizlik görevi (`cleanup_old_stream_likes_task`, `viewers`, `offers`, `exchange_rates`, `streams`, `calls`, `empty_message_threads`, `inactive_search_alerts`, `hidden_messages`) tek seferde batch'siz `DELETE FROM` çalıştırır.

### İş Mantığı, Finans, KVKK/Uyum & Ölçek Detayları (Adım 6 — `BIZ-01` .. `BIZ-05`)

1. **`BIZ-01` (🔴 P0) · Ürün & Gelir Vaadi Kırılmaları (DM Arşivi + 14 Günlük PRO Video Upsell):**
   - **DM Arşivi (`messages.py:292-299` vs `dm_archive_tasks.py:80,94`):** Pazar `03:00 UTC` çalışan [`archive_old_dm_task`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/tasks/dm_archive_tasks.py#L28-L136), 365 günlük okunmuş metin DM'lerini PostgreSQL'den silip private **`teqlif-dm`** bucket'ına yazar (`upload_bytes_dm`). Ancak kullanıcı sohbet arşivini çekmek istediğinde [`get_archived_messages`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/messages.py#L276-L321) **public `teqlif`** bucket okuyan `storage.list_object_keys()` ve `storage.get_object_bytes()` fonksiyonlarını çağırır ([`storage_service.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/services/storage_service.py#L137-L227) — `list_object_keys_dm` metodu hiç yoktur). 1 yıl+ tüm mesajlar kullanıcıya boş döner; üstelik Pazar `03:00` çalışması `pg_dump` ile aynı dakikaya denk geldiğinden silinen mesajlar `05:30 UTC` `minio_backup` çalışana kadar **2.5 saat yalnız `node1` MinIO'da tek kopya** kalır.
   - **PRO 14g Video Upsell Kırılması ([`stream_recording_tasks.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/tasks/stream_recording_tasks.py#L40-L97) vs [`streams.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/streams.py#L300-L365)):** Standart yayıncılara `"recording_upsell"` bildirimi ile **`14 gün` hukuki arşiv** tanımlanır ancak [`setup_minio_ilm.sh`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/scripts/setup_minio_ilm.sh#L18) ve [`minio_backup.sh`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/node2/resources/scripts/minio_backup.sh#L39) `node1` MinIO nesnelerini **2. günde** imha eder (`archive_recordings_task` da `node2_confirmed_at + 2 gün` sonra `status='archived'` yapar). Standart host 3.–14. günde PRO'ya geçip kaydını açmaya çalışsa dahi `node2`'den geri servis/restore mekanizması olmadığı için dosya bulunamaz (`404 NoSuchKey` / `RECORDING_EXPIRED`). Üstelik T+14 hakediş (`release_pending_earnings_task`) ile `node2` `15g` saklama hedefi arasında chargeback/anlaşmazlık için yalnızca **1 gün** tampon vardır.

2. **`BIZ-02` (🔴 P0) · Finansal Mutabakat Körlüğü + Sınırsız `pg_wal` Çökme Riski:**
   - [`daily_financial_reconciliation_task`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/tasks/wallet_tasks.py#L101-L166) (`00:00 UTC`): Negatif `user_wallet_earnings` veya 30 günlük `withdrawal_requests` ↔ `wallet_ledger` sapması yakalasa bile **yalnız `logger.warning()` yazar ve `_agent_ok` basar** — hiçbir Telegram, Alertmanager veya admin bildirimi üretmez; toplam `SUM(wallet_ledger)` mutabakatını ve 30 gün ötesini de kontrol etmez.
   - **Canlı `node1` PG `max_slot_wal_keep_size = -1` (Sınırsız!) & `0 ms` Timeout'lar:** Canlı `node1` PostgreSQL `node2_receivewal` slotu için WAL sınırı **kapatılmış (`-1`)**. `node2` disk/ağ kesintisinde `node1` NVMe (`426G`) dolana dek WAL biriktirip **prod DB'yi çökertebilir**. Nitekim [`redis_failover.sh`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/node2/resources/scripts/redis_failover.sh#L65-L68) promote anında `node2`'de `node1` WG peer'ını `0.0.0.1/32` yapıp `wg-quick save` atarak sadece Redis'i değil `pg_receivewal`, `pg_dump` ve `minio_backup` bağlantısını da kalıcı keser! Aynı sunucuda `lock_timeout = 0ms`, `statement_timeout = 0ms` ve `idle_in_transaction_session_timeout = 0ms` olduğu için ağır bakım sorguları canlı açık artırma/cüzdan işlemlerini sınırsız bloke edebilir.

3. **`BIZ-03` (🟠 P1) · KVKK/TTK/MASAK Uyum Açıkları & `07:00 TR` Push Fırtınası:**
   - **Hesap Silme ([`delete_account`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/auth.py#L1638-L1719)):** Kullanıcının aktif `pending`/`available` kazancı veya açık çekim talebi olup olmadığını denetlemeden kimliği anonimize eder (`token_version += 1` ile oturumu kapatır). Aynı endpoint **`direct_messages` ve `teqlif-dm` (`dm-archive/`) içindeki özel yazışmaları temizlemez**; pasife çekilen ilan fotoğrafları **60 gün** sonra silinse bile [`minio_backup.sh`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/node2/resources/scripts/minio_backup.sh#L20) `--remove` kullanmadığından silinmiş avatar/ilan/DM medyaları `node2`'de süresiz kalır (KVKK silme hakkı çatışması). Finansal/vergi tarafında (`V11-10` — 5–10 yıl TTK/MASAK & 120–180g chargeback penceresi) mevcut 6 aylık `restic` GFS politikası kısa kalır.
   - **Sabah `07:00–08:10 TR` Push Fırtınası & Eski Airdrop Tablosu:** [`process_churn_and_airdrop`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/tasks/analytics_tasks.py#L171-L345) (`04:00 UTC = 07:00 TR`), [`listing_tasks.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/tasks/listing_tasks.py#L224-L269) (`07:15/07:20 TR`) `pref_key=None` geçtiği için [`push_notification`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/services/notification_service.py#L66-L88) içindeki `quiet_hours_enabled` kontrolünü tamamen atlar (`DEFAULT_NOTIF_PREFS["quiet_hours_enabled"]` zaten `False`). Ayrıca `process_churn_and_airdrop`, ClickHouse hatasını yutup boş dönerken `_agent_ok` basar ve `wallet_ledger` yerine `users.teqlik_balance + teqlik_transactions` günceller.

4. **`BIZ-04` (🟠 P1) · `nodeMonitor` SPOF, İzlenmeyen Kritik Servisler & `09:15 TR` Mail Kesintisi:**
   - **Tek-Nokta Bağımlılığı:** Prometheus, Alertmanager, Loki, Grafana, Uptime Kuma ve `teqlif-agent` Lideri tek `1.9 GiB` VPS'te (`nodeMonitor`, `240 MiB swap`) koşar; **`node1` veya `node2`'den `nodeMonitor`'ı izleyen hiç Dead Man's Switch yoktur**. Canlı Prometheus hedeflerinde **`node2` ClickHouse**, **`node1` MinIO**, **`node2` Redis Replica**, **`pg_receivewal`** ve **`stalwart-mail`** yer almaz; [`alert_rules.yml`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/nodeMonitor/config/teqlif/alert_rules.yml#L1-L92) yalnızca temel HTTP/DB metriklerini kapsar (yedek failure, swap, inaktif PG slot alarmı yoktur).
   - **Sabah Mail Kesintisi & Staging Çöpü:** [`mail_backup.sh`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/node2/resources/scripts/mail_backup.sh#L21-L29) RocksDB snapshot'ı için **`06:15 UTC` (`09:15 TR` mesai açılışı!)** saatinde `stalwart-mail`'i stop/start yapar (`stalwart` arşivi boşta bile `4.9M→5.3M` artıyor; GB ölçeğinde dakikalara uzayıp şifre sıfırlama/OTP e-postalarını düşürür). Öte yandan `node5` staging ClickHouse (`~26.5k` satır) + `teqlif-staging` MinIO yedeksizken `node2` ClickHouse'ta terk edilmiş `teqlif_staging_analytics` (`25` satır) durur.

5. **`BIZ-05` (🟠 P1) · Yüksek Ölçekte (`>50K` Kullanıcı) İlk Kırılacak 4 Nokta:**
   - [`sync_pg_to_clickhouse_task`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/worker.py#L4153-L4264) `user_interactions` `LIMIT 200000` veya `analytics_events` `LIMIT 500000` sınırına takılsa dahi **`ch:last_sync_at` anahtarını `now()` değerine çeker** → aradaki olaylar ClickHouse'a hiç girmeden **48 saat sonra batch'siz `DELETE` ile PG'den kalıcı silinir**.
   - [`listing_tasks.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/tasks/listing_tasks.py#L84-L160) `LIMIT`'siz ilanı tek transaction'da döndürüp MinIO nesnelerini sırayla döngüde siler ve `except` bloklarında hatayı `raise` etmeyip ARQ retry'ını engeller.
   - Batch'siz `DELETE` sorguları ve [`cleanup_old_media_messages_task`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/worker.py#L856-L898) (`.scalars().all()` + commit öncesi MinIO silme sırası) trafik altında PG kilit & WAL patlaması yaratır.
   - `mc mirror --remove` yokluğu + `90g` tam `stalwart` tar + `node2` sınırsız `15g+` video tutumu büyüdüğünde `node2` HDD ve `node101` `934 GiB` kapasitesini hızlı doldurur.

---

## 🏗️ `node101` Nihai Mimari Tasarım Kararları (Adım 3 Kilitli Blueprint)

### 1. Yedekleme Motoru Kararı — ✅ **`restic 0.18.0` + `restic-rest-server 0.13.0 --append-only` Onaylandı**

> Debian 13 (`trixie`) ana paket deposunda hem `node2` hem `node101` için `restic 0.18.0-1+b4` ve `restic-rest-server 0.13.0-2` yerel olarak mevcuttur.

| Kriter | **Seçili Mimari: `restic` + `rest-server --append-only`** | Elenen: `borg` | Elenen: `rclone sync + crypt` |
| :--- | :---: | :---: | :---: |
| **İstemci Şifreleme** | ✅ Yerleşik AES-256 + Poly1305 (`AES-NI ✔`) | ✅ Var | ✅ `crypt` ile |
| **Ransomware WORM Kilidi** | ✅ `--append-only`: `node2` silme/prune HTTP isteği atamaz | ✅ `borg --append-only` | ❌ Destrüktif `sync` (`ext4` snapshot yok) |
| **Deduplication (`1000G` HDD)** | ✅ Global chunk dedup + zstd/sıkıştırma | ✅ Çok iyi | ❌ Her tam versiyon disk şişirir |
| **`node101` `2.9 GiB RAM` Yönetimi** | ✅ `rest-server` `<50 MB`; haftalık `prune` `GOGC=20 GOMEMLIMIT=1536MiB MemoryMax=2G` ile | ✅ Düşük RAM | ✅ Düşük RAM |
| **İzleme (`nodeMonitor`)** | ✅ `rest-server` yerel Prometheus metrikleri (`node_exporter` + HTTP endpoint) | ⚠️ Ek exporter gerek | ❌ Metrik yok |

**Hedef `node101` Dizin & Servis Yerleşimi (`/` `6.1 GiB` SSD Kesinlikle İzole):**
- `/mnt/data/restic-repo` → `rest-server` depo kökü (`teqlif-backup` sistem kullanıcısı sahipliğinde)
- `/mnt/data/tmp` → `TMPDIR=/mnt/data/tmp`
- `/mnt/data/cache/restic` → `RESTIC_CACHE_DIR=/mnt/data/cache/restic` (veya istemci/prune için kontrollü cache)
- `/mnt/data/logs` → `rest-server`, `prune` ve `check` logları
- **`node101` Saat Dilimi:** Şu an `Europe/London` (yazın `UTC+1` BST olur) → Faz-0'da `timedatectl set-timezone UTC` yapılacak ve tüm timer'lar `UTC` yazılacaktır.

**Onaylı Saklama (GFS Retention) Politikası (`node101` Yerel `prune` Timer'ı, Pazar `08:00 UTC`):**
1. **`--tag daily-full`** (`pg_dump`, `pg_basebackup`, `minio`, `clickhouse`, `redis`, `loki`, `stalwart`, `uptime_kuma`, temiz `nodemonitor_config`):
   - `--keep-daily 7 --keep-weekly 4 --keep-monthly 6`
2. **`--tag pg_wal`** (saatlik PITR artımlı WAL segmentleri):
   - `--keep-within 7d` *(maks ~168 küçük snapshot — 7 günden eski tüm veriler günlük `pg_dump` ve haftalık `pg_basebackup` snapshot'larında zaten korunur; `node101` `2.9 GiB RAM` şişmesi tamamen önlenir)*

---

### 2. Karar 2 — `pg_wal` Offsite Push Sıklığı & PostgreSQL `archive_timeout` Gerçeği

Canlı sunucuda yapılan ölçümler (`11 Kasım 2026`) **salt zamanlayıcı ayarlamanın tek başına yetmeyeceğini** kanıtlamıştır:
- **`node1` Canlı PostgreSQL (`17.11`) Ayarları:** `wal_level = replica`, `archive_mode = off`, **`archive_timeout = 0s`**, `checkpoint_timeout = 300s`, `wal_compression = off`.
- **Canlı `node2` `/project/teqlif/backups/pg_wal/` Gerçek Segment Aralıkları:**
  - `00000001000000000000009E` → `Nov 8 02:00` (`pg_basebackup` checkpoint)
  - `00000001000000000000009F` → `Nov 9 08:16`
  - `0000000100000000000000A0` → `Nov 9 09:19`
  - `0000000100000000000000A1` → `Nov 10 12:21` (**~27 saat fark!**)
  - `0000000100000000000000A2.partial` → `Nov 11 03:01` (açık/tamamlanmamış)

> **Mühendislik Tespiti:** `archive_timeout = 0` iken mevcut trafikte bir `16 MB` WAL segmenti ancak **12–27 saatte bir** kapanmaktadır. Dolayısıyla `--exclude '*.partial'` ile saatlik offsite push çalıştırılsa bile **WAL kapanmadığı için saatlerce sıfır yeni byte gider** ve gerçek offsite RPO yine `15–27 saat`te kalır!

**Seçeneklerin Karşılaştırması & Nihai Karar (`Saatlik Push + archive_timeout = 3600`):**

| Seçenek | RPO (Çifte Kayıpta) | Aylık Snapshot Sayısı (`node101` 2.9G RAM) | `node1` / `node2` Yükü | Değerlendirme |
| :--- | :--- | :--- | :--- | :--- |
| `15 dk` + `archive_timeout=900` | `≤ 15 dk` | ~`2.880` snapshot/ay | Günde 96× `16 MB` WAL segmenti (~`1.5 GB`/gün ham) | ❌ `2.9 GiB RAM`'de Restic metadata/prune baskısı ve gereksiz WAL segment enflasyonu |
| **`1 saat` (`*:45:00 UTC`) + `node1` `archive_timeout=3600`** *(Önerilen)* | **`≤ 1 saat`** | **`~168` canlı WAL snapshot** (`7d` tutum) | Saatte maks 1 boş/sparse segment (`restic` KB'lara sıkıştırır) | ✅ **Sağlıklı Denge:** Wallet/IAP finansal işlemleri için güçlü RPO, sıfır RAM baskısı, `<2 sn` saatlik artımlı aktarım |
| `4 saat` + `archive_timeout=0` | `4–27 saat` (segment dolmazsa) | `~42` snapshot (`7d`) | Minimum | ⚠️ Akşam açık artırma yoğunluğunda 4+ saat cüzdan işlemi kaybedilebilir |
| `24 saat` (yalnız günlük) | `24 saat` | `0` ek | Sıfır | ❌ Teqlif gibi finansal/wallet sistemi için yetersiz |

**Nihai WAL Kararı:**
1. **`node1` PostgreSQL:** `postgresql.conf` içinde `archive_timeout = 3600` (`1 saat`) ve `wal_compression = lz4` (veya `pglz` / PG 17 `zstd` desteği kontrol edilerek) açılır → düşük trafikte dahi her saat bir temiz kapalı WAL segmenti üretilir.
2. **`node2` Timer (`teqlif-offsite-wal.timer`):** Her saat `:45`'te (`OnCalendar=*-*-* *:45:00 UTC`) yalnızca `/project/teqlif/backups/pg_wal` dizinini (`--exclude '*.partial' --tag pg_wal`) `node101`'e pushlar; günlük ana yedek (`--tag daily-full`) ise tüm dizinlerle sabah `06:30 UTC`'de tek seferde koşar. *(İleride kullanıcı ölçeği 50K+ üzerine çıktığında trafik zaten segmentleri <15 dk'da doğal dolduracağı için timer istenirse 15–30 dk'ya çekilebilir.)*

---

### 3. Karar 3 — `/mnt/data` `fio` Benchmark Sonuçları (`✅ Adım 4'te Tamamlandı — 11 Kasım 2026`)

`node101/specs.md` içerisindeki ilk YABS testi yalnızca `/dev/vda3` (10G sistem SSD)'yi ölçtüğü için asıl yedek diski **`/mnt/data` (`/dev/vdb` 984G)** `fio 3.39` ile doğrudan test edildi (`05:23–05:25 UTC`) ve geçici dosyalar temizlendi (`/` `6.1G` boş, `/mnt/data` `934G` boş):

| Test (`node101:/mnt/data`) | Parametre | Ölçülen Sonuç | `clat` / `fsync` Gecikmesi | Mimari Çıkarım |
| :--- | :--- | :--- | :--- | :--- |
| **1. Sıralı `1M` R/W** | `2G`, `iodepth=8`, `direct=1`, `%50 R/W` | R **`137 MiB/s`** (`144 MB/s`) / W **`145 MiB/s`** (`153 MB/s`), `util=98.58%` | W `p50=52.2 ms`, `p99=56.4 ms`, `max=446 ms` | ✅ **1 Gbps (`~110 MB/s`) hattı rahatça karşılar**; ~150 MB/s tavanı nedeniyle gün içi ağır eşzamanlı iş yok |
| **2. Rastgele `4k` R/W** | `1G`, `iodepth=32`, `direct=1`, `%50 R/W` | R **`27.4k IOPS`** (`107 MiB/s`) / W **`27.4k IOPS`** (`107 MiB/s`), `util=93.44%` | R `p50=469 us` / W `p50=537 us`, `p99=1.76 ms` | ✅ KVM `ROTA=1` görünse de host katmanında **SSD/NVMe cache destekli** (saf mekanik HDD değil!) |
| **3. Senkron `64k` `fdatasync`** | `256M`, `iodepth=1`, `ioengine=sync`, `fdatasync=1` | **`83 IOPS` / `5321 KiB/s` (`5.45 MB/s`)** (`49.3 sn`) | `fdatasync` `p50=2.51 ms`, `p90=3.72 ms`, **`p95=60.6 ms`**, **`p99=229.6 ms`**, **`max=871.9 ms`** | ⚠️ **Kritik Doğrulama:** Küçük dosyada `fsync` çok pahalıdır (`5.45 MB/s`)! Dosya-dosya `rclone`/`rsync` yerine **`restic --pack-size 32`** (büyük blob paketleme) seçimi %100 doğru çıktı |

- **Tam Çıktı Kaydı:** [deploy/scale/V2.1/node101/specs.md](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/node101/specs.md) altına kalıcı olarak işlendi.
- **Konfigürasyon Kararı:** Yukarıdaki `fdatasync` tail latency (`p99=230ms`) bulgusu gereği `node2`'deki `restic backup` komutunda varsayılan `16 MiB` yerine **`--pack-size 32`** (32 MiB pack dosyaları) kullanılarak `node101` üzerindeki `fsync` çağrı sayısı yarıya indirilecektir.

---

### 4. Ağ & Erişim Modeli (`10.10.0.101`) ve Firewall Planı

```
[node1 (10.10.0.1)] ──(pg_dump/basebackup/wal/minio)──▶ [node2 (10.10.0.2)]
                                                              │
                                        WG Push (restic 0.18 -> http://10.10.0.101:8000)
                                        (--append-only: node2 SADECE EKLEYEBİLİR, SİLEMEZ)
                                                              ▼
[nodeMonitor (10.10.0.99)] ──(Prom/health scrape)────▶ [node101 (10.10.0.101)]
   ▲                                                    /mnt/data/restic-repo (984G ext4)
   └─ node1/3/4/5/6 -> node101 DOĞRUDAN YOL YOK!         └─ Local Weekly Prune/Check Timer
```

- **`node101` UFW Politika Taslağı:** Default `deny incoming`; `22/tcp` yalnız key-only SSH; `51820/udp` WireGuard; `8000/tcp` (`rest-server`) yalnız `in on wg0 from 10.10.0.2`; `9100/tcp` (`node_exporter`) yalnız `in on wg0 from 10.10.0.99`; IPv6 tüm kurallarda kapalı (`IPV6=no`).

---

### 5. Revize Hedef Zamanlama Penceresi Önerisi (Çakışmasız Sıralı Akış)

| UTC Penceresi | TR (`+3`) | Bileşen | Eylem |
| :--- | :--- | :--- | :--- |
| `00:00 – 02:55` | `03:00 – 05:55` | ARQ + `pg_basebackup` | Finans mutabakatı (`00:00`), PG→CH sync (`01:50`), Pazar `pg_basebackup` (`02:00`), T+14 release (`02:15`), CH Cache (`02:30`) |
| `03:00 – 03:45` | `06:00 – 06:45` | `node2` DB Yedekleri + ARQ Temizlik | `pg_dump` (`03:00` — Pazar `archive_old_dm_task` `02:50` veya `04:05`'e taşınır), CH Backup (`03:20`), Redis (`03:40`) |
| `03:45 – 05:15` | `06:45 – 08:15` | `node3`/`node4` Video Transfer + FAISS/Temizlik | Revize video transfer penceresi (`03:00` acil / `03:45` normal – `05:15`) → `05:30` `minio_backup`'tan önce biter |
| `05:00 – 06:15` | `08:00 – 09:15` | ARQ ML + `node2` Ek Yedekler | `05:30 minio_backup`, `06:00 notify_new_recordings`, `06:00–06:15` Loki/Kuma/Config (`--delete-excluded`)/Mail |
| `06:20` | `09:20` | `pg_wal_cleanup` | Eski WAL segment temizliği + `job_ok` |
| **`06:30 – 07:00`** | **`09:30 – 10:00`** | **`node2` → `node101` Ana Offsite (`daily-full`)** | `restic backup --tag daily-full`, `IOSchedulingClass=idle`, `Nice=19`, temizlenmiş tüm dizinler + `pg_basebackup` + kapalı `pg_wal` |
| **Her Saat `:45`** | — | **`node2` → `node101` Saatlik WAL (`pg_wal`)** | `restic backup --tag pg_wal /project/teqlif/backups/pg_wal --exclude '*.partial'` (**PG RPO ≤ 1 saat**) |
| **`07:30+ UTC`** | **`10:30+`** | OS `apt-daily-upgrade` & `node101` `prune` | Tüm node'larda `apt-daily-upgrade` `07:30 UTC` sonrasına çekilir; `node101` Pazar `08:00 UTC` yerel `forget/prune/check` |

---

### 6. Felaket Kurtarma (DR) Runbook Tasarımı (`OFFSITE-11` Hedefi)

| Senaryo | Kayıp Durumu | Kurtarma Sırası & Kaynağı | Hedef RPO / RTO |
| :--- | :--- | :--- | :--- |
| **Senaryo A** | `node2` disk/sunucu kaybı (`node1` sağ) | Yeni `node2` kurulur → WG (`10.10.0.2`) → **`restic restore latest --tag daily-full`** ile geçmiş `loki`/`stalwart`/`uptime_kuma`/`pg_basebackup` geri alınır → `pg_receivewal` ve replica yeniden bağlanır. | Backup geçmişi kaybı `≤ 1 saat`; API kesintisi **`0 dk`** |
| **Senaryo B** | `node1` kaybı (`node2` sağ) | Mevcut [`node2/resources/scripts/runbook.sh`](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/node2/resources/scripts/runbook.sh) ile `node2` standby/PITR + MinIO + Redis devreye alınır (DNS/VIP failover + yeni `node1`). | Yerel WAL (`≤ birkaç sn`) / `2–15 dk` RTO |
| **Senaryo C** | **Çifte Felaket (`node1` + `node2` ikisi de gitti / OVH hesabı yok)** | 1. Yeni DB/App VPS açılır, Key Escrow kasasından **Restic repo şifresi** alınır.<br>2. `node101` `wg0.conf` geçici yeni node IP'sine izin verir (veya `node101`'den pull).<br>3. Sırayla geri yükleme: `nodemonitor_config` (`.env` / sırlar) → `pg_basebackup` + `pg_wal` PITR (veya `pg_dump` `-Fc`) → `minio` (`teqlif`, `teqlif-dm`) → `clickhouse` → `redis` → `stalwart` → `uptime_kuma`.<br>4. DNS Cloudflare A kaydı yeni sunucuya çevrilir ve smoke test koşulur. | **DB RPO ≤ 1 saat**; MinIO & diğer servisler `≤ 24 saat`; RTO `~1–3 saat` |

---

### 7. İmplementasyon Öncesi Dosya & Sunucu Etki Haritası

Uygulama adımına geçildiğinde değiştireceğimiz / oluşturacağımız kalemlerin tam listesi:

- **Yeni Oluşturulacaklar (`deploy/scale/V2.1/node101/`):**
  - `deploy/scale/V2.1/node101/specs.md` (`fio` `/mnt/data` sonuçları eklenecek)
  - `deploy/scale/V2.1/node101/bootstrap_node101.sh` (TZ `UTC`, UFW, WG `10.10.0.101`, `restic-rest-server`, `/mnt/data` dizinleri, `prometheus-node-exporter`)
  - `deploy/scale/V2.1/node101/systemd/restic-rest-server.service` (`--append-only --listen 10.10.0.101:8000`)
  - `deploy/scale/V2.1/node101/systemd/teqlif-offsite-prune.{service,timer}` (`GOMEMLIMIT=1536MiB`, `GOGC=20`, `MemoryMax=2G`, Pazar `08:00 UTC`)
  - `deploy/scale/V2.1/node101/systemd/teqlif-offsite-verify.{service,timer}` (`restic check --read-data-subset=5%`)
  - `deploy/scale/V2.1/node101/resources/offsite_restore_runbook.md` (veya `scripts/restore_from_node101.sh`)
- **Güncellenecekler (Repo + Canlı):**
  - `deploy/scale/V2.1/secrets.env.template`, `scripts/wg_mesh_apply.sh`, `scripts/bootstrap_node2.sh` (`7` eksik timer `enable`), `scripts/_common.sh` (`logrotate` glob düzeltmesi + `agent.log` rotasyonu + `journald` kotası)
  - `deploy/scale/V2.1/node2/resources/scripts/offsite_sync.sh` + yeni `offsite_wal_sync.sh` + `nodemonitor_config_backup.sh` (`--delete-excluded`, `loki/wal`, **`grafana/` & `shared/config`**) + `mail_backup.sh` (`config.toml`, `.env.mail`, `acme/`, `tar -tzf`) + `loki_backup.sh` (`compactor/`, TSDB index, `job_ok`) + `uptime_kuma_backup.sh` (`.tmp`+`gzip -t`+`--single-transaction`, `.my.cnf`/`env`, `job_ok`) + `minio_backup.sh` (`15g` yerel temizlik, `confirm_recordings` zaman damgası kilidi) + `clickhouse_backup.sh` (`BACKUP` yetkisi + `SHOW CREATE` DDL) + `pg_dump.sh` (`--globals-only`, `.dump*`) + `pg_basebackup.sh` (atomik `.tmp`→`mv`) + `runbook.sh` (`pg_wal.tar.gz` + PITR `recovery_target` kaldırma) + `pg_wal_cleanup.sh` (`job_ok`)
  - `deploy/scale/V2.1/node2/systemd/teqlif-offsite-sync.{service,timer}` + yeni `teqlif-offsite-wal.{service,timer}` + diğer servislere `Nice=19`/`IOSchedulingClass=idle`
  - `deploy/scale/V2.1/schedule.yaml` (`backup:` anahtarı + `offsite_sync`, `offsite_wal_sync`, `loki`, `kuma`, `config`, `wal_cleanup`, `cleanup_old_stream_chat_messages_task` tekilleştirmesi + DM/push saat optimizasyonu) + `teqlif-agent/{db.py,gossip.py}` (`cleanup_log` `UNIQUE` + kalıcı `_last_sync`) + `teqlif-agent/modules/{health.py,watchdog.py,reporter.py,cleaner.py,janitor.py,recorder.py,encoder.py}` + `backend/app/worker.py` (ARQ `_agent_ok`, batch `DELETE`, `sync_pg_to_clickhouse_task` pagination, `cleanup_old_media_messages_task` OOM/`60d`→`3/7d` + commit sırası)
  - `backend/app/routers/{messages.py,streams.py,auth.py}`, `backend/app/services/storage_service.py`, `backend/app/tasks/{wallet_tasks.py,dm_archive_tasks.py,listing_tasks.py,analytics_tasks.py,stream_recording_tasks.py}` (`BIZ-01..05` DM `teqlif-dm` bucket okuma, PRO 14g kayıt tutarlılığı, finansal mutabakat alarmı, KVKK `delete_account` & push penceresi)
  - `deploy/scale/V2.1/cluster.yaml` + `encoder.py` / `worker.py` (`MAINT-02` transfer penceresi + `.log`/0-byte yetim temizliği)
  - `deploy/scale/V2.1/nodeMonitor/config/teqlif/{prometheus.yml,alert_rules.yml}` + dış Dead Man's Switch (`node2`/`node1` → `nodeMonitor`)
  - Canlı `node1` PG `postgresql.conf` (`archive_timeout = 3600`, `wal_compression = lz4`, `max_slot_wal_keep_size`, `lock_timeout`, `idle_in_transaction_session_timeout`) + `node2` & `node5` ClickHouse `system.*_log` TTL & `node2` DR cluster (`postgresql-17-pgvector`, `.env.dr`, `cf-origin.*`)
  - Canlı `node2` (zehirli `/var/lib/teqlif-redis-failover/promoted` + rogue `redis-failover.timer`/`redis-failover-check.sh` temizliği + `redis_failover.sh` WG izolasyon düzeltmesi + `979 MB` TSDB çöpü, `7` `.dump.gz` ve `13 Eki` `20B` Kuma dosyası + terk edilmiş `teqlif_staging_analytics` temizliği) + `node5` (`194M /var/recordings` + `3.2G /root/.cache` temizliği)
  - Tüm node'lar (`node1..6`, `node2`, `nodeMonitor`): `apt-daily-upgrade` override (`07:30 UTC+`), `logrotate` + `agent.log` rotasyon + `journald` `SystemMaxUse` + `nodeMonitor` Prometheus hedefi

---

## 🎯 Master Eylem Planı (Aşamalı Mühendislik Yol Haritası)

### 🟣 Faz 0: `node101` Hazırlık ve Ağ İzolasyonu (Ön Koşul)
1. ~~**`node101` `/mnt/data` `fio` Benchmark & [specs.md](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/node101/specs.md):**~~ ✅ **Tamamlandı (11 Kasım 2026 — Adım 4)**. Kalan hazırlık: `node101` timezone `UTC` yapılacak, `/mnt/data/{restic-repo,tmp,cache,logs}` kurulacak (`/` `6.1G` koruması).
2. **WireGuard `10.10.0.101` + UFW + `node_exporter`:** Yalnız `node2` ve `nodeMonitor` peering'i, SSH key-only, IPv6 drop.

### 🔴 Faz 1: Acil P0 — Canlı Failover, DR, Finans & Ürün Veri Bütünlüğü
3. **Canlı `node2` Redis Failover & DR Onarımı (`MAINT-03`, `AUDIT-01`, `BIZ-02`):**
   - Zehirli `/var/lib/teqlif-redis-failover/promoted` ve rogue `redis-failover.timer` / düz metin şifreli `/usr/local/bin/redis-failover-check.sh` kaldırılacak; `redis_failover.sh`'deki `node1` tüm WG trafiğini kesen `0.0.0.1/32` bloğu düzeltilip tek `teqlif-redis-failover.timer` doğrulanacak.
   - `node2`'ye `postgresql-17-pgvector` kurulacak, DR PG cluster + `.env.dr` + `/etc/ssl/teqlif/cf-origin.*` hazırlanacak; `pg_dump.sh` (`--globals-only`), `pg_basebackup.sh` (atomik `.tmp`→`mv`) ve `runbook.sh` (`pg_wal.tar.gz` + gerçek PITR) düzeltilecek.
   - Canlı `node1` PG üzerine **`max_slot_wal_keep_size`**, `lock_timeout` ve `idle_in_transaction_session_timeout` güvenlik sınırları eklenecek; `daily_financial_reconciliation_task` (`00:00`) anomali durumunda acil Telegram/Sentry alarmı verecek şekilde güncellenecek.
4. **Ürün Veri Bütünlüğü Düzeltmeleri (`BIZ-01`):**
   - `storage_service.py` içine `list_object_keys_dm` eklenip `messages.py` `/archive` endpoint'i `teqlif-dm` bucket'a yönlendirilecek; `archive_old_dm_task` `03:00 UTC` `pg_dump` çakışmasından ayrılacak (`02:50` / `03:45`).
   - Standart host 14g kayıt vaadi / PRO upsell (`streams.py`, `stream_recording_tasks.py`, `setup_minio_ilm.sh`, `minio_backup.sh` 15g↔30g) tutarlı hale getirilecek (`404 NoSuchKey` giderilecek).
5. **`restic` + `rest-server --append-only` Kurulumu (`OFFSITE-02`, `OFFSITE-03`):** `node101`'de `rest-server` ayağa kaldırılacak, `node2`'den şifreli ilk repo init + **3 bağımsız noktada Key Escrow** doğrulanacak; `node101` yerel `prune`/`verify` timer'ları kurulacak (`GOMEMLIMIT=1536MiB`, `MemoryMax=2G`).
6. **`offsite_sync.sh` & Saatlik `offsite_wal_sync.sh` + İzleme (`OFFSITE-04`, `OFFSITE-07`, `OFFSITE-10`):** Konfig yoksa `exit 2`, `OnFailure=teqlif-backup-failed@%n.service`, `IOSchedulingClass=idle`, `Nice=19`, `systemctl enable --now`, `job_ok` + sentinel + `schedule.yaml` + `health.py` entegrasyonu + **`node1` PG `archive_timeout=3600`**.

### 🟠 Faz 2: P1 — Veri Kapsamı, Telemetri, KVKK/Push, SPOF & Ölçek Tıkanıklıkları
7. **Eksik Backup Kapsamı & Hijyeni (`OFFSITE-08`, `OFFSITE-09`, `AUDIT-03`, `AUDIT-04`, `BIZ-04`):** `nodemonitor_config_backup.sh` (`--delete-excluded` + `loki/wal/` + **`grafana/` & `shared/config`**), `mail_backup.sh` (`config.toml`, `.env.mail`, `acme/`, `tar -tzf` ve gece `03:30 UTC` saatine kaydırma), `loki_backup.sh` (`compactor/`), `clickhouse_backup.sh` (`BACKUP` grant + `SHOW CREATE` DDL), `minio_backup.sh` (`15g`/30g temizlik + `--remove`/KVKK + `confirm_recordings` sınırı) ve `uptime_kuma_backup.sh` (atomik `.tmp`, `gzip -t`, şifre gizliliği).
8. **Telemetri, SPOF & KVKK / Push Penceresi (`AUDIT-02`, `BIZ-03`, `BIZ-04`):** `watchdog.py`, `worker.py` `_agent_ok`, `recorder`, `reporter.py`; `nodeMonitor` için dış Dead Man's Switch + Prometheus'a `ClickHouse`/`MinIO`/`Redis Replica`/`pg_receivewal`/`Stalwart` eklenmesi; `delete_account` bakiye/DM temizliği ve `07:00 TR` promosyonel push fırtınasının gün içi/quiet-hours uyumlu pencereye çekilmesi.
9. **Ölçek & Temizlik Onarımları (`AUDIT-05`, `MAINT-01..02`, `BIZ-05`):** `sync_pg_to_clickhouse_task` cursor + `LIMIT` pagination düzeltmesi; `listing_tasks.py` chunk + `raise` düzeltmesi; `node2`/`node5` ClickHouse `system.*_log` TTL + temizlik; `node5` `/var/recordings` (`194M`) + `encoder.py` `.log`/0-byte cleanup; `cleaner.py` & video transfer penceresi.

### 🟡 Faz 3: P2–P3 — Sistem Tutarlılığı, Log Hijyeni, OS Bakım & Kurtarma Tatbikatı
10. **Logrotate, `agent.log`, `journald`, SQLite & ARQ Batch Düzeltmeleri (`MAINT-04..08`, `AUDIT-06..08`):** `_common.sh` glob/nodeMonitor düzeltmesi + `/var/log/teqlif-agent/agent.log` rotasyonu + `journald` `SystemMaxUse` + `teqlif-agent` `cleanup_log` `UNIQUE`/budama + `worker.py` batch `DELETE` & `media_messages` OOM/`60d`→`3/7d`/commit sırası düzeltmesi + `bootstrap_node2.sh` 7 timer `enable` + `apt-daily-upgrade` `07:30 UTC+` + `nodeMonitor` RAM iyileştirmesi.
11. **DR Runbook & İlk Restore Tatbikatı (`OFFSITE-11`, `OFFSITE-13`, `BIZ-03`):** `node2` yerel PITR tatbikatı (`runbook.sh --dry-run` / test) + `node101`'den geçici test dizinine şifreyle gerçek `pg_dump` / `pg_basebackup` + `pg_wal` PITR restore testi ve TTK/MASAK WORM `financial_archives` akışı.

---

## 📝 Devam Analizleri & Güncelleme Günlüğü (Üzerine Ekleme Alanı)

> Bu bölüm açık uçludur. Her yeni denetim, karar, `fio` sonucu veya commit buraya kronolojik bir alt başlık olarak eklenir; yukarıdaki özet tablosu ve bulgu durumları (`⬜ Açık` → `✅ Çözüldü <commit>`) paralel güncellenir.

### Adım 1 — 2026-11-11 · İlk Kod Tabanı & Mimari Hazırlık Analizi (Tamamlandı)
- `offsite_sync.sh`, `health.py`, `watchdog.py`, `schedule.yaml`, `cluster.yaml`, `V1.0`/`V1.1` incelendi; 10 temel `OFFSITE` bulgusu çıkarıldı.

### Adım 2 — 2026-11-11 · `node101` Entegrasyonu & Canlı Cluster Tam Bakım/Yedekleme Denetimi (Tamamlandı)
- Yeni hedef VPS `node101` (`195.206.234.142`) canlı SSH + `deploy/scale/V2.1/node101/specs.md` ile incelendi; tüm 8 node OS/TZ/donanım envanteri (`Debian 13 trixie`, `nodeMonitor Europe/Berlin`, `node101 Europe/London`) doğrulandı ve `OFFSITE-01..13` + `MAINT-01..08` dokümante edildi.

### Adım 3 — 2026-11-11 · Mimari Kilitleme, WAL RPO Kanıtı, `fio` SOP & DR Blueprint (Tamamlandı)
- **Motor Kararı Kilitlendi:** `restic 0.18.0` (`node2`) → `restic-rest-server 0.13.0 --append-only` (`node101`) seçildi; Debian 13 paket sürümleri doğrulandı.
- **WAL Sıklığı Kanıtlandı & Belirlendi:** Canlı `node1` PG `archive_timeout=0` ve `node2` segment aralıklarının `15–27 saat` olduğu ölçüldü → Sağlıklı çözüm: **`node1` `archive_timeout = 3600` + `wal_compression = lz4` + Saatlik (`*:45:00 UTC`) `--tag pg_wal` Push (`--keep-within 7d`)** → PG RPO `≤ 1 saat`.
- **`/mnt/data` `fio` Benchmark Prosedürü & DR Runbook + Dosya Etki Matrisi** dokümana işlendi; doküman implementasyon öncesi son haline getirildi.

### Adım 4 — 2026-11-11 · `node101:/mnt/data` `fio-3.39` Benchmark Tamamlandı (Tamamlandı)
- `seq-rw` (`137/145 MiB/s`), `rand-4k` (`27.4k/27.4k IOPS`), `sync-write` (`83 IOPS / 5.45 MB/s`, `fdatasync` `p99=229.6ms`, `max=871.9ms`) ölçüldü ve [deploy/scale/V2.1/node101/specs.md](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/node101/specs.md) içine eklendi.
- Çıkan `fdatasync` tail latency sonucu doğrultusunda **`--pack-size 32`** kuralı blueprint'e eklendi (file-by-file transferin `5.45 MB/s`'te tıkanacağı kanıtlandı).

### Adım 5 — 2026-11-11 · Uçtan Uca Bakım, DR, Birikme & Telemetri Tam Denetimi (Tamamlandı)
- Kod tabanı (`schedule.yaml`, `worker.py`, `teqlif-agent/*`, `node2/resources/scripts/*`, `_common.sh`, `bootstrap_node2.sh`) + tüm 8 canlı node üzerinden tam sağlamlık, veri bütünlüğü, log/disk birikimi ve DR failover denetimi yapıldı.
- **Yeni Kritik Bulgular:** Canlı yedeklerin çekirdek dosyaları (`pg_dump` 647 öğe, `redis`, `mail` 643 dosya, `uptime_kuma` 67.015 satır) sağlam doğrulanırken; **`MAINT-03`** (`promoted` bayrağı yüzünden 18 Eki'den beri kör resmi Redis failover + rogue düz metin script) **`P0`'a yükseldi** ve **`AUDIT-01..08`** (kırık `node2` DR/`pgvector`/PITR, Grafana `521 MB` & Mail/Loki eksik kapsamı, Watchdog donmuş SQLite `Nov 1` & eksik cron `_agent_ok`, ClickHouse `system.*_log` `2.38G`/`5.4G` şişmesi, kırık `logrotate **/*.log`, `565 MB` `agent.log`, `1.2G`/`1.6G` `journald`, `194M` `/var/recordings`, `15g` MinIO temizlik eksiği & race, `cleanup_log` SQLite çoğaltma ve batch'siz ARQ silmeleri) dokümana eklendi ve Master Eylem Planı (Faz 1–3) güncellendi.

### Adım 6 — 2026-11-11 · İş Mantığı, Finans, KVKK/Uyum, SLA & Ölçek Analizi (Tamamlandı)
- Yedekleme ve bakım penceresinin kullanıcı deneyimi, gelir modelleri (PRO / airdrop / finans), KVKK/TTK/MASAK uyumu, SPOF dayanıklılığı ve `>50K` ölçek sınırları incelendi (`messages.py`, `dm_archive_tasks.py`, `storage_service.py`, `wallet_tasks.py`, `stream_recording_tasks.py`, `streams.py`, `listing_tasks.py`, `analytics_tasks.py`, `auth.py`, `notification_service.py`, `node1` PG settings, `nodeMonitor` Prometheus hedefleri).
- **`BIZ-01..05` Bulguları Eklendi:** DM arşivi wrong-bucket hatası (`teqlif` vs `teqlif-dm`), Standart 14g video PRO upsell vs 2g ILM kırılması, sessiz finansal mutabakat (`00:00`), canlı `node1` PG `max_slot_wal_keep_size = -1` & `0ms` timeout'lar, `redis_failover.sh` WG `node1` peer kesme tuzağı, KVKK `delete_account` & `--remove` yokluğu, `07:00 TR` push fırtınası, `nodeMonitor` dış gözcü (SPOF) + eksik servis metrikleri, `09:15 TR` mail stop (`4.9M→5.3M` idle büyüme) ve `sync_pg_to_clickhouse_task` `LIMIT` veri kaybı riski dokümante edildi.

### Adım 7 — *(Bekleyen Sonraki Adım: İmplementasyon Faz 0 → Faz 3)*
- **Amaç:** Kullanıcı implementasyon onayını verdiğinde yukarıdaki **Faz 0–3** kapsamındaki tüm `OFFSITE-01..13`, `MAINT-01..08`, `AUDIT-01..08` ve `BIZ-01..05` düzeltmelerini repoya işlemek ve `node101` + canlı küme üzerinde doğrulamak.
