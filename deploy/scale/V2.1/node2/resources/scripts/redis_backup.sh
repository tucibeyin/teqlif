#!/bin/bash
set -euo pipefail

BACKUP_DIR=/project/teqlif/backups/redis
REDIS_HOST=10.10.0.1
RETENTION_DAYS=7
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

install -d "${BACKUP_DIR}"

redis-cli -h "${REDIS_HOST}" -p 6379 -a "${CORE_REDIS_PASS}" \
    --no-auth-warning BGSAVE 2>/dev/null
sleep 3

DEST="${BACKUP_DIR}/redis-core_${TIMESTAMP}.rdb"
rsync -az "tucibeyin@${REDIS_HOST}:/project/teqlif/data/redis/core/dump-core.rdb" \
    "${DEST}" 2>/dev/null || true

find "${BACKUP_DIR}" -name "redis-*.rdb" -mtime +${RETENTION_DAYS} -delete
logger "teqlif redis_backup: tamamlandı"
