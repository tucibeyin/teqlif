#!/bin/bash
set -euo pipefail

source /project/teqlif/config/.env.backup

BACKUP_DIR=/project/teqlif/backups/redis
RETENTION_DAYS=7
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

install -d "${BACKUP_DIR}"

# Local replica'ya BGSAVE — node1'e SSH gerekmez
redis-cli -h 127.0.0.1 -p 6379 -a "${CORE_REDIS_PASS}" --no-auth-warning BGSAVE

# BGSAVE tamamlanana kadar bekle: polling, maks 60 saniye
for _i in $(seq 1 12); do
    _in_prog=$(redis-cli -h 127.0.0.1 -p 6379 -a "${CORE_REDIS_PASS}" --no-auth-warning \
        INFO persistence 2>/dev/null | grep rdb_bgsave_in_progress | tr -d '[:space:]' | cut -d: -f2)
    [[ "${_in_prog}" == "0" ]] && break
    sleep 5
done

# Replica RDB dosyasını kopyala
RDB_SRC=$(redis-cli -h 127.0.0.1 -p 6379 -a "${CORE_REDIS_PASS}" --no-auth-warning CONFIG GET dir | tail -1)
RDB_FILE=$(redis-cli -h 127.0.0.1 -p 6379 -a "${CORE_REDIS_PASS}" --no-auth-warning CONFIG GET dbfilename | tail -1)
DEST="${BACKUP_DIR}/redis-replica_${TIMESTAMP}.rdb"

cp "${RDB_SRC}/${RDB_FILE}" "${DEST}"
gzip "${DEST}"

find "${BACKUP_DIR}" -name 'redis-*.rdb.gz' -mtime +${RETENTION_DAYS} -delete
logger "teqlif redis_backup: $(du -sh ${DEST}.gz | cut -f1) — tamamlandı"
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) redis_backup: OK ($(du -sh ${DEST}.gz | cut -f1))"
redis-cli -h 10.10.0.1 -p 6379 -a "${CORE_REDIS_PASS}" --no-auth-warning HSET teqlif:agent:job_ok redis_backup "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >/dev/null 2>&1 || true
