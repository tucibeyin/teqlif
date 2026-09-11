#!/usr/bin/env bash
# PostgreSQL backup — teqlif-backup.service tarafından her gece 03:00 UTC'de çalıştırılır.
set -euo pipefail

BACKUP_DIR="/var/backups/pg"
DB="teqlif"
KEEP_DAYS=3

mkdir -p "$BACKUP_DIR"

DATE=$(date +%Y-%m-%d)
OUTFILE="$BACKUP_DIR/${DB}-${DATE}.sql.gz"

sudo -u postgres pg_dump "$DB" | gzip > "$OUTFILE"
echo "[$(date '+%F %T')] pg_dump tamamlandi: $OUTFILE ($(du -sh "$OUTFILE" | cut -f1))"

DELETED=$(find "$BACKUP_DIR" -name "${DB}-*.sql.gz" -mtime +$KEEP_DAYS -print -delete)
if [ -n "$DELETED" ]; then
  echo "[$(date '+%F %T')] Silindi: $DELETED"
fi
