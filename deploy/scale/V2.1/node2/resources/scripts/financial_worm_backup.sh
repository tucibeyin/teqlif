#!/bin/bash
# financial_worm_backup.sh — TTK/VUK/MASAK uyumlu aylık finansal WORM arşivi
# Zamanlama: her ayın 1'i 07:30 UTC (teqlif-financial-worm.timer)
# Tablolar: wallet_ledger, withdrawal_requests, purchases, audit_logs (1y+ eski)
# Çıktı: JSONL + SHA-256 manifest → restic --tag financial-worm → node101

set -euo pipefail
source /project/teqlif/config/.env.backup

ARCHIVE_MONTH=$(date -u +%Y-%m)
ARCHIVE_DIR=/project/teqlif/backups/financial_archives/${ARCHIVE_MONTH}
mkdir -p "${ARCHIVE_DIR}"
exec >> "${ARCHIVE_DIR}/backup.log" 2>&1

TS() { date -u +%Y-%m-%dT%H:%M:%SZ; }
echo "$(TS) financial_worm: başlıyor — ${ARCHIVE_MONTH}"

PGHOST=10.10.0.1
PGPORT=5432
PGUSER=teqlif
PGDATABASE=teqlif

# 1 yıldan eski satırlar (zaman damgası sütunu her tabloda created_at)
CUTOFF=$(date -u -d "1 year ago" +%Y-%m-%dT%H:%M:%SZ)

export_table() {
    local table="$1"
    local dest="${ARCHIVE_DIR}/${table}.jsonl"

    # Tablo varlık kontrolü — henüz oluşturulmamış tabloları atlar
    local exists
    exists=$(PGPASSWORD="${TEQLIF_DB_PASSWORD}" psql \
        -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" -d "${PGDATABASE}" \
        -t -A \
        -c "SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='${table}'" 2>/dev/null || true)

    if [[ "${exists}" != "1" ]]; then
        echo "$(TS) financial_worm: ${table} tablosu bulunamadı — boş dosya oluşturuluyor"
        touch "${dest}"
        return
    fi

    echo "$(TS) financial_worm: ${table} dışa aktarılıyor (cutoff=${CUTOFF})..."
    PGPASSWORD="${TEQLIF_DB_PASSWORD}" psql \
        -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" -d "${PGDATABASE}" \
        -t -A \
        -c "COPY (SELECT row_to_json(t) FROM ${table} t WHERE created_at < '${CUTOFF}'::timestamptz ORDER BY created_at) TO STDOUT" \
        > "${dest}"

    local count
    count=$(wc -l < "${dest}")
    echo "$(TS) financial_worm: ${table} → ${count} satır"
}

export_table wallet_ledger
export_table withdrawal_requests
export_table purchases
export_table audit_logs

# SHA-256 manifest
echo "$(TS) financial_worm: SHA-256 manifest oluşturuluyor..."
cd "${ARCHIVE_DIR}"
sha256sum wallet_ledger.jsonl withdrawal_requests.jsonl purchases.jsonl audit_logs.jsonl \
    > manifest.sha256
echo "$(TS) financial_worm: manifest hazır"
cat manifest.sha256

# Restic backup — financial-worm tag, --append-only repoya yazar
export RESTIC_REPOSITORY="rest:http://${RESTIC_REST_USER}:${RESTIC_REST_PASSWORD}@10.10.0.101:8000/${RESTIC_REST_USER}/"
export RESTIC_PASSWORD
export RESTIC_CACHE_DIR=/project/teqlif/backups/.restic-cache
export TMPDIR=/project/teqlif/backups/.restic-tmp
mkdir -p "${RESTIC_CACHE_DIR}" "${TMPDIR}"

echo "$(TS) financial_worm: restic backup başlıyor..."
/usr/bin/restic backup \
    "${ARCHIVE_DIR}" \
    --tag financial-worm \
    --pack-size 32 \
    --compression max

SNAP=$(/usr/bin/restic snapshots --tag financial-worm --json --latest 1 \
    | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[0]['id'][:8])" 2>/dev/null \
    || echo "unknown")
echo "$(TS) financial_worm: snapshot=${SNAP}"

# Doğrulama: manifest SHA-256 kontrolü
echo "$(TS) financial_worm: manifest doğrulanıyor..."
sha256sum --check manifest.sha256
echo "$(TS) financial_worm: manifest doğrulama geçti"

# Job OK sinyali — teqlif:agent:job_ok
redis-cli -h 10.10.0.1 -p 6379 -a "${CORE_REDIS_PASS:-}" --no-auth-warning \
    HSET teqlif:agent:job_ok financial_worm "$(TS)" >/dev/null 2>&1 || true

echo "$(TS) financial_worm: tamamlandı (ay=${ARCHIVE_MONTH} snapshot=${SNAP})"
