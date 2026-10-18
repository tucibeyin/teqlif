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

ssh -i /home/tucibeyin/.ssh/id_ed25519 \
    -o StrictHostKeyChecking=no \
    tucibeyin@10.10.0.99 \
    "MYSQL_PWD='${UPTIME_KUMA_DB_PASS}' mysqldump -h 127.0.0.1 -u uptime_kuma uptime_kuma" \
    | gzip > "${DEST}"

find "${BACKUP_DIR}" -name "uptime_kuma_*.sql.gz" -mtime "+${RETENTION_DAYS}" -delete

SIZE=$(du -sh "${DEST}" | cut -f1)
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) uptime_kuma_backup: OK (${SIZE})"
touch "${BACKUP_DIR}/.last_backup_ok"
logger "teqlif uptime_kuma_backup: tamamlandı (${SIZE})"
