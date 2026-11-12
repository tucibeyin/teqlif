#!/bin/bash
set -euo pipefail

source /project/teqlif/config/.env.backup

BACKUP_DIR=/project/teqlif/backups/minio
LOGFILE=/project/teqlif/logs/minio_backup.log
MINIO_URL=http://10.10.0.1:9000

install -d "${BACKUP_DIR}"
exec >> "${LOGFILE}" 2>&1
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) minio_backup: start"

mc alias set node1minio "${MINIO_URL}" "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASSWORD}" --quiet

mirror_bucket() {
    local bucket="$1"
    shift
    local dest="${BACKUP_DIR}/${bucket}"
    install -d "${dest}"
    mc mirror --overwrite --quiet "$@" "node1minio/${bucket}" "${dest}"
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) minio_backup: ${bucket} OK ($(du -sh "${dest}" | cut -f1))"
}

# WireGuard ağ dalgalanmalarına karşı 3x retry, 2 dakika backoff
mirror_bucket_with_retry() {
    local bucket="$1"
    shift
    local attempt
    for attempt in 1 2 3; do
        if mirror_bucket "${bucket}" "$@"; then
            return 0
        fi
        echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) minio_backup: ${bucket} deneme ${attempt}/3 başarısız"
        [[ ${attempt} -lt 3 ]] && sleep 120
    done
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) minio_backup: ${bucket} 3 denemede başarısız"
    return 1
}

MINIO_ILM_NORMAL_DAYS=2
MINIO_ILM_EMERGENCY_DAYS=7

ilm_set_days() {
    local days="$1"
    local rule_id
    rule_id=$(mc ilm ls node1minio/teqlif --json 2>/dev/null | python3 -c "
import sys, json
for line in sys.stdin:
    try:
        d = json.loads(line)
        cfg = d.get('config') or {}
        rules = cfg.get('Rules') or cfg.get('rules') or []
        for r in rules:
            filt = r.get('Filter') or r.get('filter') or {}
            prefix = filt.get('Prefix') or filt.get('prefix') or ''
            if prefix == 'recordings/':
                print(r.get('ID') or r.get('id') or '')
    except Exception: pass
" 2>/dev/null | head -1) || true

    if [[ -n "${rule_id}" ]]; then
        mc ilm edit --id "${rule_id}" --expiry-days "${days}" node1minio/teqlif \
            && echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) minio_backup: ILM retention=${days}d (id=${rule_id})" \
            || echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) minio_backup: WARNING ILM güncellenemedi (id=${rule_id})"
    else
        echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) minio_backup: WARNING ILM kural bulunamadı — recordings/ kuralı mevcut değil"
    fi
}

# SYNC_START: confirm_recordings bu anı kesme noktası olarak kullanır (race koruması)
SYNC_START=$(date -u +%Y-%m-%dT%H:%M:%SZ)

teqlif_ok=false
teqlif_dm_ok=false

# teqlif: recordings/ dışı --remove ile KVKK silmelerini yansıt; recordings/ ayrıca --remove'suz
{ mirror_bucket_with_retry teqlif --remove --exclude 'recordings/*' && \
  mirror_bucket_with_retry teqlif --include 'recordings/*'; } && teqlif_ok=true || true

# 30 günden eski recordings yerel kopyalarını temizle (MinIO ILM'den bağımsız yerel retention)
find "${BACKUP_DIR}/teqlif/recordings" -type f -mtime +30 -delete 2>/dev/null || true

mirror_bucket_with_retry teqlif-dm --remove && teqlif_dm_ok=true || true

if ! $teqlif_ok || ! $teqlif_dm_ok; then
    ilm_set_days "${MINIO_ILM_EMERGENCY_DAYS}"
    exit 1
fi
ilm_set_days "${MINIO_ILM_NORMAL_DAYS}"

# teqlif bucket mirror başarılı → node1 MinIO'daki tüm nesneler node2'de mevcut.
# Henüz onaylanmamış stream_recordings kayıtlarını damgala.
# PG güncellemesi başarısız olsa da MinIO yedek tamam — sadece WARN logla.
confirm_recordings() {
    local updated
    updated=$(PGPASSWORD="${TEQLIF_DB_PASSWORD}" psql \
        -h 10.10.0.1 -p 5432 -U teqlif teqlif \
        --no-align --tuples-only -q \
        -c "WITH upd AS (
                UPDATE stream_recordings
                SET node2_confirmed_at = NOW(), updated_at = NOW()
                WHERE node2_confirmed_at IS NULL
                  AND minio_key IS NOT NULL
                  AND COALESCE(transferred_at, available_at) IS NOT NULL
                  AND COALESCE(transferred_at, available_at, created_at) <= '${SYNC_START}'::timestamptz
                  AND status IN ('available','expired')
                RETURNING 1
            ) SELECT COUNT(*) FROM upd" 2>&1) || { \
        echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) minio_backup: WARNING node2_confirmed_at güncellenemedi: ${updated}"; \
        return 0; \
    }
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) minio_backup: node2_confirmed_at set: ${updated} kayıt"
}

confirm_recordings

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) minio_backup: tamamlandı"
touch "${BACKUP_DIR}/.last_backup_ok"
logger "teqlif minio_backup: tamamlandı"
redis-cli -h 10.10.0.1 -p 6379 -a "${CORE_REDIS_PASS}" --no-auth-warning HSET teqlif:agent:job_ok minio_backup "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >/dev/null 2>&1 || true
