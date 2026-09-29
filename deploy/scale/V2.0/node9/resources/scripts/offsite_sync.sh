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

# Sync WAL archive — pg_receivewal /opt/teqlif/backups/postgres/wal/ altına yazar
rclone sync /opt/teqlif/backups/postgres/wal/ "${B2_BUCKET}/wal/" \
    --transfers 8 \
    --checkers 16 \
    --log-level INFO

# Sync Redis RDB snapshots
rclone sync "${LOCAL_BASE}/redis/" "${B2_BUCKET}/redis/" \
    --transfers 2 \
    --checkers 4 \
    --log-level INFO

# Sync ClickHouse backups (lokal 7 gün — clickhouse_backup.sh RETENTION_DAYS=7 yönetir)
rclone sync /data/clickhouse-backups/ "${B2_BUCKET}/clickhouse/" \
    --transfers 2 \
    --checkers 4 \
    --log-level INFO

# MinIO cold archive (teqlif + teqlif-dm — mc mirror tarafından /data/backups/minio/ altına yazılır)
rclone sync /data/backups/minio/ "${B2_BUCKET}/minio/" \
    --transfers 4 \
    --checkers 8 \
    --log-level INFO

logger "offsite_sync: completed all backup categories to ${B2_BUCKET}"
