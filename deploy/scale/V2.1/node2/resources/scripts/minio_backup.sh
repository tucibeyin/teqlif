#!/bin/bash
set -euo pipefail

source /project/teqlif/config/.env.backup

BACKUP_DIR=/project/teqlif/backups/minio
LOGFILE=/project/teqlif/logs/minio_backup.log
MINIO_URL=http://10.10.0.1:9000

install -d "${BACKUP_DIR}"
exec >> "${LOGFILE}" 2>&1
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) minio_backup: start"

mc alias set node1minio "${MINIO_URL}" "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASSWORD}" --quiet

mirror_bucket() {
    local bucket="$1"
    local dest="${BACKUP_DIR}/${bucket}"
    install -d "${dest}"
    mc mirror --overwrite --quiet "node1minio/${bucket}" "${dest}"
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) minio_backup: ${bucket} OK ($(du -sh ${dest} | cut -f1))"
}

mirror_bucket teqlif
mirror_bucket teqlif-dm
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) minio_backup: tamamlandı"
logger "teqlif minio_backup: tamamlandı"
