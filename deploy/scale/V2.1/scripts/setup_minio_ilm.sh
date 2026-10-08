#!/bin/bash
# MinIO ILM (Information Lifecycle Management) kurulum scripti.
#
# Node1'de MinIO başladıktan SONRA bir kez çalıştır:
#   sudo -u tucibeyin bash deploy/scale/V2.1/scripts/setup_minio_ilm.sh
#
# Güvenli: idempotent. Tekrar çalıştırılabilir, mevcut policy'i günceller.
set -euo pipefail

source /project/teqlif/config/.env.minio

MINIO_URL=http://10.10.0.1:9000
ALIAS=teqlif-prod

mc alias set "${ALIAS}" "${MINIO_URL}" "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASSWORD}" --quiet

# recordings/ prefix: transferred_at'ten itibaren 4 gün sonra sil.
# archive_recordings_task bu süreye güvenir (transferred_at + 4g → archived).
mc ilm add \
    --prefix "recordings/" \
    --expiry-days 4 \
    "${ALIAS}/teqlif"

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) MinIO ILM: teqlif/recordings/ → 4 gün expiry tanımlandı"
mc ilm ls "${ALIAS}/teqlif"
