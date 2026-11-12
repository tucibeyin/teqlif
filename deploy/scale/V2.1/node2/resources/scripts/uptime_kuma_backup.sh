#!/bin/bash
# nodeMonitor Uptime Kuma (MariaDB) günlük yedeği.
#
# Gerekli: .env.backup içinde UPTIME_KUMA_DB_PASS tanımlı olmalı.
# DB: MariaDB (127.0.0.1:3306) — user: uptime_kuma, db: uptime_kuma
set -euo pipefail

source /project/teqlif/config/.env.backup

BACKUP_DIR=/project/teqlif/backups/uptime_kuma
RETENTION_DAYS=180
LOGFILE=/project/teqlif/logs/uptime_kuma_backup.log
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DEST="${BACKUP_DIR}/uptime_kuma_${TIMESTAMP}.sql.gz"

install -d "${BACKUP_DIR}"
exec >> "${LOGFILE}" 2>&1
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) uptime_kuma_backup: start"

if [[ -z "${UPTIME_KUMA_DB_PASS:-}" ]]; then
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) uptime_kuma_backup: HATA — UPTIME_KUMA_DB_PASS tanımlı değil"
    exit 1
fi

DEST_TMP="${DEST}.tmp"

# Küçük/bozuk yetim arşivleri temizle (ör: 13 Eki 20B)
find "${BACKUP_DIR}" -name 'uptime_kuma_*.sql.gz' -size -100c -delete 2>/dev/null || true

# Şifreyi stdin üzerinden geçir — komut satırında görünmez, ps aux'da çıkmaz
printf '[client]\npassword=%s\n' "${UPTIME_KUMA_DB_PASS}" | \
    ssh -i /home/tucibeyin/.ssh/id_ed25519 \
        -o StrictHostKeyChecking=no \
        tucibeyin@10.10.0.99 \
        "f=\$(mktemp -t .myXXXXXX.cnf); chmod 600 \"\$f\"; cat > \"\$f\"; \
         mysqldump --defaults-extra-file=\"\$f\" -h 127.0.0.1 -u uptime_kuma --single-transaction uptime_kuma; \
         rc=\$?; rm -f \"\$f\"; exit \$rc" \
    | gzip > "${DEST_TMP}"

# Bütünlük doğrulaması — bozuk arşiv sentinel yazılmadan önce tespit edilir
gzip -t "${DEST_TMP}"
mv "${DEST_TMP}" "${DEST}"

find "${BACKUP_DIR}" -name "uptime_kuma_*.sql.gz" -mtime "+${RETENTION_DAYS}" -delete

SIZE=$(du -sh "${DEST}" | cut -f1)
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) uptime_kuma_backup: OK (${SIZE})"
touch "${BACKUP_DIR}/.last_backup_ok"
logger "teqlif uptime_kuma_backup: tamamlandı (${SIZE})"
redis-cli -h 10.10.0.1 -p 6379 -a "${CORE_REDIS_PASS}" --no-auth-warning HSET teqlif:agent:job_ok uptime_kuma_backup "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >/dev/null 2>&1 || true
