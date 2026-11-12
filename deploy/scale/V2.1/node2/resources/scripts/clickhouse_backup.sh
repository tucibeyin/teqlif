#!/bin/bash
# clickhouse_backup.sh — teqlif ClickHouse backup → /project/teqlif/backups/clickhouse/
# Zamanlama: her gün 03:20 UTC (teqlif-clickhouse-backup.timer)
#
# Yöntem 1: clickhouse-backup CLI (tercih edilen, atomik snapshot)
# Yöntem 2: SQL BACKUP DATABASE TO Disk('backups', 'name.zip')
#   → teqlif kullanıcısında GRANT BACKUP ON *.* zorunlu
#   → Disk('backups') → /project/teqlif/backups/clickhouse/ (teqlif.xml)
# Yöntem 3: Native format export + schema.sql DDL (son çare)
#
# Ortam değişkenleri /project/teqlif/config/.env.backup'tan gelir:
#   CLICKHOUSE_DB       — veritabanı adı (varsayılan: teqlif_prod_analytics)
#   CLICKHOUSE_USER     — CH kullanıcısı (varsayılan: teqlif)
#   CLICKHOUSE_PASSWORD — CH parolası

set -euo pipefail

source /project/teqlif/config/.env.backup

CH_DB="${CLICKHOUSE_DB:-teqlif_prod_analytics}"
CH_USER="${CLICKHOUSE_USER:-teqlif}"
CH_PASS="${CLICKHOUSE_PASSWORD:-}"
CH_PASS_ARG=()
[[ -n "${CH_PASS}" ]] && CH_PASS_ARG=(--password "${CH_PASS}")

BACKUP_DIR=/project/teqlif/backups/clickhouse
RETENTION_DAYS=7
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="${CH_DB}_${TIMESTAMP}"
DEST="${BACKUP_DIR}/${BACKUP_NAME}"
BACKUP_METHOD="primary"

LOGFILE=/project/teqlif/logs/clickhouse_backup.log
install -d "$(dirname "${LOGFILE}")"
exec >> "${LOGFILE}" 2>&1

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) clickhouse_backup: start"

mkdir -p "${BACKUP_DIR}"

# Yöntem 1: clickhouse-backup CLI (tercih edilen, atomik snapshot)
if command -v clickhouse-backup &>/dev/null && \
   clickhouse-backup create "${BACKUP_NAME}" --tables="${CH_DB}.*" 2>/dev/null; then
    :

# Yöntem 2: SQL BACKUP — Disk('backups', ...) → /project/teqlif/backups/clickhouse/
# Gereksinim: GRANT BACKUP ON *.* TO teqlif (bootstrap_node2.sh post adım)
elif clickhouse-client \
        --host 127.0.0.1 --port 9000 --user "${CH_USER}" "${CH_PASS_ARG[@]}" \
        --query "BACKUP DATABASE \`${CH_DB}\` TO Disk('backups', '${BACKUP_NAME}.zip')" \
        2>/dev/null; then
    BACKUP_METHOD="sql"

# Yöntem 3: Native format export + schema.sql DDL (son çare — Yöntem 1/2 mevcut değil)
else
    BACKUP_METHOD="fallback"
    mkdir -p "${DEST}"
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) clickhouse_backup: WARN — Yöntem 1/2 başarısız, fallback başlatıldı"

    # DDL schema dump — tüm tablolar + view'lar (MV iç tabloları hariç)
    while IFS= read -r tname; do
        echo "-- ${tname}" >> "${DEST}/schema.sql"
        clickhouse-client --host 127.0.0.1 --port 9000 --user "${CH_USER}" "${CH_PASS_ARG[@]}" \
            --query "SELECT create_table_query FROM system.tables WHERE database='${CH_DB}' AND name='${tname}' FORMAT TabSeparated" \
            2>/dev/null >> "${DEST}/schema.sql" || true
        echo "" >> "${DEST}/schema.sql"
    done < <(clickhouse-client --host 127.0.0.1 --port 9000 --user "${CH_USER}" "${CH_PASS_ARG[@]}" \
        --query "SELECT name FROM system.tables WHERE database='${CH_DB}' AND name NOT LIKE '.inner%' ORDER BY name" \
        2>/dev/null || true)

    # Veri export — sadece MergeTree tabloları (View/MV export edilmez)
    while IFS= read -r tname; do
        clickhouse-client --host 127.0.0.1 --port 9000 --user "${CH_USER}" "${CH_PASS_ARG[@]}" \
            --query "SELECT * FROM \`${CH_DB}\`.\`${tname}\` FORMAT Native" \
            > "${DEST}/${tname}.native" || true
    done < <(clickhouse-client --host 127.0.0.1 --port 9000 --user "${CH_USER}" "${CH_PASS_ARG[@]}" \
        --query "SELECT name FROM system.tables WHERE database='${CH_DB}' AND engine NOT IN ('MaterializedView','View') AND name NOT LIKE '.inner%' ORDER BY name" \
        2>/dev/null || true)

    tar -czf "${DEST}.tar.gz" -C "${BACKUP_DIR}" "$(basename "${DEST}")"
    rm -rf "${DEST}"

    if [[ ! -s "${DEST}.tar.gz" ]]; then
        echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) clickhouse_backup: FAIL — fallback tar.gz boş veya yok"
        logger -p user.err "teqlif clickhouse_backup: fallback BAŞARISIZ — tar.gz boş veya yok"
        exit 1
    fi
fi

# Retention temizliği — her iki yöntemin çıktısı aynı dizinde
find "${BACKUP_DIR}" -name '*.tar.gz' -mtime +${RETENTION_DAYS} -delete
find "${BACKUP_DIR}" -name '*.zip'    -mtime +${RETENTION_DAYS} -delete
find "${BACKUP_DIR}" -mindepth 1 -maxdepth 1 -type d -mtime +${RETENTION_DAYS} -exec rm -rf {} +

TIMESTAMP_NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
redis-cli -h 10.10.0.1 -p 6379 -a "${CORE_REDIS_PASS}" --no-auth-warning \
    HSET teqlif:agent:job_ok clickhouse_backup "${TIMESTAMP_NOW}" >/dev/null 2>&1 || true

if [[ "${BACKUP_METHOD}" == "fallback" ]]; then
    logger -p user.warning "teqlif clickhouse_backup: native fallback kullanıldı (Yöntem 1/2 kurulu değil veya BACKUP grant eksik)"
fi

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) clickhouse_backup: OK (${BACKUP_METHOD})"
logger "teqlif clickhouse_backup: tamamlandı (${BACKUP_METHOD})"
