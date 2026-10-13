#!/bin/bash
# nodeMonitor'dan Uptime Kuma MariaDB backup'ı.
#
# Ön koşul — nodeMonitor'da bir kez çalıştır:
#   cat > /home/tucibeyin/.my-backup.cnf <<'EOF'
#   [mysqldump]
#   host=127.0.0.1
#   user=root
#   password=<mysql_root_password>
#   EOF
#   chmod 600 /home/tucibeyin/.my-backup.cnf
set -euo pipefail

BACKUP_DIR=/project/teqlif/backups/uptime_kuma
RETENTION_DAYS=180
LOGFILE=/project/teqlif/logs/uptime_kuma_backup.log
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DEST="${BACKUP_DIR}/uptime_kuma_${TIMESTAMP}.sql.gz"

install -d "${BACKUP_DIR}"
exec >> "${LOGFILE}" 2>&1
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) uptime_kuma_backup: start"

ssh -i /home/tucibeyin/.ssh/id_ed25519 \
    -o StrictHostKeyChecking=no \
    tucibeyin@10.10.0.99 \
    "mysqldump --defaults-file=/home/tucibeyin/.my-backup.cnf uptime_kuma 2>/dev/null" \
    | gzip > "${DEST}"

find "${BACKUP_DIR}" -name "uptime_kuma_*.sql.gz" -mtime "+${RETENTION_DAYS}" -delete

SIZE=$(du -sh "${DEST}" | cut -f1)
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) uptime_kuma_backup: OK (${SIZE})"
logger "teqlif uptime_kuma_backup: tamamlandı (${SIZE})"
