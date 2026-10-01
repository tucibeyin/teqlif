#!/bin/bash
set -euo pipefail

BACKUP_DIR=/project/teqlif/backups/pg_dump
PGHOST=10.10.0.1
PGPORT=5432
PGUSER=teqlif
PGDATABASE=teqlif
RETENTION_DAYS=7
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DEST="${BACKUP_DIR}/teqlif_${TIMESTAMP}.dump.gz"

install -d "${BACKUP_DIR}"
PGPASSWORD="${TEQLIF_DB_PASSWORD}" pg_dump \
    -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" \
    -Fc "${PGDATABASE}" | gzip -9 > "${DEST}"

find "${BACKUP_DIR}" -name "teqlif_*.dump.gz" -mtime +${RETENTION_DAYS} -delete
logger "teqlif pg_dump: ${DEST} ($(du -sh ${DEST} | cut -f1))"
