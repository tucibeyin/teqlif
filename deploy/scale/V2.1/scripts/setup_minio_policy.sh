#!/bin/bash
# MinIO bucket policy kurulum scripti.
#
# Node1'de MinIO başladıktan ve bucket oluşturulduktan SONRA bir kez çalıştır:
#   sudo -u tucibeyin bash deploy/scale/V2.1/scripts/setup_minio_policy.sh
#
# Güvenli: idempotent. Mevcut policy'yi kontrol eder, gerekiyorsa günceller.
#
# Politika:
#   teqlif        → download  (anonim GET/HEAD izinli; ilan görselleri, profil fotoğrafları)
#   teqlif-dm     → private   (DM ekleri — sadece imzalı URL ile erişilir)
set -euo pipefail

source /project/teqlif/config/.env.minio

MINIO_URL=http://10.10.0.1:9000
ALIAS=teqlif-prod

mc alias set "${ALIAS}" "${MINIO_URL}" "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASSWORD}" --quiet

# teqlif bucket → download (public read, no anonymous write)
CURRENT=$(mc anonymous get "${ALIAS}/${MINIO_BUCKET}" 2>/dev/null | awk '{print $NF}' || echo "unknown")
if [ "${CURRENT}" != "download" ]; then
    mc anonymous set download "${ALIAS}/${MINIO_BUCKET}"
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) MinIO policy: ${MINIO_BUCKET} → download"
else
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) MinIO policy: ${MINIO_BUCKET} zaten download, değişiklik yok"
fi

# teqlif-dm bucket → private (DM eklerinde presigned URL kullanılır)
DM_CURRENT=$(mc anonymous get "${ALIAS}/${MINIO_DM_BUCKET}" 2>/dev/null | awk '{print $NF}' || echo "unknown")
if [ "${DM_CURRENT}" != "none" ] && [ "${DM_CURRENT}" != "private" ]; then
    mc anonymous set none "${ALIAS}/${MINIO_DM_BUCKET}"
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) MinIO policy: ${MINIO_DM_BUCKET} → private"
else
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) MinIO policy: ${MINIO_DM_BUCKET} zaten private, değişiklik yok"
fi

echo ""
echo "=== Mevcut policy özeti ==="
mc anonymous get "${ALIAS}/${MINIO_BUCKET}"
mc anonymous get "${ALIAS}/${MINIO_DM_BUCKET}"
