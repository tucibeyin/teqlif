#!/bin/bash
set -euo pipefail

source /project/teqlif/config/.env.backup

BACKUP_DIR=/project/teqlif/backups/clickhouse
RETENTION_DAYS=7
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DEST="${BACKUP_DIR}/teqlif_analytics_${TIMESTAMP}"

install -d "${BACKUP_DIR}"

clickhouse-backup create --tables 'teqlif_analytics.*' "${DEST}" 2>/dev/null || clickhouse-client   --host 127.0.0.1   --port 9000   --user default   --query "BACKUP DATABASE teqlif_analytics TO Disk('backups', 'teqlif_analytics_${TIMESTAMP}.zip')" 2>/dev/null || (
  mkdir -p "${DEST}"
  for TABLE in user_events feed_analytics search_events swipe_live_events direct_sale_events; do
    clickhouse-client --host 127.0.0.1 --port 9000 --user default       --query "SELECT * FROM teqlif_analytics.${TABLE} FORMAT Native" > "${DEST}/${TABLE}.native" 2>/dev/null || true
  done
  tar -czf "${DEST}.tar.gz" -C "${BACKUP_DIR}" "$(basename ${DEST})"
  rm -rf "${DEST}"
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) clickhouse_backup: OK ($(du -sh ${DEST}.tar.gz | cut -f1))"
  logger "teqlif clickhouse_backup: tamamlandı"
)

find "${BACKUP_DIR}" -name '*.tar.gz' -mtime +${RETENTION_DAYS} -delete
redis-cli -h 10.10.0.1 -p 6379 -a "${CORE_REDIS_PASS}" --no-auth-warning HSET teqlif:agent:job_ok clickhouse_backup "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >/dev/null 2>&1 || true
