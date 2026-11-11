#!/bin/bash
# restic_verify.sh — teqlif offsite repo bütünlük kontrolü (node101 yerel)
# systemd teqlif-offsite-verify.service tarafından çağrılır.
# Manuel test: sudo -u teqlif-backup bash restic_verify.sh

set -euo pipefail

LOGFILE=/var/log/teqlif-offsite/verify.log
install -d "$(dirname "${LOGFILE}")"
exec >> "${LOGFILE}" 2>&1

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) verify: start"

# %5 veri örneklemesi — 1 TiB repoda ~50 GiB okur (~5–8 dakika)
restic check --read-data-subset=5%

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) verify: OK"
