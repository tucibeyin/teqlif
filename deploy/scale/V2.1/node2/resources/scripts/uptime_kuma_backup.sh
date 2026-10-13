#!/bin/bash
# nodeMonitor'dan Uptime Kuma SQLite backup'ı.
#
# Uptime Kuma SQLite kullanır (/opt/monitor/shared/uptime-kuma/db/kuma.db).
# sqlite3 .backup komutu live DB'yi consistent biçimde alır (WAL-safe).
set -euo pipefail

BACKUP_DIR=/project/teqlif/backups/uptime_kuma
RETENTION_DAYS=180
LOGFILE=/project/teqlif/logs/uptime_kuma_backup.log
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DEST="${BACKUP_DIR}/uptime_kuma_${TIMESTAMP}.db.gz"
TMP_REMOTE="/tmp/teqlif_kuma_${TIMESTAMP}.db"
KUMA_DB="/opt/monitor/shared/uptime-kuma/db/kuma.db"

install -d "${BACKUP_DIR}"
exec >> "${LOGFILE}" 2>&1
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) uptime_kuma_backup: start"

SSH="ssh -i /home/tucibeyin/.ssh/id_ed25519 -o StrictHostKeyChecking=no tucibeyin@10.10.0.99"

# sqlite3 .backup → nodeMonitor /tmp'ye consistent snapshot al
${SSH} "sqlite3 '${KUMA_DB}' '.backup ${TMP_REMOTE}'"

# node2'ye rsync
rsync -az \
    -e "ssh -i /home/tucibeyin/.ssh/id_ed25519 -o StrictHostKeyChecking=no" \
    tucibeyin@10.10.0.99:"${TMP_REMOTE}" \
    "${DEST%.gz}"

# nodeMonitor /tmp temizle
${SSH} "rm -f '${TMP_REMOTE}'"

gzip "${DEST%.gz}"

find "${BACKUP_DIR}" -name "uptime_kuma_*.db.gz" -mtime "+${RETENTION_DAYS}" -delete

SIZE=$(du -sh "${DEST}" | cut -f1)
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) uptime_kuma_backup: OK (${SIZE})"
logger "teqlif uptime_kuma_backup: tamamlandı (${SIZE})"
