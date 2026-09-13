#!/bin/bash
# Redis RDB backup — systemd timer tarafından her gece çalıştırılır.
# Kurulum: deploy.md Faz 3.7 adımlarına bak.

set -e

BACKUP_DIR="/var/backups/redis"
REDIS_DIR="/var/lib/redis"
KEEP_DAYS=3

REDIS_PASS=$(grep '^requirepass' /etc/redis/redis.conf | awk '{print $2}')
REDIS_CLI="redis-cli -a $REDIS_PASS --no-auth-warning"

mkdir -p "$BACKUP_DIR"

START=$($REDIS_CLI LASTSAVE)

if echo "$START" | grep -q "NOAUTH\|ERR"; then
    echo "[redis-backup] HATA: Redis auth başarısız" >&2
    exit 1
fi

$REDIS_CLI BGSAVE
for i in $(seq 1 10); do
    sleep 2
    STATUS=$($REDIS_CLI LASTSAVE)
    if [ "$STATUS" -gt "$START" ] 2>/dev/null; then
        break
    fi
done

DATE=$(date +%Y-%m-%d)
cp "$REDIS_DIR/dump.rdb" "$BACKUP_DIR/dump-$DATE.rdb"
echo "[$(date '+%F %T')] Backup alındı: $BACKUP_DIR/dump-$DATE.rdb ($(du -sh "$BACKUP_DIR/dump-$DATE.rdb" | cut -f1))"

DELETED=$(find "$BACKUP_DIR" -name "dump-*.rdb" -mtime +$KEEP_DAYS -print -delete)
if [ -n "$DELETED" ]; then
    echo "[$(date '+%F %T')] Silindi: $DELETED"
fi
