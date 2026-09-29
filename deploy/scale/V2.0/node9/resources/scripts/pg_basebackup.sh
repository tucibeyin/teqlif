#!/bin/bash
set -euo pipefail

BACKUP_DIR=/data/backups/pg_basebackup
PGHOST=10.10.0.10
PGPORT=5432
PGUSER=replicator
RETENTION_DAYS=7
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DEST="${BACKUP_DIR}/basebackup_${TIMESTAMP}"
DEST_TMP="${DEST}.tmp"

install -d "${BACKUP_DIR}"

pg_basebackup \
    -h "${PGHOST}" \
    -p "${PGPORT}" \
    -U "${PGUSER}" \
    -D "${DEST_TMP}" \
    -Ft \
    -z \
    --compress=9 \
    -P \
    -Xs \
    --checkpoint=fast

mv "${DEST_TMP}" "${DEST}"

if [ -d "${BACKUP_DIR}/previous_basebackup" ]; then
    rm -rf "${BACKUP_DIR}/previous_basebackup"
fi
if ls "${BACKUP_DIR}"/basebackup_* 2>/dev/null | grep -v "${DEST}" | head -1 | read PREV; then
    mv "${PREV}" "${BACKUP_DIR}/previous_basebackup" 2>/dev/null || true
fi

find "${BACKUP_DIR}" -maxdepth 1 -name "previous_basebackup_*" -mtime +${RETENTION_DAYS} -exec rm -rf {} +

logger "pg_basebackup: completed to ${DEST}"
