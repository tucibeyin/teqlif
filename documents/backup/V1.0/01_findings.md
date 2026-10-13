# Backup Sistem Analizi — Bulgular

**Tarih:** 2026-10-13
**Kapsam:** node2 backup script'leri, izleme katmanları, TTL/yaşam döngüsü, risk değerlendirmesi
**Revizyon:** Dış kod incelemesinden gelen doğrulanmış bulgular eklendi.

---

## 1. İzleme Katmanları

İki bağımsız katman çalışıyor.

### Katman A — Redis Heartbeat (watchdog.py)

Her backup script başarılı tamamlanınca `HSET teqlif:agent:job_ok <name> <timestamp>` yazar.
`watchdog.py` bu zaman damgasını `schedule.yaml`'daki `watchdog_m` ile kıyaslar; eşik aşılırsa Telegram uyarısı gönderir.

| Job | Timer (UTC) | watchdog_m | Maks. sessiz kalma |
|---|---|---|---|
| pg_dump | 03:00 | 1500 | ~25 saat |
| clickhouse_backup | 03:20 | 1500 | ~25 saat |
| redis_backup | 03:40 | 1500 | ~25 saat |
| mail_backup | 06:15 | 1500 | ~25 saat |
| minio_backup | 05:30 | 1500 | ~25 saat |
| pg_basebackup | Pazar 08:30 | 10080 | **7 gün** |

> **schedule.yaml uyumsuzlukları (watchdog_m fonksiyonel değil, doküman yanlış):**
> - `minio_backup`: schedule.yaml 04:00, gerçek timer 05:30
> - `mail_backup`: schedule.yaml 03:45, gerçek timer 06:15
>
> **clickhouse_backup unit konum hatası:** `teqlif-clickhouse-backup.service/.timer` ana `node2/systemd/` dizinine değil, `node2/resources/systemd/` altına yanlışlıkla bırakılmış. Ayrıca timer'da `WantedBy=multi-user.target` yazıyor; `timers.target` olmalı. Symlink ya da taşıma yapılmadığı sürece boot sonrası timer etkinleşmeyebilir.

### Katman B — Filesystem Yaş İzlemesi (health.py)

`_backup_ages()` fonksiyonu `/project/teqlif/backups/` altındaki dosyaların gerçek mtime'ını okur.
Redis HSET başarısız olsa bile bu katman bağımsız çalışır. Eşik: `_BACKUP_MAX_MIN = 1500 dakika`.

**Katman B'nin izlediği backup'lar:**

| Backup | İzleme Yöntemi |
|---|---|
| pg_backup | Dizin içindeki en yeni dosyanın mtime |
| minio_backup | Dizin içindeki en yeni dosyanın mtime |
| redis_backup | Dizin içindeki en yeni dosyanın mtime |
| mail_backup | `.last_mail_backup_ok` sentinel dosyası |
| loki_backup | `.last_backup_ok` sentinel dosyası |
| uptime_kuma_backup | Dizin içindeki en yeni dosyanın mtime |
| nodemonitor_config_backup | Dizin içindeki en yeni dosyanın mtime |
| **clickhouse_backup** | ❌ **İZLENMİYOR** |
| **pg_basebackup** | ❌ **İZLENMİYOR** |

ClickHouse ve pg_basebackup, Katman B'de yoktur — yalnızca Katman A'ya (Redis heartbeat) bağımlıdır. pg_basebackup için bu 7 günlük kör nokta demektir.

Tersine, loki/uptime_kuma/nodemonitor_config backupları Katman B'de izleniyor ama `schedule.yaml`'da `watchdog_m` tanımları yok — Katman A'da izlenmiyorlar. Bu 3 backup için "iki bağımsız katman" iddiası geçerli değil; yalnızca filesystem yaş izlemesi çalışıyor.

### Yapısal Boşluk

Tüm servislerde `OnFailure=` yok. Bir script `set -euo pipefail` ile çıkış 1 verse bile sistem watchdog_m geçene kadar (günlük backup'lar için ~25 saat, pg_basebackup için 7 gün) sessiz kalır.

---

## 2. Script Güvenilirliği

### mail_backup.sh — KRİTİK BUG

`set -euo pipefail` devrede. Script `sudo systemctl stop stalwart-mail` yaptıktan sonra `tar` çalıştırıyor. `trap` yok. `tar` disk dolması veya izin hatası nedeniyle başarısız olursa script anında sonlanır; `sudo systemctl start stalwart-mail` hiçbir zaman çalışmaz ve **mail servisi durdurulmuş halde kalır**.

```bash
# Mevcut — HATALI
sudo systemctl stop stalwart-mail
tar -czf "${DEST}" /project/mail/data ...   # burada hata → script çıkar
sudo systemctl start stalwart-mail          # ← ASLA ÇALIŞMAZ

# Düzeltme
trap 'sudo systemctl start stalwart-mail' EXIT
sudo systemctl stop stalwart-mail
tar -czf "${DEST}" /project/mail/data ...
```

### pg_dump.sh — ORTA

- `set -euo pipefail` var.
- Dump dosyası doğrudan `$DEST`'e yazılıyor, `.tmp` yok. Aktarım ortasında kesilirse kırık `.dump` diskte kalır; `-mtime` temizliği onu geçici olarak geçerli backup gibi görür.
- `pg_restore --list` bütünlük doğrulaması yok — bozuk backup bir sonraki restore girişimine kadar fark edilmez.
- 7 günlük retention ✓, retry yok.

### minio_backup.sh — İYİ (retry eksik)

- `mc mirror --overwrite` — `--remove` kasıtlı yok. node1 MinIO ILM 2 günde nesneyi siler; node2 HDD'de kalıcı birikim sağlanır. Doğru tasarım.
- `confirm_recordings()` PG güncellemesi başarısız olsa bile `return 0` ile geçiliyor. Savunmacı tasarım ✓.
- 12 KB minio backup klasörü: hata değil, ürün yeni ve henüz çok az kayıt var.
- Retry yok; ağa en bağımlı, en kritik backup job'ı.

### clickhouse_backup.sh — HATA (sessiz yanlış pozitif)

3-yol fallback zinciri: `cmd1 || cmd2 || (fallback)`. Fallback subshell içindeki son komutlar `echo` ve `logger` olduğu için zincirin exit kodu her durumda 0. ClickHouse servisi tamamen çökmüş, tüm tablo exportları boş bile olsa HSET "OK" yazılır. Watchdog bunu başarılı backup sanır.

Ek sorun: fallback içindeki `|| true` satırları, tablo başına boş export geçirilmesine izin verir.

### redis_backup.sh — ORTA (race condition)

- BGSAVE **asenkron**. `sleep 5` hardcoded — Redis belleği büyüdüğünde veya disk I/O yoğun olduğunda BGSAVE 5 saniyede tamamlanmayabilir. Bu durumda `cp` komutu o anki dump'ı değil, bir önceki günün eski RDB dosyasını kopyalar.
- Düzeltme: `redis-cli info persistence | grep rdb_bgsave_in_progress` değeri 0 olana kadar (timeout ile) döngüde beklenmelidir.

### pg_basebackup.sh — YÜKSEK RİSK

- `--wal-method=stream` — WAL yedek içine dahil ✓.
- 2 haftalık pencere için 2 backup retention ✓.
- `OnFailure=` yok. Pazar 08:30'daki job başarısız olursa **bir sonraki Pazar'a kadar sessiz kalır**.
- `teqlif-pg-receivewal.service` `Restart=always` ile WAL sürekli akıyor — hafifletici faktör: PITR için pg_dump + WAL arşivi kullanılabilir.

---

## 3. Servis Envanteri

**9 backup servisi** (timer veya one-shot):

| Servis | Timer | Konum |
|---|---|---|
| teqlif-pg-dump | 03:00 | node2/systemd/ |
| teqlif-clickhouse-backup | 03:20 | ⚠️ **node2/resources/systemd/** (yanlış yer) |
| teqlif-redis-backup | 03:40 | node2/systemd/ |
| teqlif-minio-backup | 05:30 | node2/systemd/ |
| teqlif-pg-basebackup | Pazar 08:30 | node2/systemd/ |
| teqlif-loki-backup | 06:00 | node2/systemd/ |
| teqlif-uptime-kuma-backup | 06:05 | node2/systemd/ |
| teqlif-nodemonitor-config-backup | 06:10 | node2/systemd/ |
| teqlif-mail-backup | 06:15 | node2/systemd/ |

**Toplam: 9 backup servisi.**

`teqlif-clickhouse-backup.timer`: `WantedBy=multi-user.target` yazıyor; `timers.target` olmalı. Boot'ta timer etkinleşmeyebilir.

---

## 4. TTL ve Veri Yaşam Döngüsü

### Kayıt Yaşam Döngüsü

```
live_stream → recording → encoding → encoded → transferring
  → available (24h kullanıcı erişimi)
  → expired → archived → deleted
```

| Parametre | Değer | Kaynak | Açıklama |
|---|---|---|---|
| user_access_hours | 24h | cluster.yaml | Kullanıcı kaydı izleyebilir |
| minio_expiry_days | 2 gün | cluster.yaml → ILM | node1 MinIO nesneyi siler |
| minio_backup | 05:30 UTC | timer | node2'ye mirror (kalıcı birikim) |
| recording_retention_days | 15 gün | schedule.yaml ttl | node2'de saklama süresi |

Zincir bütünlüğü sağlam. Janitor yalnızca sayar, gerçek silme `cleanup_actions.sh` üzerinden.

### PostgreSQL PITR

`teqlif-pg-receivewal.service` sürekli WAL akıtıyor + `pg_basebackup` (haftalık) + `pg_dump` (günlük) → üç katmanlı PITR kapasitesi mevcut.

### Redis

Büyük çoğunluk yeniden inşa edilebilir. Chat geçmişi stream bitişinde DB'ye dump ediliyor.

### node2 Disk

3.6 TB toplam, 5.1 GB kullanılmış (%0.14). Alan endişesi yok.

---

## 5. Risk Değerlendirmesi

| Backup | Risk | Gerekçe |
|---|---|---|
| mail_backup | **KRİTİK** | `trap` eksikliği — başarısız backup, mail servisini kapalı bırakır. |
| minio_backup | **YÜKSEK** | Başarısız + ILM 2 günde siler = kalıcı veri kaybı. En kritik backup job'ı. |
| pg_basebackup | **ORTA-YÜKSEK** | 7 günlük kör nokta. pg_receivewal fallback var ama restorasyon çok yavaş. |
| pg_dump | **ORTA** | WAL + pg_basebackup ile PITR mümkün. Bozuk dump 7 güne kadar fark edilmeyebilir. |
| clickhouse_backup | **ORTA** | Sessiz yanlış pozitif bug + unit dosyası yanlış dizinde, timer target hatalı. |
| redis_backup | **DÜŞÜK** | BGSAVE race condition riski; içerik büyük ölçüde yeniden inşa edilebilir. |
| disk_space | **SORUNSUZ** | 3.6 TB toplam, %0.14 kullanılmış. |

---

## 6. Uygulama Kararı

Uygulanmalı. Hiçbir değişiklik uygulama servislerine, DB şemasına veya routing'e dokunmuyor.
Hepsi node2 backup script'leri, systemd unit dosyaları ve teqlif-agent modülleri kapsamında kalıyor.

### Öncelik Sıralaması

**P0 — Hemen (servis çökmesi ve sessiz hataları kapat):** ✅ 2026-10-13

1. ✅ `mail_backup.sh`: `trap 'sudo systemctl start stalwart-mail' EXIT` eklendi.
2. ✅ `clickhouse_backup.sh`: `if/elif/else` ile yeniden yazıldı. Fallback'te `|| true` kaldırıldı; HSET yazılıp `exit 2` ile çıkılır — watchdog yanlış pozitif görmez, `OnFailure=` tetiklenir.
3. ✅ `notify_backup_failed.sh` + `teqlif-backup-failed@.service` oluşturuldu. Tüm 9 backup servisine `OnFailure=teqlif-backup-failed@%n.service` eklendi. `.env.backup`'a `TELEGRAM_BOT_TOKEN`/`TELEGRAM_CHAT_ID` eklendi (node2 sunucusunda).
4. ✅ `teqlif-clickhouse-backup.service/.timer` `node2/resources/systemd/` → `node2/systemd/` taşındı. `WantedBy=multi-user.target` → `timers.target`. Timer aktif.

**P1 — Güvenilirlik artışı:**

5. `pg_dump.sh`: `${DEST}.tmp`'ye yaz → `pg_restore --list` ile doğrula → `mv` ile taşı.
6. `minio_backup.sh`: 3x retry döngüsü, 2 dakika backoff (WireGuard ağ dalgalanmalarına karşı).
7. `health.py`: `_backup_ages()` içine `clickhouse_backup` ve `pg_basebackup` dizinlerini ekle.

**P2 — Süreç iyileştirmeleri:**

8. `redis_backup.sh`: `sleep 5` yerine `rdb_bgsave_in_progress` döngüsü (timeout ile).
9. `schedule.yaml`: `minio_backup` 04:00 → 05:30, `mail_backup` 03:45 → 06:15 olarak düzelt.
10. `teqlif-pg-basebackup.timer` Description satırı: "Pazar 02:00 UTC" → "Pazar 08:30 UTC" (kalıntı düzeltme).
