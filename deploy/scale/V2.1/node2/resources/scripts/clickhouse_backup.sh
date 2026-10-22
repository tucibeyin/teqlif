#!/bin/bash
set -euo pipefail

source /project/teqlif/config/.env.backup

# Ortama özgü değerler — .env.backup'ta tanımlanır
CH_DB="${CLICKHOUSE_DB:-teqlif_prod_analytics}"
CH_USER="${CLICKHOUSE_USER:-teqlif}"
CH_PASS="${CLICKHOUSE_PASSWORD:-}"
CH_PASS_ARG=()
[[ -n "${CH_PASS}" ]] && CH_PASS_ARG=(--password "${CH_PASS}")

BACKUP_DIR=/project/teqlif/backups/clickhouse
RETENTION_DAYS=7
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DEST="${BACKUP_DIR}/${CH_DB}_${TIMESTAMP}"
BACKUP_METHOD="primary"

install -d "${BACKUP_DIR}"

# Yöntem 1: clickhouse-backup (tercih edilen, atomik snapshot)
if clickhouse-backup create --tables "${CH_DB}.*" "${DEST}" 2>/dev/null; then
    :
# Yöntem 2: SQL BACKUP komutu
elif clickhouse-client \
        --host 127.0.0.1 --port 9000 --user "${CH_USER}" "${CH_PASS_ARG[@]}" \
        --query "BACKUP DATABASE ${CH_DB} TO Disk('backups', '${CH_DB}_${TIMESTAMP}.zip')" \
        2>/dev/null; then
    BACKUP_METHOD="sql"
# Yöntem 3: Native format export (son çare — birincil yöntemler başarısız)
else
    BACKUP_METHOD="fallback"
    mkdir -p "${DEST}"
    for TABLE in user_events feed_analytics search_events swipe_live_events direct_sale_events mv_listing_events_daily; do
        clickhouse-client --host 127.0.0.1 --port 9000 --user "${CH_USER}" "${CH_PASS_ARG[@]}" \
            --query "SELECT * FROM ${CH_DB}.${TABLE} FORMAT Native" \
            > "${DEST}/${TABLE}.native"
    done
    tar -czf "${DEST}.tar.gz" -C "${BACKUP_DIR}" "$(basename "${DEST}")"
    rm -rf "${DEST}"

    # Fallback başarılı mı kontrol et (tar.gz oluştu ve boyutu > 0)
    if [[ ! -s "${DEST}.tar.gz" ]]; then
        logger -p user.err "teqlif clickhouse_backup: fallback BAŞARISIZ — tar.gz boş veya yok"
        exit 1
    fi
fi

find "${BACKUP_DIR}" -name '*.tar.gz' -mtime +${RETENTION_DAYS} -delete
find "${BACKUP_DIR}" -name '*.zip'    -mtime +${RETENTION_DAYS} -delete
find "${BACKUP_DIR}" -mindepth 1 -maxdepth 1 -type d -mtime +${RETENTION_DAYS} -exec rm -rf {} +

TIMESTAMP_NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
redis-cli -h 10.10.0.1 -p 6379 -a "${CORE_REDIS_PASS}" --no-auth-warning \
    HSET teqlif:agent:job_ok clickhouse_backup "${TIMESTAMP_NOW}" >/dev/null 2>&1 || true

if [[ "${BACKUP_METHOD}" == "fallback" ]]; then
    logger -p user.warning "teqlif clickhouse_backup: native fallback kullanıldı (birincil yöntemler kurulu değil)"
fi

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) clickhouse_backup: OK (${BACKUP_METHOD})"
logger "teqlif clickhouse_backup: tamamlandı (${BACKUP_METHOD})"
