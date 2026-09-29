#!/bin/bash
set -euo pipefail

BACKUP_DIR=/data/clickhouse-backups
RETENTION_DAYS=7
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="teqlif_${TIMESTAMP}"

clickhouse-client \
    --host 127.0.0.1 \
    --user "${CLICKHOUSE_USER}" \
    --password "${CLICKHOUSE_PASSWORD}" \
    --query "BACKUP DATABASE teqlif TO Disk('backup_disk', '${BACKUP_NAME}')"

# Poll until backup completes
for i in $(seq 1 60); do
    STATUS=$(clickhouse-client \
        --host 127.0.0.1 \
        --user "${CLICKHOUSE_USER}" \
        --password "${CLICKHOUSE_PASSWORD}" \
        --query "SELECT status FROM system.backups WHERE name='${BACKUP_NAME}' ORDER BY start_time DESC LIMIT 1" \
        2>/dev/null || echo "UNKNOWN")
    if [ "$STATUS" = "BACKUP_CREATED" ]; then
        break
    fi
    if [ "$STATUS" = "FAILED" ]; then
        logger "clickhouse_backup: FAILED for ${BACKUP_NAME}"
        exit 1
    fi
    sleep 5
done

find "${BACKUP_DIR}" -maxdepth 1 -name "teqlif_*" -mtime +${RETENTION_DAYS} -exec rm -rf {} +

logger "clickhouse_backup: completed ${BACKUP_NAME}"
