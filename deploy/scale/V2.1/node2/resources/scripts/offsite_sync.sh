#!/bin/bash
set -euo pipefail

B2_BUCKET="b2backup:teqlif-backup"
LOCAL_BASE=/project/teqlif/backups

rclone sync "${LOCAL_BASE}/pg_dump/"  "${B2_BUCKET}/pg_dump/"  --transfers 4 --checkers 8  --log-level INFO
rclone sync "${LOCAL_BASE}/pg_wal/"   "${B2_BUCKET}/pg_wal/"   --transfers 8 --checkers 16 --log-level INFO
rclone sync "${LOCAL_BASE}/redis/"    "${B2_BUCKET}/redis/"    --transfers 2 --checkers 4  --log-level INFO
rclone sync "${LOCAL_BASE}/minio/"    "${B2_BUCKET}/minio/"    --transfers 4 --checkers 8  --log-level INFO

logger "teqlif offsite_sync: tümü B2'ye senkronize edildi"
