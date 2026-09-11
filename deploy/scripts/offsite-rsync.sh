#!/usr/bin/env bash
# Off-site backup rsync — teqlif-backup.service tarafından pg-backup.sh'den sonra çalıştırılır.
# node1'den node3'e WireGuard üzerinden yedek gönderir.
set -euo pipefail

BACKUP_SRC="/var/backups/"
BACKUP_DEST="tucibeyin@10.10.0.4:/var/backups/teqlif/"
SSH_KEY="/root/.ssh/id_backup"
REDIS_KEEP_DAYS=14

if ! ping -c 1 -W 3 10.10.0.4 &>/dev/null; then
  echo "[$(date '+%F %T')] UYARI: node3 (10.10.0.4) erişilemiyor — rsync atlandı" >&2
  exit 1
fi

rsync -az --delete \
  -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=10" \
  "$BACKUP_SRC" "$BACKUP_DEST"

echo "[$(date '+%F %T')] rsync tamamlandi: $BACKUP_SRC → $BACKUP_DEST"

# node3'te eski Redis backup'ları temizle (redis: 14 gün retention)
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no tucibeyin@10.10.0.4 \
  "find /var/backups/teqlif/redis -name 'dump-*.rdb' -mtime +$REDIS_KEEP_DAYS -delete 2>/dev/null || true"
