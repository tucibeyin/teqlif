#!/bin/bash
set -euo pipefail

BACKUP_DIR=/project/teqlif/backups/pg_dump
PGHOST=10.10.0.1
PGPORT=5432
PGUSER=teqlif
PGDATABASE=teqlif
RETENTION_DAYS=7
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DEST="${BACKUP_DIR}/teqlif_${TIMESTAMP}.dump"

install -d "${BACKUP_DIR}"

# .tmp'ye yaz — başarısız dump kırık dosya olarak kalmasın
DEST_TMP="${DEST}.tmp"
PGPASSWORD="${TEQLIF_DB_PASSWORD}" pg_dump \
    -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" \
    -Fc "${PGDATABASE}" > "${DEST_TMP}"

# Bütünlük doğrulaması — içerik listesi çıkarılamazsa dump bozuk
pg_restore --list "${DEST_TMP}" > /dev/null

mv "${DEST_TMP}" "${DEST}"

find "${BACKUP_DIR}" -name "teqlif_*.dump" -mtime +${RETENTION_DAYS} -delete
logger "teqlif pg_dump: ${DEST} ($(du -sh ${DEST} | cut -f1))"
redis-cli -h 10.10.0.1 -p 6379 -a "${CORE_REDIS_PASS}" --no-auth-warning HSET teqlif:agent:job_ok pg_dump "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >/dev/null 2>&1 || true
