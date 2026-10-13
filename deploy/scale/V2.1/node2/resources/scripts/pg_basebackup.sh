#!/bin/bash
# pg_basebackup — node1 PostgreSQL fiziksel yedeği (haftalık, Pazar 02:00 UTC)
#
# pg_receivewal WAL segmentleriyle birlikte PITR (Point-In-Time Recovery) sağlar.
# Yedek bu dizine çıkar: /project/teqlif/backups/pg_basebackup/<timestamp>/
# Son 2 yedek saklanır (2 haftalık güvenlik penceresi).
#
# Kurtarma: runbook.sh —bu scriptle alınan yedeği kullanır.
set -euo pipefail

source /project/teqlif/config/.env.backup

BACKUP_DIR=/project/teqlif/backups/pg_basebackup
PGHOST=10.10.0.1
PGPORT=5432
PGUSER=teqlif_repl
RETENTION_COUNT=2
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DEST="${BACKUP_DIR}/${TIMESTAMP}"
LOGFILE=/project/teqlif/logs/pg_basebackup.log

install -d "${BACKUP_DIR}"
exec >> "${LOGFILE}" 2>&1

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) pg_basebackup: başlıyor → ${DEST}"

PGPASSWORD="${REPL_PASSWORD}" pg_basebackup \
    -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" \
    --checkpoint=fast \
    --wal-method=stream \
    --format=tar \
    --gzip \
    --compress=1 \
    -D "${DEST}"

SIZE=$(du -sh "${DEST}" | cut -f1)
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) pg_basebackup: tamamlandı (${SIZE}) → ${DEST}"
logger "teqlif pg_basebackup: tamamlandı (${SIZE})"

# Eski yedekleri temizle — en son RETENTION_COUNT adedini sakla
mapfile -t OLD < <(ls -1dt "${BACKUP_DIR}"/[0-9]* 2>/dev/null | tail -n +$((RETENTION_COUNT + 1)))
for OLD_DIR in "${OLD[@]}"; do
    rm -rf "${OLD_DIR}"
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) pg_basebackup: eski yedek silindi → ${OLD_DIR}"
done

redis-cli -h 10.10.0.1 -p 6379 -a "${CORE_REDIS_PASS}" --no-auth-warning HSET teqlif:agent:job_ok pg_basebackup "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >/dev/null 2>&1 || true
