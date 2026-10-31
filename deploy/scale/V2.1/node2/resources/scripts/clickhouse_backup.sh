#!/bin/bash
set -euo pipefail

source /project/teqlif/config/.env.backup

# Ortama özgü değerler — .env.backup'ta tanımlanır
CH_DB="${CLICKHOUSE_DB:-teqlif_prod_analytics}"
CH_USER="${CLICKHOUSE_USER:-teqlif}"
CH_PASS="${CLICKHOUSE_PASSWORD:-}"
CH_PASS_ARG=()
[[ -n "${CH_PASS}" ]] && CH_PASS_ARG=(--password "${CH_PASS}")

BACKUP_DIR=/project/teqlif/backups/clickhouse   # native fallback çıktısı (tucibeyin sahipli)
CH_DISK_DIR=/var/lib/clickhouse/backups         # SQL BACKUP çıktısı (clickhouse sahipli)
RETENTION_DAYS=7
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="${CH_DB}_${TIMESTAMP}"             # clickhouse-backup için sade isim (tam yol değil)
DEST="${BACKUP_DIR}/${BACKUP_NAME}"             # fallback native export için tam yol
BACKUP_METHOD="primary"

install -d "${BACKUP_DIR}"

# Yöntem 1: clickhouse-backup (tercih edilen, atomik snapshot)
# Doğru sözdizim: create <backup_name> --tables="<db>.*"  (tam yol değil, sadece isim)
if command -v clickhouse-backup &>/dev/null && \
   clickhouse-backup create "${BACKUP_NAME}" --tables="${CH_DB}.*" 2>/dev/null; then
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
    # Dinamik tablo listesi — yeni tablo eklense de otomatik yedeklenir
    # .inner% filtreleme: MV iç tabloları doğrudan dışa aktarılmaz
    TABLES=$(clickhouse-client --host 127.0.0.1 --port 9000 --user "${CH_USER}" "${CH_PASS_ARG[@]}" \
        --query "SELECT name FROM system.tables WHERE database='${CH_DB}' AND name NOT LIKE '.inner%'" \
        2>/dev/null || true)
    for TABLE in ${TABLES}; do
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

find "${BACKUP_DIR}"  -name '*.tar.gz' -mtime +${RETENTION_DAYS} -delete
find "${BACKUP_DIR}"  -mindepth 1 -maxdepth 1 -type d -mtime +${RETENTION_DAYS} -exec rm -rf {} +
find "${CH_DISK_DIR}" -name '*.zip'   -mtime +${RETENTION_DAYS} -delete 2>/dev/null || true

TIMESTAMP_NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
redis-cli -h 10.10.0.1 -p 6379 -a "${CORE_REDIS_PASS}" --no-auth-warning \
    HSET teqlif:agent:job_ok clickhouse_backup "${TIMESTAMP_NOW}" >/dev/null 2>&1 || true

if [[ "${BACKUP_METHOD}" == "fallback" ]]; then
    logger -p user.warning "teqlif clickhouse_backup: native fallback kullanıldı (birincil yöntemler kurulu değil)"
fi

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) clickhouse_backup: OK (${BACKUP_METHOD})"
logger "teqlif clickhouse_backup: tamamlandı (${BACKUP_METHOD})"
