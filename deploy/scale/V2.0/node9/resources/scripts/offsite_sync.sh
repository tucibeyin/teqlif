#!/bin/bash
set -euo pipefail

B2_BUCKET=b2backup:teqlif-backup
LOCAL_BASE=/data/backups

# Sync PostgreSQL dumps
rclone sync "${LOCAL_BASE}/pg_dump/" "${B2_BUCKET}/pg_dump/" \
    --transfers 4 \
    --checkers 8 \
    --log-level INFO

# Sync PostgreSQL basebackups
rclone sync "${LOCAL_BASE}/pg_basebackup/" "${B2_BUCKET}/pg_basebackup/" \
    --transfers 2 \
    --checkers 4 \
    --log-level INFO

# Sync WAL archive
rclone sync "${LOCAL_BASE}/wal/" "${B2_BUCKET}/wal/" \
    --transfers 8 \
    --checkers 16 \
    --log-level INFO

# Sync Redis RDB snapshots
rclone sync "${LOCAL_BASE}/redis/" "${B2_BUCKET}/redis/" \
    --transfers 2 \
    --checkers 4 \
    --log-level INFO

# Sync ClickHouse backups
rclone sync /data/clickhouse-backups/ "${B2_BUCKET}/clickhouse/" \
    --transfers 2 \
    --checkers 4 \
    --log-level INFO

logger "offsite_sync: completed all backup categories to ${B2_BUCKET}"
