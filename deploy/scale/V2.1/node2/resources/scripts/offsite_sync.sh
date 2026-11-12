#!/bin/bash
# offsite_sync.sh — teqlif daily-full backup → node101 (restic)
# Zamanlama: her gün 06:30 UTC (teqlif-offsite-sync.timer)
# pg_dump (03:00) + minio (05:30) tamamlandıktan sonra çalışır.
#
# Ortam değişkenleri /project/teqlif/config/.env.backup'tan gelir:
#   RESTIC_REST_USER     — restic-rest-server HTTP kullanıcı adı
#   RESTIC_REST_PASSWORD — restic-rest-server HTTP parolası
#   RESTIC_PASSWORD      — AES-256 şifreleme parolası (gizli)
#   CORE_REDIS_PASS      — job_ok Redis kaydı için

set -euo pipefail

source /project/teqlif/config/.env.backup

LOGFILE=/project/teqlif/logs/offsite_sync.log
install -d "$(dirname "${LOGFILE}")"
exec >> "${LOGFILE}" 2>&1

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) offsite_sync: start"

# restic-rest-server credentials kontrolü — eksikse fail (OFFSITE_MODE=disabled ile devre dışı bırakılabilir)
if [[ -z "${RESTIC_REST_USER:-}" ]] || [[ -z "${RESTIC_REST_PASSWORD:-}" ]] || [[ -z "${RESTIC_PASSWORD:-}" ]]; then
    if [[ "${OFFSITE_MODE:-}" == "disabled" ]]; then
        echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) offsite_sync: SKIP — OFFSITE_MODE=disabled"
        exit 0
    fi
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) offsite_sync: FAIL — credentials tanımlı değil; OFFSITE_MODE=disabled ile susturulabilir"
    exit 2
fi

# minio_backup.sh staleness kontrolü (3-2-1 bütünlük garantisi)
# .last_backup_ok 12 saatten eskiyse minio bayat — diğer yolların offsite'ını bloklamaz,
# restic tamamlandıktan sonra exit 1 ile OnFailure alarmı tetiklenir.
_MINIO_OK="/project/teqlif/backups/minio/.last_backup_ok"
_stale_minio=0
if [[ ! -f "${_MINIO_OK}" ]]; then
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) offsite_sync: WARN — ${_MINIO_OK} bulunamadı (minio_backup hiç çalışmadı?)"
    _stale_minio=1
else
    _minio_age=$(( $(date +%s) - $(stat -c %Y "${_MINIO_OK}") ))
    if [[ ${_minio_age} -gt 43200 ]]; then
        echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) offsite_sync: WARN — minio_backup ${_minio_age}s önce tamamlandı (eşik: 43200s) — minio bayat, diğer yollar devam ediyor"
        _stale_minio=1
    fi
fi

export RESTIC_REPOSITORY="rest:http://${RESTIC_REST_USER}:${RESTIC_REST_PASSWORD}@10.10.0.101:8000/${RESTIC_REST_USER}/"
export RESTIC_PASSWORD
export RESTIC_CACHE_DIR=/project/teqlif/backups/.restic-cache
export TMPDIR=/project/teqlif/backups/.restic-tmp
mkdir -p "${RESTIC_CACHE_DIR}" "${TMPDIR}"

# ── daily-full snapshot ───────────────────────────────────────────────────────
# Tüm kritik uygulama verisi: pg_dump + pg_basebackup + pg_wal (PITR) +
# minio + clickhouse + redis + loki (chunks+meta) + stalwart + uptime_kuma +
# nodeMonitor (teqlif-config + shared-config + grafana.db) +
# cluster_secrets (tüm node TLS/env — AES-256 şifreli)
restic backup \
    /project/teqlif/backups/pg_dump \
    /project/teqlif/backups/pg_basebackup \
    /project/teqlif/backups/pg_wal \
    /project/teqlif/backups/minio \
    /project/teqlif/backups/clickhouse \
    /project/teqlif/backups/redis \
    /project/teqlif/backups/loki \
    /project/teqlif/backups/stalwart \
    /project/teqlif/backups/uptime_kuma \
    /project/teqlif/backups/nodemonitor_config/teqlif-config \
    /project/teqlif/backups/nodemonitor_config/shared-config \
    /project/teqlif/backups/nodemonitor_config/grafana \
    /project/teqlif/backups/cluster_secrets \
    --tag daily-full \
    --pack-size 32 \
    --compression max \
    --exclude "*.tmp" \
    --exclude "*.partial" \
    --exclude ".last_*" \
    --exclude ".restic-*"

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) offsite_sync: daily-full snapshot OK"

# ── job_ok Redis kaydı ────────────────────────────────────────────────────────
redis-cli -h 10.10.0.1 -p 6379 -a "${CORE_REDIS_PASS:-}" --no-auth-warning \
    HSET teqlif:agent:job_ok offsite_sync "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >/dev/null 2>&1 || true

if [[ ${_stale_minio} -eq 1 ]]; then
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) offsite_sync: FAIL — minio bayattı, snapshot alındı ama minio eksik (OnFailure tetiklendi)"
    exit 1
fi

touch /project/teqlif/backups/.last_offsite_sync_ok
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) offsite_sync: tamamlandı"
