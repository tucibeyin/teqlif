#!/bin/bash
# Stalwart Mail Server günlük yedeği
# Veri:  /project/mail/data/  (RocksDB + blobs)
# DKIM:  /project/mail/config/dkim/
# Log:   /project/mail/logs/mail_backup.log
set -euo pipefail

BACKUP_DIR=/project/mail/backups
LOGFILE=/project/mail/logs/mail_backup.log
RETENTION_DAYS=7
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DEST="${BACKUP_DIR}/mail_${TIMESTAMP}.tar.gz"

install -d "${BACKUP_DIR}"
install -d "$(dirname "${LOGFILE}")"
exec >> "${LOGFILE}" 2>&1
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) mail_backup: start"

tar -czf "${DEST}" \
    /project/mail/data \
    /project/mail/config/dkim \
    2>/dev/null

find "${BACKUP_DIR}" -name "mail_*.tar.gz" -mtime "+${RETENTION_DAYS}" -delete

SIZE=$(du -sh "${DEST}" | cut -f1)
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) mail_backup: OK (${SIZE})"
logger "mail_backup: ${DEST} (${SIZE})"
