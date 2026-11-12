#!/bin/bash
# offsite_wal_sync.sh — teqlif WAL backup → node101 (restic, saatlik *:45)
# pg_receivewal /project/teqlif/backups/pg_wal/'a sürekli yazar;
# bu script saatte bir mevcut WAL dosyalarını restic ile node101'e gönderir.

set -euo pipefail

source /project/teqlif/config/.env.backup

LOGFILE=/project/teqlif/logs/offsite_wal_sync.log
install -d "$(dirname "${LOGFILE}")"
exec >> "${LOGFILE}" 2>&1

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) offsite_wal_sync: start"

if [[ -z "${RESTIC_REST_USER:-}" ]] || [[ -z "${RESTIC_REST_PASSWORD:-}" ]] || [[ -z "${RESTIC_PASSWORD:-}" ]]; then
    if [[ "${OFFSITE_MODE:-}" == "disabled" ]]; then
        echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) offsite_wal_sync: SKIP — OFFSITE_MODE=disabled"
        exit 0
    fi
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) offsite_wal_sync: FAIL — credentials tanımlı değil"
    exit 2
fi

export RESTIC_REPOSITORY="rest:http://${RESTIC_REST_USER}:${RESTIC_REST_PASSWORD}@10.10.0.101:8000/${RESTIC_REST_USER}/"
export RESTIC_PASSWORD
export RESTIC_CACHE_DIR=/project/teqlif/backups/.restic-cache
export TMPDIR=/project/teqlif/backups/.restic-tmp
mkdir -p "${RESTIC_CACHE_DIR}" "${TMPDIR}"

restic backup \
    /project/teqlif/backups/pg_wal \
    --tag pg_wal \
    --pack-size 32 \
    --compression max \
    --exclude '*.partial' \
    --exclude '*.tmp' \
    --exclude '.last_*'

redis-cli -h 10.10.0.1 -p 6379 -a "${CORE_REDIS_PASS:-}" --no-auth-warning \
    HSET teqlif:agent:job_ok offsite_wal_sync "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >/dev/null 2>&1 || true

touch /project/teqlif/backups/.last_offsite_wal_ok
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) offsite_wal_sync: OK"
