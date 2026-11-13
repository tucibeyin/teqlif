# teqlif V2.1 — Offsite Felaket Kurtarma Runbook (`node101` → Yeni Sunucu)

**Versiyon:** V2.1  
**Son Güncelleme:** 2026-11-13  
**Hedef Kitle:** teqlif SRE / Yönetici  
**Çalıştırılacak Yer:** node101 (yerel) veya WireGuard erişimi olan herhangi bir sunucu  
**İlgili Script:** `deploy/scale/V2.1/node101/resources/scripts/restore_from_node101.sh`  
**Mevcut Runbook:** `deploy/scale/V2.1/node2/resources/scripts/runbook.sh` (node2→node1 kurtarma)

---

## Senaryolar ve RPO/RTO

| Senaryo | Kayıp | RPO | RTO | Yöntem |
|---------|-------|-----|-----|--------|
| **A** | Yalnız node2 | 0 (node1 canlı) | ~2 saat | bootstrap_node2 + offsite restore |
| **B** | Yalnız node1 | ~1 dk (pg_wal hourly) | ~1 saat | `runbook.sh` (node2→node1) |
| **C** | node1 + node2 | ~1 saat (son pg_wal) | ~4 saat | Bu runbook: node101 → yeni node1 |
| **D** | node1 + node2 + node101 | Offline hazırlık gerekli | — | Manuel gpg decrypt + pg_restore |

> **Öncelik:** Senaryo B varsa önce `runbook.sh` deneyin. Bu runbook yalnız node2 de yoksa veya
> `runbook.sh` başarısız olduğunda kullanılır.

---

## 1. Ön Koşullar

### 1a. node101 Erişimi

```bash
ssh node101              # Public IP: 195.206.234.142
# WireGuard: 10.10.0.101 (wg0 aktifse)
```

### 1b. Credentials — Key Escrow

**Çift felaket (node1+node2 kaybı) durumunda:** restic şifresi node101'dedir.

```bash
# node101 üzerinde:
sudo cat /etc/teqlif-offsite/restic.env | grep -v "#"
# RESTIC_REPOSITORY=/mnt/data/teqlif
# RESTIC_PASSWORD=<restic_sifre>
```

Yedek erişim: `cluster_secrets_backup.sh` her gün 06:20 UTC'de
`/project/teqlif/config/.env.backup` içeriğini (RESTIC_REST_USER, RESTIC_REST_PASSWORD dahil)
offsite_sync ile node101'e yükler:
```
Snapshot: daily-full → /project/teqlif/backups/cluster_secrets/node2/
```

### 1c. Araçlar

```bash
# Yeni sunucuda:
apt-get install -y restic postgresql-17 postgresql-client-17
# restic sürümü: 0.18+
restic version
```

---

## 2. Mevcut Snapshot'ları Listele

```bash
# node101 üzerinde (root):
sudo bash -c '. /etc/teqlif-offsite/restic.env && restic snapshots'

# Belirli tag:
sudo bash -c '. /etc/teqlif-offsite/restic.env && restic snapshots --tag daily-full'
sudo bash -c '. /etc/teqlif-offsite/restic.env && restic snapshots --tag pg_wal'
sudo bash -c '. /etc/teqlif-offsite/restic.env && restic snapshots --tag financial-worm'
```

**Mevcut snapshot özeti (2026-11-13 itibarıyla):**
- `daily-full`: `78a348dc` (2026-11-12 14:01) — pg_dump + minio + clickhouse + redis + pg_basebackup + pg_wal
- `pg_wal`: saatlik, her `:45` UTC
- Toplam: 47 snapshot, bütünlük doğrulandı (`restic check: no errors were found`)

---

## 3. Senaryo A — node2 Yeniden Kurulum (node1 Canlı)

> node2 fiziksel olarak kayboldu, node1 çalışıyor.

```bash
# 1. Yeni Debian 13 sunucuya bootstrap_node2.sh çalıştır
sudo bash /var/www/teqlif.com/deploy/scale/V2.1/scripts/bootstrap_node2.sh

# 2. .env.backup credentials'ları doldur (cluster_secrets_backup'tan veya Key Escrow)
sudo nano /project/teqlif/config/.env.backup

# 3. Restic ile backup verilerini node101'den geri yükle (isteğe bağlı):
export RESTIC_REPOSITORY="rest:http://<RESTIC_REST_USER>:<RESTIC_REST_PASSWORD>@10.10.0.101:8000/<RESTIC_REST_USER>/"
export RESTIC_PASSWORD="<restic_sifre>"
restic restore latest --tag daily-full --target /project/teqlif/backups/

# 4. Backup timerları başlat
sudo systemctl start teqlif-offsite-sync.timer teqlif-pg-dump.timer
```

---

## 4. Senaryo C — Çifte Felaket: node1 + node2 Kayıp

> En kritik senaryo. Veriler yalnız node101'de.

### 4a. node101 Üzerinde Snapshot Doğrula

```bash
ssh node101
sudo bash -c '. /etc/teqlif-offsite/restic.env && restic snapshots --tag daily-full --latest 1'
```

### 4b. İnteraktif Restore Script

```bash
# node101 üzerinde:
sudo bash /var/www/teqlif.com/deploy/scale/V2.1/node101/resources/scripts/restore_from_node101.sh
```

### 4c. Manuel DUMP Restore (Fallback)

```bash
# node101 üzerinde — pg_dump dosyasını geçici dizine çıkar
TMPDIR=$(mktemp -d /mnt/data/tmp/restore_XXXXXX)
sudo bash -c ". /etc/teqlif-offsite/restic.env && restic restore latest \
    --tag daily-full \
    --include /project/teqlif/backups/pg_dump \
    --target '${TMPDIR}'"

# Yeni node1'e transfer
NEW_NODE1="<yeni_node1_ip>"
rsync -avz "${TMPDIR}/project/teqlif/backups/pg_dump/" "${NEW_NODE1}:/project/teqlif/backups/pg_dump/"
rm -rf "${TMPDIR}"
```

### 4d. PITR Restore (pg_basebackup + WAL, RPO ~1 dk)

```bash
# node101 üzerinde — basebackup + WAL çıkar
TMPDIR=$(mktemp -d /mnt/data/tmp/pitr_XXXXXX)
sudo bash -c ". /etc/teqlif-offsite/restic.env && restic restore latest \
    --tag daily-full \
    --include /project/teqlif/backups/pg_basebackup \
    --include /project/teqlif/backups/pg_wal \
    --target '${TMPDIR}'"

# Yeni node1'de:
# 1. PostgreSQL durdur
sudo systemctl stop postgresql@17-main

# 2. PGDATA temizle + basebackup aç
sudo rm -rf /var/lib/postgresql/17/main
sudo install -d -o postgres -g postgres -m 700 /var/lib/postgresql/17/main
BASE_TAR="${TMPDIR}/project/teqlif/backups/pg_basebackup/<TARIH>/base.tar.gz"
sudo -u postgres tar -xzf "${BASE_TAR}" -C /var/lib/postgresql/17/main

# 3. WAL segmentlerini recovery_target_time'a kadar uygula
sudo -u postgres mkdir -p /var/lib/postgresql/17/main/pg_wal
WAL_TAR="${TMPDIR}/project/teqlif/backups/pg_basebackup/<TARIH>/pg_wal.tar.gz"
sudo -u postgres tar -xzf "${WAL_TAR}" -C /var/lib/postgresql/17/main/pg_wal/

# 4. restore_command ile WAL arşivini uygula
cat > /var/lib/postgresql/17/main/postgresql.auto.conf <<'EOF'
restore_command = 'cp /project/teqlif/backups/pg_wal/%f %p'
recovery_target_action = 'promote'
EOF
sudo -u postgres touch /var/lib/postgresql/17/main/recovery.signal

# 5. Başlat ve promote olmasını bekle
sudo systemctl start postgresql@17-main
sudo -u postgres psql -c "SELECT pg_is_in_recovery();"
# → f (false) = promote başarılı
```

---

## 5. Doğrulama Adımları

```bash
# Restic bütünlük kontrolü (node101):
sudo bash -c '. /etc/teqlif-offsite/restic.env && \
    export RESTIC_CACHE_DIR=/mnt/data/cache/restic && \
    restic check --read-data-subset=5%'
# Beklenen: "no errors were found"

# Snapshot tablo sayısı doğrula (restore sonrası):
psql -h 127.0.0.1 -U teqlif -d teqlif \
    -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';"
# Beklenen: tablolar mevcut (örn. >50)

# Wallet ledger varlık kontrolü:
psql -h 127.0.0.1 -U teqlif -d teqlif \
    -c "SELECT count(*) FROM wallet_ledger LIMIT 1;"
```

---

## 6. DR Tatbikat Raporu — 2026-11-13

**Tatbikat Tipi:** pg_dump + restic check  
**Tarih:** 2026-11-13 06:12 UTC  
**Çalıştıran:** `systemctl start teqlif-offsite-verify.service`

| Kontrol | Sonuç |
|---------|-------|
| `restic check --read-data-subset=5%` | ✅ `no errors were found` |
| Toplam snapshot sayısı | 47 |
| `daily-full` son snapshot | `78a348dc` (2026-11-12 14:01) |
| pg_dump restore (snapshot `78a348dc`) | ✅ Başarılı (6.474 MiB, 0:01) |
| `pg_restore --list` doğrulama | ✅ Geçti (exit 0) |
| Restic servis bellek (peak) | 46 MB |

**Sonuç:** Veriler node101'de bütünlüklü ve kurtarılabilir durumdadır.

---

## 7. Periyodik Tatbikat Takvimi

| Tatbikat | Sıklık | Metod |
|----------|--------|-------|
| `restic check --read-data-subset=5%` | Her Pazar 09:00 UTC | Otomatik (`teqlif-offsite-verify.timer`) |
| `restic check` tam | Yılda 1 | Manuel |
| pg_dump tam restore tatbikatı | 6 ayda 1 | Manuel (bu runbook) |
| PITR tatbikatı | Yılda 1 | Manuel (bu runbook §4d) |

---

## 8. İlgili Dosyalar ve Komutlar

```
deploy/scale/V2.1/node101/systemd/teqlif-offsite-prune.{service,timer}
deploy/scale/V2.1/node101/systemd/teqlif-offsite-verify.{service,timer}
deploy/scale/V2.1/node101/resources/scripts/restore_from_node101.sh
deploy/scale/V2.1/node2/resources/scripts/runbook.sh           ← node2→node1
deploy/scale/V2.1/node2/resources/scripts/offsite_sync.sh      ← restic push
```
