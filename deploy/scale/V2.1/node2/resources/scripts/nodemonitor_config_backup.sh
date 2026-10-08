#!/bin/bash
# nodeMonitor config dosyalarının backup'ı (kalıcı — süresi dolmaz).
#
# Kapsam:
#   /project/teqlif/config/     — teqlif servis konfigürasyonu
#   /opt/monitor/teqlif/        — Prometheus, Loki, Grafana, Alertmanager
set -euo pipefail

BACKUP_DIR=/project/teqlif/backups/nodemonitor_config
LOGFILE=/project/teqlif/logs/nodemonitor_config_backup.log

install -d "${BACKUP_DIR}"
exec >> "${LOGFILE}" 2>&1
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) nodemonitor_config_backup: start"

rsync_from_nodemonitor() {
    local src="$1"
    local dest="$2"
    install -d "${dest}"
    rsync -az \
        --delete \
        -e "ssh -i /home/tucibeyin/.ssh/id_ed25519 -o StrictHostKeyChecking=no" \
        tucibeyin@10.10.0.99:"${src}" \
        "${dest}/"
}

# teqlif servis config (env dosyaları, sertifikalar, vb.)
rsync_from_nodemonitor "/project/teqlif/config/" "${BACKUP_DIR}/teqlif-config"

# Monitoring stack config (prometheus.yml, loki.yml, grafana.ini, vb.)
rsync_from_nodemonitor "/opt/monitor/teqlif/" "${BACKUP_DIR}/monitor-config"

USED=$(du -sh "${BACKUP_DIR}" 2>/dev/null | cut -f1 || echo "?")
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) nodemonitor_config_backup: tamamlandı (${USED})"
logger "teqlif nodemonitor_config_backup: tamamlandı (${USED})"
