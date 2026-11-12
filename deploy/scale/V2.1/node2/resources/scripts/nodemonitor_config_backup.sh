#!/bin/bash
# nodeMonitor config dosyalarının backup'ı (kalıcı — süresi dolmaz).
#
# Kapsam:
#   /project/teqlif/config/     — teqlif servis konfigürasyonu (env, certs, secrets)
#   /project/shared/config/     — Grafana + Uptime Kuma paylaşımlı config (grafana.ini, .env)
#   /opt/monitor/teqlif/        — Prometheus/Loki/Alertmanager config dosyaları
#   /opt/monitor/shared/grafana/data/  — grafana.db (dashboard, alert, user) + diğerleri
#
# KAPSAM DIŞI (bilinçli):
#   prometheus/data/            — TSDB (30 günlük, onlarca GB)
#   loki/data,wal,tsdb-*/       — Loki runtime (loki_backup.sh'de chunks + compactor)
#   grafana/data/plugins/       — Paket verileri (grafana.ini'den yeniden yüklenebilir)
#   grafana/data/logs/          — Log dosyaları
#   Git repo'su içindeki yml dosyaları zaten sürüm kontrolünde;
#   burada yalnızca runtime secrets, Grafana DB ve statik config korunur.
set -euo pipefail

source /project/teqlif/config/.env.backup

BACKUP_DIR=/project/teqlif/backups/nodemonitor_config
LOGFILE=/project/teqlif/logs/nodemonitor_config_backup.log

install -d "${BACKUP_DIR}"
exec >> "${LOGFILE}" 2>&1
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) nodemonitor_config_backup: start"

rsync_from_nodemonitor() {
    local src="$1"
    local dest="$2"
    shift 2
    install -d "${dest}"
    rsync -az \
        --delete \
        --delete-excluded \
        "$@" \
        -e "ssh -i /home/tucibeyin/.ssh/id_ed25519 -o StrictHostKeyChecking=no" \
        tucibeyin@10.10.0.99:"${src}" \
        "${dest}/"
}

# teqlif servis config (env dosyaları, sertifikalar, vb.)
rsync_from_nodemonitor "/project/teqlif/config/" "${BACKUP_DIR}/teqlif-config"

# Paylaşımlı servis config — grafana.ini, uptime-kuma.env
rsync_from_nodemonitor "/project/shared/config/" "${BACKUP_DIR}/shared-config"

# Monitoring stack config — TSDB, WAL ve index cache dizinleri hariç
rsync_from_nodemonitor "/opt/monitor/teqlif/" "${BACKUP_DIR}/monitor-config" \
    --exclude 'prometheus/data/' \
    --exclude 'loki/data/' \
    --exclude 'loki/wal/' \
    --exclude 'loki/tsdb-shipper-active/' \
    --exclude 'loki/tsdb-shipper-cache/'

# Grafana veritabanı — dashboardlar, alertler, kullanıcılar, veri kaynakları
# Plugins (509MB) ve logs yedeksiz; grafana.ini shared-config'de.
# grafana.db WAL modunda: ana dosya her zaman commit'lenmiş transaksiyonları içerir.
rsync_from_nodemonitor "/opt/monitor/shared/grafana/data/" "${BACKUP_DIR}/grafana" \
    --exclude 'plugins/' \
    --exclude 'logs/'

USED=$(du -sh "${BACKUP_DIR}" 2>/dev/null | cut -f1 || echo "?")
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) nodemonitor_config_backup: tamamlandı (${USED})"
touch "${BACKUP_DIR}/.last_backup_ok"
logger "teqlif nodemonitor_config_backup: tamamlandı (${USED})"
redis-cli -h 10.10.0.1 -p 6379 -a "${CORE_REDIS_PASS}" --no-auth-warning HSET teqlif:agent:job_ok nodemonitor_config_backup "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >/dev/null 2>&1 || true
