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

# restic-rest-server yapılandırılmamışsa sessizce çık
if [[ -z "${RESTIC_REST_USER:-}" ]] || [[ -z "${RESTIC_REST_PASSWORD:-}" ]] || [[ -z "${RESTIC_PASSWORD:-}" ]]; then
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) offsite_sync: SKIP — RESTIC_REST_USER/PASSWORD/RESTIC_PASSWORD tanımlı değil"
    exit 0
fi

# minio_backup.sh'nin bu gün başarıyla tamamlandığını doğrula (3-2-1 bütünlük garantisi)
# .last_backup_ok 2 saatten eskiyse ILM acil moda girmiş olabilir — offsite'ı durdur
_MINIO_OK="/project/teqlif/backups/minio/.last_backup_ok"
if [[ ! -f "${_MINIO_OK}" ]]; then
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) offsite_sync: FAIL — ${_MINIO_OK} bulunamadı (minio_backup hiç çalışmadı?)"
    exit 1
fi
_minio_age=$(( $(date +%s) - $(stat -c %Y "${_MINIO_OK}") ))
if [[ ${_minio_age} -gt 7200 ]]; then
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) offsite_sync: FAIL — minio_backup ${_minio_age}s önce tamamlandı (eşik: 7200s) — ILM acil moda geçti mi?"
    exit 1
fi

export RESTIC_REPOSITORY="rest:http://${RESTIC_REST_USER}:${RESTIC_REST_PASSWORD}@10.10.0.101:8000/${RESTIC_REST_USER}/"
export RESTIC_PASSWORD
export RESTIC_CACHE_DIR=/project/teqlif/backups/.restic-cache
export TMPDIR=/project/teqlif/backups/.restic-tmp
mkdir -p "${RESTIC_CACHE_DIR}" "${TMPDIR}"

# ── daily-full snapshot ───────────────────────────────────────────────────────
# Tüm kritik uygulama verisi: pg_dump + minio + stalwart + redis +
# pg_basebackup + clickhouse + uptime_kuma + nodeMonitor teqlif-config
restic backup \
    /project/teqlif/backups/pg_dump \
    /project/teqlif/backups/minio \
    /project/teqlif/backups/stalwart \
    /project/teqlif/backups/redis \
    /project/teqlif/backups/pg_basebackup \
    /project/teqlif/backups/clickhouse \
    /project/teqlif/backups/uptime_kuma \
    /project/teqlif/backups/nodemonitor_config/teqlif-config \
    --tag daily-full \
    --pack-size 32 \
    --compression max \
    --exclude "*.tmp" \
    --exclude ".restic-*"

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) offsite_sync: daily-full snapshot OK"

# ── job_ok Redis kaydı ────────────────────────────────────────────────────────
redis-cli -h 10.10.0.1 -p 6379 -a "${CORE_REDIS_PASS:-}" --no-auth-warning \
    HSET teqlif:agent:job_ok offsite_sync "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >/dev/null 2>&1 || true

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) offsite_sync: tamamlandı"
