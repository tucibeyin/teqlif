#!/bin/bash
# Stalwart Mail Server günlük yedeği.
#
# RocksDB tutarlılığı için servis kısa süre durdurulur (~1-2 sn, 16MB veri).
# Backup: /project/teqlif/backups/stalwart/
set -euo pipefail

BACKUP_DIR=/project/teqlif/backups/stalwart
LOGFILE=/project/teqlif/logs/mail_backup.log
RETENTION_DAYS=90
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DEST="${BACKUP_DIR}/stalwart_${TIMESTAMP}.tar.gz"

install -d "${BACKUP_DIR}"
exec >> "${LOGFILE}" 2>&1
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) mail_backup: start"

# RocksDB tutarlı snapshot için servisi durdur
sudo systemctl stop stalwart-mail

tar -czf "${DEST}" \
    /project/mail/data \
    /project/mail/config/dkim \
    2>/dev/null

sudo systemctl start stalwart-mail

# Sentinel: health.py bu dosyanın mtime'ına bakar
touch "${BACKUP_DIR}/../.last_mail_backup_ok"

find "${BACKUP_DIR}" -name "stalwart_*.tar.gz" -mtime "+${RETENTION_DAYS}" -delete

SIZE=$(du -sh "${DEST}" | cut -f1)
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) mail_backup: OK (${SIZE})"
logger "teqlif mail_backup: tamamlandı (${SIZE})"
