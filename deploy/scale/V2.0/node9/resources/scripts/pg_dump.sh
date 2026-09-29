#!/bin/bash
set -euo pipefail

BACKUP_DIR=/data/backups/pg_dump
PGHOST=10.10.0.10
PGPORT=5432
PGUSER=teqlif
PGDATABASE=teqlif
RETENTION_DAYS=7
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DEST="${BACKUP_DIR}/teqlif_${TIMESTAMP}.dump.gz"

install -d "${BACKUP_DIR}"

pg_dump \
    -h "${PGHOST}" \
    -p "${PGPORT}" \
    -U "${PGUSER}" \
    -Fc \
    "${PGDATABASE}" | gzip -9 > "${DEST}"

find "${BACKUP_DIR}" -name "teqlif_*.dump.gz" -mtime +${RETENTION_DAYS} -delete

logger "pg_dump: completed to ${DEST}"
