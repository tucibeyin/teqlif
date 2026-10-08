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
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) minio_backup: ${bucket} OK ($(du -sh "${dest}" | cut -f1))"
}

mirror_bucket teqlif
mirror_bucket teqlif-dm

# teqlif bucket mirror başarılı → node1 MinIO'daki tüm nesneler node2'de mevcut.
# Henüz onaylanmamış stream_recordings kayıtlarını damgala.
# PG güncellemesi başarısız olsa da MinIO yedek tamam — sadece WARN logla.
confirm_recordings() {
    local updated
    updated=$(PGPASSWORD="${TEQLIF_DB_PASSWORD}" psql \
        -h 10.10.0.1 -p 5432 -U teqlif teqlif \
        --no-align --tuples-only -q \
        -c "WITH upd AS (
                UPDATE stream_recordings
                SET node2_confirmed_at = NOW(), updated_at = NOW()
                WHERE node2_confirmed_at IS NULL
                  AND minio_key IS NOT NULL
                  AND transferred_at IS NOT NULL
                  AND status IN ('available','expired')
                RETURNING 1
            ) SELECT COUNT(*) FROM upd" 2>&1) || { \
        echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) minio_backup: WARNING node2_confirmed_at güncellenemedi: ${updated}"; \
        return 0; \
    }
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) minio_backup: node2_confirmed_at set: ${updated} kayıt"
}

confirm_recordings

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) minio_backup: tamamlandı"
logger "teqlif minio_backup: tamamlandı"
