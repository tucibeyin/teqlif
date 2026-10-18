#!/bin/bash
# teqlif — Off-site Yedek Senkronizasyonu (node2 → Uzak Depolama)
#
# DURUM: devre dışı (teqlif-offsite-sync.timer disabled)
#
# Aktif etmek için:
#   1. /project/teqlif/config/.env.backup dosyasına aşağıdaki değerleri ekle:
#        RCLONE_REMOTE=<rclone remote adı, örn. "b2" veya "hetzner">
#        RCLONE_BUCKET=<hedef bucket/yol>
#   2. node2'de rclone konfigürasyonu oluştur:
#        rclone config  (interaktif kurulum)
#        veya doğrudan: /home/tucibeyin/.config/rclone/rclone.conf
#   3. Bu dosyanın "SKIP" bloğunu kaldır, asıl sync bloğunu aktive et.
#   4. systemctl enable --now teqlif-offsite-sync.timer
#
# Önerilen hedefler:
#   - Hetzner Storage Box (rclone sftp/s3compat)
#   - Backblaze B2 (rclone b2) — Lifecycle ile otomatik eski versiyon temizliği
#   - AWS S3 Glacier Instant Retrieval — büyük hacimler için
#
# Şifreleme: rclone'un "crypt" remote'u ile şifreli transfer önerilir.
#   rclone config → "New remote" → "crypt" → kaynak olarak gerçek hedefi seç.
#   Bu sayede bulut sağlayıcı şifresiz veriye erişemez.
#
# Hedef dizin yapısı (örnek):
#   <BUCKET>/teqlif/backups/pg_dump/
#   <BUCKET>/teqlif/backups/minio/
#   <BUCKET>/teqlif/backups/clickhouse/
#   <BUCKET>/teqlif/backups/redis/
#   <BUCKET>/teqlif/backups/loki/
#   <BUCKET>/teqlif/backups/stalwart/
#
set -euo pipefail

source /project/teqlif/config/.env.backup

LOCAL_BASE=/project/teqlif/backups
LOGFILE=/project/teqlif/logs/offsite_sync.log

install -d "$(dirname "${LOGFILE}")"
exec >> "${LOGFILE}" 2>&1
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) offsite_sync: start"

# ── Hedef yapılandırılmamışsa çık ────────────────────────────────────────────
if [[ -z "${RCLONE_REMOTE:-}" ]] || [[ -z "${RCLONE_BUCKET:-}" ]]; then
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) offsite_sync: SKIP — RCLONE_REMOTE/RCLONE_BUCKET tanımlı değil"
    logger "teqlif offsite_sync: hedef yapılandırılmamış, atlanıyor"
    exit 0
fi

# ── Asıl sync (hedef yapılandırıldığında aktif olacak) ───────────────────────
DEST="${RCLONE_REMOTE}:${RCLONE_BUCKET}/teqlif/backups"

sync_dir() {
    local src="$1"
    local label="$2"
    if [[ ! -d "${src}" ]]; then
        echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) offsite_sync: ${label} dizini yok, atlanıyor"
        return 0
    fi
    rclone sync "${src}" "${DEST}/$(basename "${src}")" \
        --transfers 4 \
        --checkers 8 \
        --retries 3 \
        --low-level-retries 5 \
        --stats-log-level NOTICE \
        --log-level ERROR \
        2>&1
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) offsite_sync: ${label} OK"
}

sync_dir "${LOCAL_BASE}/pg_dump"             "pg_dump"
sync_dir "${LOCAL_BASE}/minio"               "minio"
sync_dir "${LOCAL_BASE}/clickhouse"          "clickhouse"
sync_dir "${LOCAL_BASE}/redis"               "redis"
sync_dir "${LOCAL_BASE}/loki"                "loki"
sync_dir "${LOCAL_BASE}/stalwart"            "stalwart"
sync_dir "${LOCAL_BASE}/uptime_kuma"         "uptime_kuma"
sync_dir "${LOCAL_BASE}/nodemonitor_config"  "nodemonitor_config"

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) offsite_sync: tamamlandı"
logger "teqlif offsite_sync: tamamlandı"
redis-cli -h 10.10.0.1 -p 6379 -a "${CORE_REDIS_PASS}" --no-auth-warning \
    HSET teqlif:agent:job_ok offsite_sync "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >/dev/null 2>&1 || true
