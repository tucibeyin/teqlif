#!/bin/bash
set -euo pipefail

# Ofsite yedek hedefi henüz yapılandırılmamış.
# teqlif-offsite-sync.timer devre dışı (disabled) — bu script çalışmıyor.
# Hedef belirlendiğinde buraya rclone/rsync komutu eklenecek.

LOCAL_BASE=/project/teqlif/backups

logger "teqlif offsite_sync: ofsite hedef yapılandırılmamış, atlanıyor"
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) offsite_sync: SKIP — ofsite hedef yapılandırılmamış" >&2
exit 0
