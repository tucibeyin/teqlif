#!/bin/bash
# pg_wal_cleanup — /project/teqlif/backups/pg_wal/ içindeki 7 günden eski WAL
# segmentlerini siler. Günlük 05:30 UTC'de çalışır.
set -euo pipefail

WAL_DIR=/project/teqlif/backups/pg_wal
RETENTION_DAYS=7
LOGFILE=/project/teqlif/logs/pg_wal_cleanup.log

exec >> "${LOGFILE}" 2>&1

if [ ! -d "${WAL_DIR}" ]; then
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) pg_wal_cleanup: ${WAL_DIR} yok, atlanıyor"
    exit 0
fi

deleted=$(find "${WAL_DIR}" -maxdepth 1 -type f -mtime +${RETENTION_DAYS} -print -delete | wc -l)
total=$(find "${WAL_DIR}" -maxdepth 1 -type f | wc -l)
size=$(du -sh "${WAL_DIR}" 2>/dev/null | cut -f1)

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) pg_wal_cleanup: ${deleted} segment silindi, kalan ${total} segment (${size})"
logger "teqlif pg_wal_cleanup: ${deleted} silindi, kalan ${total} (${size})"
