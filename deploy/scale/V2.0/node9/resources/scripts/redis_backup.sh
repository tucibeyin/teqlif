#!/bin/bash
set -euo pipefail

BACKUP_DIR=/data/backups/redis
REDIS_HOST=10.10.0.11
REDIS_PORT=6379
REDIS_PASS=<core_redis_pass>
RETENTION_DAYS=7
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DEST="${BACKUP_DIR}/redis-core_${TIMESTAMP}.rdb"

install -d "${BACKUP_DIR}"

redis-cli \
    -h "${REDIS_HOST}" \
    -p "${REDIS_PORT}" \
    -a "${REDIS_PASS}" \
    --no-auth-warning \
    --rdb "${DEST}"

find "${BACKUP_DIR}" -name "redis-core_*.rdb" -mtime +${RETENTION_DAYS} -delete

logger "redis_backup: completed to ${DEST}"
