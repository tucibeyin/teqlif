#!/bin/bash
# Redis RDB backup — her gece çalışır, 3 günden eski dosyaları siler.
# Kurulum: sudo bash deploy/scripts/redis-backup.sh --install

set -e

BACKUP_DIR="/var/backups/redis"
REDIS_DIR="/var/lib/redis"
KEEP_DAYS=3

install() {
    SCRIPT_DEST="/usr/local/sbin/redis-backup.sh"
    cp "$(realpath "$0")" "$SCRIPT_DEST"
    chmod +x "$SCRIPT_DEST"

    REPO_DIR="$(dirname "$(dirname "$(dirname "$(realpath "$0")")")")"
    cp "$REPO_DIR/deploy/systemd/redis-backup.service" /etc/systemd/system/
    cp "$REPO_DIR/deploy/systemd/redis-backup.timer"   /etc/systemd/system/

    systemctl daemon-reload
    systemctl enable --now redis-backup.timer

    echo "Kurulum tamam. Durum:"
    systemctl status redis-backup.timer --no-pager
}

backup() {
    mkdir -p "$BACKUP_DIR"

    # Anlık RDB snapshot al, tamamlanmasını bekle
    redis-cli BGSAVE
    for i in $(seq 1 10); do
        sleep 2
        STATUS=$(redis-cli LASTSAVE)
        if [ "$STATUS" -gt "$START" ] 2>/dev/null; then
            break
        fi
    done

    DATE=$(date +%Y-%m-%d)
    cp "$REDIS_DIR/dump.rdb" "$BACKUP_DIR/dump-$DATE.rdb"
    echo "[$(date '+%F %T')] Backup alındı: $BACKUP_DIR/dump-$DATE.rdb ($(du -sh "$BACKUP_DIR/dump-$DATE.rdb" | cut -f1))"

    # 3 günden eski dosyaları sil
    DELETED=$(find "$BACKUP_DIR" -name "dump-*.rdb" -mtime +$KEEP_DAYS -print -delete)
    if [ -n "$DELETED" ]; then
        echo "[$(date '+%F %T')] Silindi: $DELETED"
    fi
}

if [ "$1" = "--install" ]; then
    install
else
    START=$(redis-cli LASTSAVE)
    backup
fi
