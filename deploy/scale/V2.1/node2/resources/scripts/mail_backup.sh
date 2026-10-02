#!/bin/bash
# Stalwart Mail Server günlük yedeği
# Veri: /project/teqlif/data/mail/ (RocksDB + blobs)
# DKIM anahtarları: /project/teqlif/config/stalwart/dkim/
set -euo pipefail

BACKUP_DIR=/project/teqlif/backups/mail
LOGFILE=/project/teqlif/logs/mail_backup.log
RETENTION_DAYS=7
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DEST="${BACKUP_DIR}/mail_${TIMESTAMP}.tar.gz"

install -d "${BACKUP_DIR}"
exec >> "${LOGFILE}" 2>&1
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) mail_backup: start"

# Stalwart veri dizini + DKIM anahtarları
tar -czf "${DEST}" \
    /project/teqlif/data/mail \
    /project/teqlif/config/stalwart/dkim \
    2>/dev/null

find "${BACKUP_DIR}" -name "mail_*.tar.gz" -mtime "+${RETENTION_DAYS}" -delete

SIZE=$(du -sh "${DEST}" | cut -f1)
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) mail_backup: OK (${SIZE})"
logger "teqlif mail_backup: ${DEST} (${SIZE})"
