#!/bin/bash
# MinIO ILM (Information Lifecycle Management) kurulum scripti.
#
# Node1'de MinIO başladıktan SONRA bir kez çalıştır:
#   sudo -u tucibeyin bash deploy/scale/V2.1/scripts/setup_minio_ilm.sh
#
# Güvenli: idempotent. Kural varsa günceller, yoksa oluşturur.
# recordings/ için hedef expiry: 2 gün
#   - node2 minio_backup.sh mirror başarılı → node2_confirmed_at set
#   - archive_recordings_task: node2_confirmed_at IS NOT NULL + transferred_at + 2g guard
#   - Böylece 4 günlük kör bekleme kalktı, node1 NVMe daha erken boşalır
set -euo pipefail

source /project/teqlif/config/.env.minio

MINIO_URL=http://10.10.0.1:9000
ALIAS=teqlif-prod
TARGET_DAYS=2

mc alias set "${ALIAS}" "${MINIO_URL}" "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASSWORD}" --quiet

# Mevcut recordings/ kuralının ID'sini bul
RULE_ID=$(mc ilm ls "${ALIAS}/teqlif" --json 2>/dev/null \
    | python3 -c "
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
    except Exception:
        continue
    for rule in (obj.get('config') or {}).get('rules') or []:
        prefix = (rule.get('filter') or {}).get('prefix') or ''
        if prefix == 'recordings/':
            print(rule.get('id',''))
" 2>/dev/null || true)

if [ -n "${RULE_ID}" ]; then
    mc ilm edit --id "${RULE_ID}" --expiry-days "${TARGET_DAYS}" "${ALIAS}/teqlif"
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) MinIO ILM: recordings/ kuralı güncellendi → ${TARGET_DAYS} gün (id=${RULE_ID})"
else
    mc ilm add \
        --prefix "recordings/" \
        --expiry-days "${TARGET_DAYS}" \
        "${ALIAS}/teqlif"
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) MinIO ILM: recordings/ kuralı oluşturuldu → ${TARGET_DAYS} gün"
fi

echo ""
mc ilm ls "${ALIAS}/teqlif"
