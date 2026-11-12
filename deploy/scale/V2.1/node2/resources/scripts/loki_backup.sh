#!/bin/bash
# nodeMonitor'dan Loki backup'ı.
#
# Kapsam:
#   chunks/    — Loki log chunk'ları (90 günlük, --ignore-existing: silinmişler korunur)
#   compactor/ — TSDB compactor meta (küçük, tam mirror, indeks bütünlüğü için)
#   rules/     — Loki alert kuralları
#
# Ön koşul: node2'den nodeMonitor'a SSH key-based auth:
#   ~/.ssh/config'de şu blok olmalı:
#     Host nodemonitor
#       HostName 10.10.0.99
#       User tucibeyin
#       IdentityFile ~/.ssh/nodeMonitor
#       StrictHostKeyChecking no
set -euo pipefail

source /project/teqlif/config/.env.backup

LOKI_BACKUP_BASE=/project/teqlif/backups/loki
CHUNKS_DIR="${LOKI_BACKUP_BASE}/chunks"
META_DIR="${LOKI_BACKUP_BASE}/meta"
RETENTION_DAYS=90
LOGFILE=/project/teqlif/logs/loki_backup.log
SSH_OPTS="-e ssh -i /home/tucibeyin/.ssh/id_ed25519 -o StrictHostKeyChecking=no"
NODEMONITOR="tucibeyin@10.10.0.99"

install -d "${CHUNKS_DIR}" "${META_DIR}"
exec >> "${LOGFILE}" 2>&1
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) loki_backup: start"

# -- 1. Chunk'lar: --ignore-existing (nodeMonitor'ın sildiği chunk'lar backup'ta korunur)
rsync -az \
    --ignore-existing \
    -e "ssh -i /home/tucibeyin/.ssh/id_ed25519 -o StrictHostKeyChecking=no" \
    "${NODEMONITOR}:/opt/monitor/teqlif/loki/data/chunks/" \
    "${CHUNKS_DIR}/"

# -- 2. Compactor meta + rules: tam mirror (--delete), değişkenler küçük
rsync -az \
    --delete \
    --delete-excluded \
    -e "ssh -i /home/tucibeyin/.ssh/id_ed25519 -o StrictHostKeyChecking=no" \
    "${NODEMONITOR}:/opt/monitor/teqlif/loki/data/compactor/" \
    "${META_DIR}/compactor/"

rsync -az \
    --delete \
    --delete-excluded \
    -e "ssh -i /home/tucibeyin/.ssh/id_ed25519 -o StrictHostKeyChecking=no" \
    "${NODEMONITOR}:/opt/monitor/teqlif/loki/data/rules/" \
    "${META_DIR}/rules/"

# Sentinel: health.py bu dosyanın mtime'ına bakar
touch "${LOKI_BACKUP_BASE}/.last_backup_ok"

# 90 günden eski chunk'ları sil (meta dizini retention'a tabi değil — küçük ve kalıcı)
find "${CHUNKS_DIR}" -type f -mtime "+${RETENTION_DAYS}" -delete
find "${CHUNKS_DIR}" -type d -empty -mindepth 1 -delete

CHUNKS_USED=$(du -sh "${CHUNKS_DIR}" 2>/dev/null | cut -f1 || echo "?")
META_USED=$(du -sh "${META_DIR}" 2>/dev/null | cut -f1 || echo "?")
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) loki_backup: tamamlandı (chunks=${CHUNKS_USED} meta=${META_USED})"
logger "teqlif loki_backup: tamamlandı (chunks=${CHUNKS_USED} meta=${META_USED})"
redis-cli -h 10.10.0.1 -p 6379 -a "${CORE_REDIS_PASS}" --no-auth-warning HSET teqlif:agent:job_ok loki_backup "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >/dev/null 2>&1 || true
