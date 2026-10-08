#!/bin/bash
# nodeMonitor'dan Loki chunk backup'ı.
#
# Ön koşul: node2'den nodeMonitor'a SSH key-based auth:
#   ~/.ssh/config'de şu blok olmalı:
#     Host nodemonitor
#       HostName 10.10.0.99
#       User tucibeyin
#       IdentityFile ~/.ssh/nodeMonitor
#       StrictHostKeyChecking no
set -euo pipefail

BACKUP_DIR=/project/teqlif/backups/loki/chunks
RETENTION_DAYS=90
LOGFILE=/project/teqlif/logs/loki_backup.log
NODEMONITOR_CHUNKS="nodemonitor:/opt/monitor/teqlif/loki/data/chunks/"

install -d "${BACKUP_DIR}"
exec >> "${LOGFILE}" 2>&1
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) loki_backup: start"

# --ignore-existing: nodeMonitor'ın sildiği chunk'ları backup'ta koru.
# Yeni chunk'lar mevcut zaman damgasıyla kopyalanır.
rsync -az \
    --ignore-existing \
    --delete-after \
    -e "ssh -i /home/tucibeyin/.ssh/nodeMonitor -o StrictHostKeyChecking=no" \
    tucibeyin@10.10.0.99:"${NODEMONITOR_CHUNKS}" \
    "${BACKUP_DIR}/"

# Sentinel: health.py bu dosyanın mtime'ına bakar
touch "${BACKUP_DIR}/../.last_backup_ok"

# 90 günden eski chunk'ları sil
find "${BACKUP_DIR}" -type f -mtime "+${RETENTION_DAYS}" -delete
find "${BACKUP_DIR}" -type d -empty -mindepth 1 -delete

USED=$(du -sh "${BACKUP_DIR}" 2>/dev/null | cut -f1 || echo "?")
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) loki_backup: tamamlandı (${USED})"
logger "teqlif loki_backup: tamamlandı (${USED})"
