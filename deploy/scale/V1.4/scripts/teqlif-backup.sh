#!/usr/bin/env bash
# deploy/scale/V1.4/scripts/teqlif-backup.sh
#
# Generic backup agent — servis tabanlı tespit, node bağımsız.
# Hangi node'da çalıştığını bilmez; çalışan servislere bakarak karar verir.
#
# Çalıştırmak için: sudo teqlif-backup
# Wrapper kurulumu (bootstrap'ta bir kez):
#   printf '#!/bin/sh\nexec /var/www/teqlif.com/deploy/scale/V1.4/scripts/teqlif-backup.sh "$@"\n' \
#     | sudo tee /usr/local/bin/teqlif-backup && sudo chmod +x /usr/local/bin/teqlif-backup

set -euo pipefail

# ── Renkler ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
SEP="${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

# ── Sabitler ──────────────────────────────────────────────────────────────────
TIMESTAMP=$(date -u '+%Y%m%dT%H%M%SZ')
HOSTNAME=$(hostname)
BACKUP_LOCAL_ROOT="/var/backups/teqlif"
ENV_FILE="/var/www/teqlif.com/backend/.env.production"

# ── Varsayılanlar (.env.production ile override edilir) ───────────────────────
BACKUP_REMOTE_HOST=""
BACKUP_REMOTE_PATH="/var/backups/teqlif"
BACKUP_REMOTE_USER="tucibeyin"
BACKUP_RETENTION_LOCAL_DAYS=2
BACKUP_RETENTION_REMOTE_DAYS=7
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""
REDIS_URL=""

# ── .env.production oku ───────────────────────────────────────────────────────
_env_get() {
    local key="$1" default="${2:-}"
    [[ -f "$ENV_FILE" ]] || { echo "$default"; return; }
    local val
    val=$(grep -E "^${key}=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | sed "s/^['\"]//;s/['\"]$//" || true)
    echo "${val:-$default}"
}

BACKUP_REMOTE_HOST=$(_env_get BACKUP_REMOTE_HOST "")
BACKUP_REMOTE_PATH=$(_env_get BACKUP_REMOTE_PATH "/var/backups/teqlif")
BACKUP_REMOTE_USER=$(_env_get BACKUP_REMOTE_USER "tucibeyin")
BACKUP_RETENTION_LOCAL_DAYS=$(_env_get BACKUP_RETENTION_LOCAL_DAYS "2")
BACKUP_RETENTION_REMOTE_DAYS=$(_env_get BACKUP_RETENTION_REMOTE_DAYS "7")
TELEGRAM_BOT_TOKEN=$(_env_get TELEGRAM_BOT_TOKEN "")
TELEGRAM_CHAT_ID=$(_env_get TELEGRAM_CHAT_ID "")
REDIS_URL=$(_env_get REDIS_URL "")

# ── Durum takibi ──────────────────────────────────────────────────────────────
BACKED_UP=()
SKIPPED=()
FAILED=()

# ── Yardımcı: Telegram bildirim ───────────────────────────────────────────────
_telegram() {
    local msg="$1"
    [[ -z "$TELEGRAM_BOT_TOKEN" || -z "$TELEGRAM_CHAT_ID" ]] && return 0
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=${msg}" \
        -d "parse_mode=HTML" > /dev/null 2>&1 || true
}

# ── Yardımcı: Dosya boyutu ────────────────────────────────────────────────────
_size() { [[ -f "$1" ]] && du -sh "$1" 2>/dev/null | cut -f1 || echo "?"; }

# ── Header ────────────────────────────────────────────────────────────────────
echo ""
echo -e "$SEP"
echo -e "${BOLD}${CYAN}  teqlif-backup  ·  ${TIMESTAMP}  ·  ${HOSTNAME}${RESET}"
echo -e "$SEP"
echo ""

# ════════════════════════════════════════════════════════════════════════════
# Üretim kontrolü — servis tabanlı karar
# ════════════════════════════════════════════════════════════════════════════
IS_PROD=false
IS_STAGING=false

systemctl is-active teqlif         &>/dev/null && IS_PROD=true
systemctl is-active teqlif-staging &>/dev/null && IS_STAGING=true

if [[ "$IS_STAGING" == true && "$IS_PROD" == false ]]; then
    echo -e "  ${YELLOW}Bu node staging ortamı (teqlif-staging aktif, teqlif değil) — backup atlandı.${RESET}"
    exit 0
fi

if [[ "$IS_PROD" == false ]]; then
    echo -e "  ${YELLOW}Production servisi (teqlif) bu node'da aktif değil — backup atlandı.${RESET}"
    exit 0
fi

# Disk doluluk kontrolü — %85 üstünde uyarı, %95 üstünde dur
DISK_PCT=$(df "$BACKUP_LOCAL_ROOT" 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%')
[[ -z "$DISK_PCT" ]] && DISK_PCT=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
if [[ "${DISK_PCT:-0}" -ge 95 ]]; then
    MSG="🔴 <b>teqlif-backup DURDU</b> · ${HOSTNAME}
Disk doluluk %${DISK_PCT} — backup başlatılmadı. Temizlik gerekli."
    echo -e "  ${RED}Disk doluluk %${DISK_PCT} → backup durduruldu.${RESET}"
    _telegram "$MSG"
    exit 1
elif [[ "${DISK_PCT:-0}" -ge 85 ]]; then
    echo -e "  ${YELLOW}Uyarı: Disk doluluk %${DISK_PCT}${RESET}"
fi

# Dizinleri hazırla
mkdir -p \
    "$BACKUP_LOCAL_ROOT/pg" \
    "$BACKUP_LOCAL_ROOT/redis" \
    "$BACKUP_LOCAL_ROOT/ch"

# ════════════════════════════════════════════════════════════════════════════
# [1/5] PostgreSQL
# ════════════════════════════════════════════════════════════════════════════
echo -e "${BOLD}[1/5] PostgreSQL${RESET}"

_pg_active=false
systemctl is-active "postgresql@*" &>/dev/null && _pg_active=true
systemctl is-active postgresql     &>/dev/null && _pg_active=true

if [[ "$_pg_active" == false ]]; then
    echo -e "  ${YELLOW}⊘  postgresql inactive — atlandı${RESET}"
    SKIPPED+=("postgresql")
else
    # Üretim DB'lerini keşfet: template/postgres/staging/test dışı
    PG_DBS=$(sudo -u postgres psql -tAc \
        "SELECT datname FROM pg_database
         WHERE datistemplate = false
           AND datname NOT IN ('postgres')
           AND datname NOT LIKE '%staging%'
           AND datname NOT LIKE '%test%'" 2>/dev/null || echo "")

    if [[ -z "$PG_DBS" ]]; then
        echo -e "  ${YELLOW}⊘  Yedeklenecek production DB bulunamadı — atlandı${RESET}"
        SKIPPED+=("postgresql (no production dbs)")
    else
        for db in $PG_DBS; do
            TABLE_COUNT=$(sudo -u postgres psql -d "$db" -tAc \
                "SELECT COUNT(*) FROM information_schema.tables
                 WHERE table_schema = 'public'" \
                2>/dev/null | tr -d ' \n' || echo "0")

            if [[ "${TABLE_COUNT:-0}" -eq 0 ]]; then
                echo -e "  ${YELLOW}⊘  ${db} — boş şema, atlandı${RESET}"
                SKIPPED+=("pg/${db} (empty)")
                continue
            fi

            DEST="$BACKUP_LOCAL_ROOT/pg/teqlif_pg_${db}_${TIMESTAMP}.pgdump"
            printf "  ↻  %-32s " "${db} (${TABLE_COUNT} tablo)..."

            if sudo -u postgres pg_dump \
                    --format=custom \
                    --compress=6 \
                    "$db" \
                    --file="$DEST" 2>/dev/null && [[ -s "$DEST" ]]; then
                echo -e "${GREEN}✓  $(_size "$DEST")${RESET}"
                BACKED_UP+=("pg/${db} $(_size "$DEST")")
            else
                rm -f "$DEST"
                echo -e "${RED}✗  pg_dump başarısız${RESET}"
                FAILED+=("pg/${db}")
            fi
        done
    fi
fi
echo ""

# ════════════════════════════════════════════════════════════════════════════
# [2/5] Redis
# ════════════════════════════════════════════════════════════════════════════
echo -e "${BOLD}[2/5] Redis${RESET}"

if ! systemctl is-active redis-server &>/dev/null; then
    echo -e "  ${YELLOW}⊘  redis-server inactive — atlandı${RESET}"
    SKIPPED+=("redis")
else
    # Bağlantı bilgisini REDIS_URL'den çıkar: redis://:<pass>@<host>:<port>/<db>
    REDIS_AUTH=$(echo "$REDIS_URL" | grep -oP '(?<=redis://:)[^@]+(?=@)' 2>/dev/null || echo "")
    REDIS_HOST=$(echo "$REDIS_URL" | grep -oP '(?<=@)[^:]+(?=:)' 2>/dev/null || echo "127.0.0.1")
    REDIS_PORT=$(echo "$REDIS_URL" | grep -oP ':\d+/' | grep -oP '\d+' | tail -1 2>/dev/null || echo "6379")

    R_ARGS=(-h "${REDIS_HOST:-127.0.0.1}" -p "${REDIS_PORT:-6379}")
    [[ -n "$REDIS_AUTH" ]] && R_ARGS+=(-a "$REDIS_AUTH" --no-auth-warning)

    KEY_COUNT=$(redis-cli "${R_ARGS[@]}" DBSIZE 2>/dev/null | tr -d ' \n' || echo "0")

    if [[ "${KEY_COUNT:-0}" -lt 10 ]]; then
        echo -e "  ${YELLOW}⊘  Redis önemsiz (${KEY_COUNT} key) — atlandı${RESET}"
        SKIPPED+=("redis (${KEY_COUNT} keys)")
    else
        printf "  ↻  BGSAVE (%s key)... " "$KEY_COUNT"
        redis-cli "${R_ARGS[@]}" BGSAVE > /dev/null 2>&1 || true

        # BGSAVE tamamlanmasını bekle (maks 60s)
        for _i in $(seq 1 60); do
            _in_progress=$(redis-cli "${R_ARGS[@]}" INFO persistence 2>/dev/null \
                | grep "rdb_bgsave_in_progress" | cut -d: -f2 | tr -d ' \r\n' || echo "0")
            [[ "$_in_progress" == "0" ]] && break
            sleep 1
        done

        # RDB konumunu sorgula
        RDB_DIR=$(redis-cli "${R_ARGS[@]}" CONFIG GET dir 2>/dev/null | tail -1 | tr -d ' \r\n' || echo "/var/lib/redis")
        RDB_NAME=$(redis-cli "${R_ARGS[@]}" CONFIG GET dbfilename 2>/dev/null | tail -1 | tr -d ' \r\n' || echo "dump.rdb")
        RDB_PATH="${RDB_DIR}/${RDB_NAME}"

        if [[ -s "$RDB_PATH" ]]; then
            DEST="$BACKUP_LOCAL_ROOT/redis/teqlif_redis_${TIMESTAMP}.rdb.gz"
            gzip -c "$RDB_PATH" > "$DEST"
            echo -e "${GREEN}✓  $(_size "$DEST")${RESET}"
            BACKED_UP+=("redis $(_size "$DEST")")
        else
            echo -e "${RED}✗  RDB bulunamadı: ${RDB_PATH}${RESET}"
            FAILED+=("redis (rdb not found: ${RDB_PATH})")
        fi
    fi
fi
echo ""

# ════════════════════════════════════════════════════════════════════════════
# [3/5] ClickHouse
# ════════════════════════════════════════════════════════════════════════════
echo -e "${BOLD}[3/5] ClickHouse${RESET}"

if ! systemctl is-active clickhouse-server &>/dev/null; then
    echo -e "  ${YELLOW}⊘  clickhouse-server inactive — atlandı${RESET}"
    SKIPPED+=("clickhouse")
else
    CH_DBS=$(clickhouse-client --query \
        "SELECT name FROM system.databases
         WHERE engine = 'Atomic'
           AND name NOT IN ('system','information_schema','INFORMATION_SCHEMA','default')
           AND name NOT LIKE '%staging%'
           AND name NOT LIKE '%test%'" 2>/dev/null || echo "")

    if [[ -z "$CH_DBS" ]]; then
        echo -e "  ${YELLOW}⊘  Yedeklenecek ClickHouse DB bulunamadı — atlandı${RESET}"
        SKIPPED+=("clickhouse (no production dbs)")
    else
        for chdb in $CH_DBS; do
            ROW_COUNT=$(clickhouse-client --query \
                "SELECT formatReadableQuantity(sum(total_rows))
                 FROM system.tables WHERE database='${chdb}'" \
                2>/dev/null | tr -d ' \n' || echo "0")

            EMPTY_CHECK=$(clickhouse-client --query \
                "SELECT sum(total_rows) FROM system.tables WHERE database='${chdb}'" \
                2>/dev/null | tr -d ' \n' || echo "0")

            if [[ "${EMPTY_CHECK:-0}" -eq 0 ]]; then
                echo -e "  ${YELLOW}⊘  ${chdb} — boş, atlandı${RESET}"
                SKIPPED+=("ch/${chdb} (empty)")
                continue
            fi

            # ClickHouse native BACKUP (22.4+)
            CH_TMP_NAME="teqlif_ch_${chdb}_${TIMESTAMP}"
            CH_TMP_PATH="/var/lib/clickhouse/backup/${CH_TMP_NAME}"
            DEST="$BACKUP_LOCAL_ROOT/ch/${CH_TMP_NAME}.tar.zst"

            printf "  ↻  %-32s " "${chdb} (~${ROW_COUNT} rows)..."

            if clickhouse-client --query \
                "BACKUP DATABASE \`${chdb}\` TO File('${CH_TMP_PATH}')" \
                2>/dev/null && [[ -d "$CH_TMP_PATH" ]]; then
                tar -I 'zstd -3' -cf "$DEST" \
                    -C "$(dirname "$CH_TMP_PATH")" \
                    "$(basename "$CH_TMP_PATH")" 2>/dev/null
                rm -rf "$CH_TMP_PATH"
                echo -e "${GREEN}✓  $(_size "$DEST")${RESET}"
                BACKED_UP+=("ch/${chdb} $(_size "$DEST")")
            else
                rm -rf "$CH_TMP_PATH"
                echo -e "${RED}✗  BACKUP komutu başarısız${RESET}"
                FAILED+=("ch/${chdb}")
            fi
        done
    fi
fi
echo ""

# ════════════════════════════════════════════════════════════════════════════
# Erken çıkış: yedeklenecek hiçbir şey yoksa
# ════════════════════════════════════════════════════════════════════════════
if [[ ${#BACKED_UP[@]} -eq 0 && ${#FAILED[@]} -eq 0 ]]; then
    echo -e "${YELLOW}Bu node'da yedeklenecek aktif production verisi bulunamadı.${RESET}"
    _telegram "⚠️ <b>teqlif-backup</b> · ${HOSTNAME} · ${TIMESTAMP}
Yedeklenecek aktif veri yok.
Atlandı: $(IFS=', '; echo "${SKIPPED[*]:-—}")"
    exit 0
fi

# Tüm backup'lar başarısız → temizlik yapma
if [[ ${#FAILED[@]} -gt 0 && ${#BACKED_UP[@]} -eq 0 ]]; then
    echo -e "${RED}${BOLD}Tüm backup işlemleri başarısız — temizlik ve rsync atlandı.${RESET}"
    _telegram "🔴 <b>teqlif-backup BAŞARISIZ</b> · ${HOSTNAME} · ${TIMESTAMP}
Başarısız: $(IFS=', '; echo "${FAILED[*]}")"
    exit 1
fi

# ════════════════════════════════════════════════════════════════════════════
# [4/5] Rsync → remote
# ════════════════════════════════════════════════════════════════════════════
echo -e "${BOLD}[4/5] Rsync → remote${RESET}"
RSYNC_OK=false

if [[ -z "$BACKUP_REMOTE_HOST" ]]; then
    echo -e "  ${YELLOW}⊘  BACKUP_REMOTE_HOST tanımlı değil — rsync atlandı${RESET}"
else
    REMOTE_DEST="${BACKUP_REMOTE_USER}@${BACKUP_REMOTE_HOST}:${BACKUP_REMOTE_PATH}/${HOSTNAME}"
    printf "  ↻  %s ... " "$REMOTE_DEST"

    # Remote dizini oluştur
    ssh -o StrictHostKeyChecking=no \
        -o ConnectTimeout=15 \
        -o BatchMode=yes \
        "${BACKUP_REMOTE_USER}@${BACKUP_REMOTE_HOST}" \
        "mkdir -p '${BACKUP_REMOTE_PATH}/${HOSTNAME}/pg' \
                  '${BACKUP_REMOTE_PATH}/${HOSTNAME}/redis' \
                  '${BACKUP_REMOTE_PATH}/${HOSTNAME}/ch'" 2>/dev/null || true

    if rsync \
        --archive \
        --compress \
        --delete \
        --timeout=120 \
        -e "ssh -o StrictHostKeyChecking=no -o ConnectTimeout=15 -o BatchMode=yes" \
        "$BACKUP_LOCAL_ROOT/" \
        "$REMOTE_DEST/" 2>/dev/null; then
        echo -e "${GREEN}✓  rsync tamamlandı${RESET}"
        RSYNC_OK=true
    else
        echo -e "${RED}✗  rsync başarısız (SSH erişimi, key kurulumu veya ağ sorunu)${RESET}"
    fi
fi
echo ""

# ════════════════════════════════════════════════════════════════════════════
# [5/5] Retention temizliği — yalnızca backup başarılıysa
# ════════════════════════════════════════════════════════════════════════════
echo -e "${BOLD}[5/5] Retention temizliği${RESET}"

# Local: 2 gün (veya BACKUP_RETENTION_LOCAL_DAYS)
LOCAL_DEL=$(find "$BACKUP_LOCAL_ROOT" -name "teqlif_*" \
    -mtime "+${BACKUP_RETENTION_LOCAL_DAYS}" -delete -print 2>/dev/null | wc -l)
echo -e "  Local  (>${BACKUP_RETENTION_LOCAL_DAYS}g): ${LOCAL_DEL} dosya silindi"

# Remote: 7 gün (veya BACKUP_RETENTION_REMOTE_DAYS)
if [[ "$RSYNC_OK" == true ]]; then
    REMOTE_DEL=$(ssh \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout=15 \
        -o BatchMode=yes \
        "${BACKUP_REMOTE_USER}@${BACKUP_REMOTE_HOST}" \
        "find '${BACKUP_REMOTE_PATH}/${HOSTNAME}' -name 'teqlif_*' \
         -mtime '+${BACKUP_RETENTION_REMOTE_DAYS}' \
         -delete -print 2>/dev/null | wc -l" 2>/dev/null || echo "?")
    echo -e "  Remote (>${BACKUP_RETENTION_REMOTE_DAYS}g): ${REMOTE_DEL} dosya silindi"
fi
echo ""

# ════════════════════════════════════════════════════════════════════════════
# Özet
# ════════════════════════════════════════════════════════════════════════════
echo -e "$SEP"
echo -e "${BOLD}${CYAN}  BACKUP ÖZET${RESET}"
echo -e "$SEP"

printf "  ${BOLD}%-12s${RESET} %s\n" "Node"    "$HOSTNAME"
printf "  ${BOLD}%-12s${RESET} %s\n" "Zaman"   "$TIMESTAMP"
printf "  ${BOLD}%-12s${RESET} %s\n" "Rsync"   "$( [[ $RSYNC_OK == true ]] && echo "✓ ${BACKUP_REMOTE_HOST}" || echo "✗ atlandı" )"
echo -e "  ─────────────────────────────────────────────────────────────"

for item in "${BACKED_UP[@]}"; do
    echo -e "  ${GREEN}✓${RESET}  $item"
done
for item in "${SKIPPED[@]}"; do
    echo -e "  ${YELLOW}⊘${RESET}  $item"
done
for item in "${FAILED[@]}"; do
    echo -e "  ${RED}✗${RESET}  $item"
done

echo -e "$SEP"
echo ""

# Telegram özeti
if [[ ${#FAILED[@]} -gt 0 ]]; then
    ICON="🟡"; STATUS="KISMI BAŞARILI"
else
    ICON="✅"; STATUS="BAŞARILI"
fi

_TG_BACKED=$(printf '✓ %s\n' "${BACKED_UP[@]}" 2>/dev/null | head -10 || true)
_TG_FAILED=$(printf '✗ %s\n' "${FAILED[@]}"   2>/dev/null | head -5  || true)
_TG_RSYNC="rsync: $( [[ $RSYNC_OK == true ]] && echo "✓ ${BACKUP_REMOTE_HOST}" || echo "✗" )"

_telegram "${ICON} <b>teqlif-backup ${STATUS}</b> · ${HOSTNAME}
${TIMESTAMP}
${_TG_BACKED}
${_TG_FAILED:-}
${_TG_RSYNC}
Temizlik → local: ${LOCAL_DEL:-0} dosya"
