#!/bin/bash
# bootstrap_nodemonitor.sh — teqlif V2.1 Monitor (10.10.0.99)
# VPS | Grafana + Prometheus + Loki + Alertmanager + Uptime Kuma
# Çalıştır: sudo bash bootstrap_nodemonitor.sh
# Ortam: SECRETS_FILE=/tmp/teqlif-secrets.env SSH_PUBKEY="ssh-ed25519 ..."
# NOT: SSH sadece WireGuard üzerinde (10.10.0.99:22) — dışarıdan doğrudan erişim yok.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

NODE_ID="nodeMonitor"
WG_IP="10.10.0.99"
REPO_DIR="${REPO_DIR:-/var/www/teqlif.com}"
NODE_DIR="${REPO_DIR}/deploy/scale/V2.1/${NODE_ID}"
SECRETS_FILE="${SECRETS_FILE:-}"

GRAFANA_VERSION="${GRAFANA_VERSION:-11.6.1}"
LOKI_VERSION="${LOKI_VERSION:-3.4.3}"
ALERTMANAGER_VERSION="${ALERTMANAGER_VERSION:-0.28.1}"
PROMETHEUS_VERSION="${PROMETHEUS_VERSION:-3.2.1}"

main() {
    check_root
    check_debian
    echo -e "${BOLD}${CYAN}teqlif V2.1 — ${NODE_ID} bootstrap (${WG_IP}) [MONITORING]${NC}"

    install_base_packages
    setup_user "${SSH_PUBKEY:-}"
    setup_teqlif_directories
    setup_ntp
    setup_autoupdates
    clone_repo "${REPO_DIR}"
    setup_logrotate
    setup_wg_keygen
    setup_wg_config    "${NODE_DIR}"
    setup_wg_sudoers
    ufw_nodemonitor
    install_grafana
    install_prometheus
    install_loki
    install_alertmanager
    install_uptime_kuma
    setup_monitoring_services "${NODE_DIR}"
    fix_grafana_defaults
    install_node_exporter "${WG_IP}"
    setup_teqlif_agent "${NODE_DIR}"
    finalize
}

# ── UFW — sadece WireGuard, SSH internete kapalı ──────────────────────────────
ufw_nodemonitor() {
    log_step "UFW (nodeMonitor — WireGuard-only)"
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 51820/udp comment 'WireGuard'
    ufw allow in on wg0 from 10.10.0.0/24 comment 'WireGuard cluster'
    ufw_enable
    log_ok "UFW aktif — internetten tüm portlar kapalı"
}

# ── Grafana defaults düzeltmesi ───────────────────────────────────────────────
# /etc/default/grafana-server paket güncellemelerinde CONF_FILE'ı sıfırlayabilir.
# Bu fonksiyon her bootstrap'te canonical değeri garantiler.
fix_grafana_defaults() {
    log_step "Grafana defaults"
    local defaults_file="/etc/default/grafana-server"
    if [ -f "${defaults_file}" ]; then
        sed -i 's|CONF_FILE=.*|CONF_FILE=/project/shared/config/grafana.ini|' "${defaults_file}"
    fi
    log_ok "CONF_FILE → /project/shared/config/grafana.ini"
}

# ── Monitoring servisleri ─────────────────────────────────────────────────────
setup_monitoring_services() {
    local node_dir="${1}"
    log_step "Monitoring systemd servisleri"
    local systemd_dir="${node_dir}/systemd"
    for svc in teqlif-prometheus teqlif-loki teqlif-alertmanager uptime-kuma node-exporter teqlif-agent; do
        if [ -f "${systemd_dir}/${svc}.service" ]; then
            cp "${systemd_dir}/${svc}.service" /etc/systemd/system/
        fi
    done
    # Config dosyaları → /project/shared/config/
    install -d /project/shared/config
    cp "${node_dir}/config/shared/grafana.ini" /project/shared/config/grafana.ini
    systemctl daemon-reload
    systemctl enable --now teqlif-prometheus teqlif-loki teqlif-alertmanager uptime-kuma grafana-server
    log_ok "Monitoring servisleri aktif"
}

finalize() {
    log_ok "nodeMonitor bootstrap tamamlandı"
    echo ""
    echo "  Grafana:       http://10.10.0.99:3000  (SSH tunnel ile eriş)"
    echo "  Prometheus:    http://10.10.0.99:9090"
    echo "  Loki:          http://10.10.0.99:3100"
    echo "  Uptime Kuma:   http://10.10.0.99:3001"
    echo ""
    echo "  SSH tunnel:    ssh -N monitor-tunnel"
}

main "$@"
