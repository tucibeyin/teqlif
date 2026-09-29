#!/bin/bash
set -euo pipefail
BACKUP_BASE="/data/backups/minio"
LOGFILE="/var/log/teqlif/minio_backup.log"
exec >> "${LOGFILE}" 2>&1
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) minio_backup: start"

source /etc/teqlif/.env.production

mc alias set node7minio "http://10.10.0.8:9000" "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASSWORD}" --quiet
mc alias set node8minio "http://10.10.0.12:9000" "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASSWORD}" --quiet

mirror_bucket() {
  local alias="$1" bucket="$2"
  local dest="${BACKUP_BASE}/${bucket}"
  mkdir -p "${dest}"
  mc mirror --overwrite --remove --quiet "${alias}/${bucket}" "${dest}"
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) minio_backup: ${bucket} OK — $(du -sh ${dest} | cut -f1)"
}

if mc admin info node7minio --quiet &>/dev/null; then
  mirror_bucket node7minio teqlif
  mirror_bucket node7minio teqlif-dm
else
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) minio_backup: node7 erişilemiyor, node8 fallback"
  mirror_bucket node8minio teqlif
  mirror_bucket node8minio teqlif-dm
fi

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) minio_backup: tamamlandı"
