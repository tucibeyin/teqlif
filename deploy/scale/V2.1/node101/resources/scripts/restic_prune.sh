#!/bin/bash
# restic_prune.sh — teqlif offsite repo prune (node101 yerel)
# systemd teqlif-offsite-prune.service tarafından çağrılır.
# Manuel test: sudo -u teqlif-backup bash restic_prune.sh

set -euo pipefail

LOGFILE=/var/log/teqlif-offsite/prune.log
install -d "$(dirname "${LOGFILE}")"
exec >> "${LOGFILE}" 2>&1

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) prune: start"

restic forget \
    --tag daily-full \
    --keep-daily   7 \
    --keep-weekly  4 \
    --keep-monthly 6 \
    --prune

restic forget \
    --tag pg_wal \
    --keep-within 7d \
    --prune

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) prune: OK"
