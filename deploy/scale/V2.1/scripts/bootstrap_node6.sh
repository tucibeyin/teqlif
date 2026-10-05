#!/bin/bash
# bootstrap_node6.sh — teqlif V2.1 AI Primary (ZAP Virginia US, 10.10.0.6)
# KVM VPS | Sadece AI Proxy (Gemini kısıtsız erişim için ABD'de)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

NODE_ID="node6"
WG_IP="10.10.0.6"
REPO_DIR="${REPO_DIR:-/var/www/teqlif.com}"
NODE_DIR="${REPO_DIR}/deploy/scale/V2.1/${NODE_ID}"
SECRETS_FILE="${SECRETS_FILE:-}"

main() {
    check_root
    check_debian
    echo -e "${BOLD}${CYAN}teqlif V2.1 — ${NODE_ID} bootstrap (${WG_IP}) [AI PRIMARY]${NC}"

    install_base_packages
    setup_user "${SSH_PUBKEY:-}"
    setup_teqlif_directories
    setup_ntp
    setup_autoupdates
    setup_limits
    setup_swap 4
    clone_repo "${REPO_DIR}"
    setup_logrotate
    setup_auditd
    setup_thp_disable
    setup_fail2ban
    setup_node_conf    "${NODE_DIR}"
    setup_wg_keygen
    setup_wg_config    "${NODE_DIR}"
    setup_wg_sudoers
    setup_sysctl       "${NODE_DIR}"
    ufw_node6
    setup_venv "${REPO_DIR}"
    setup_env_template \
        "${NODE_DIR}/resources/.env.ai-proxy.template" \
        "/project/teqlif/config/.env.ai-proxy"
    setup_ai_proxy_service "${NODE_DIR}"
    install_promtail
    setup_promtail "${NODE_DIR}" "${NODE_ID}"
    install_node_exporter

    if [ -n "${SECRETS_FILE:-}" ]; then
        apply_secrets "${SECRETS_FILE}" /project/teqlif/config /etc/wireguard
    fi

    print_summary "${NODE_ID}" "${WG_IP}" \
        "wg_mesh_apply.sh çalıştır" \
        "wg-quick up wg0 && systemctl enable wg-quick@wg0" \
        "/project/teqlif/config/.env.ai-proxy içindeki API key'leri doldur" \
        "systemctl start teqlif-ai-proxy" \
        "node1'den test: curl http://10.10.0.6:8001/health"
}

ufw_node6() {
    log_step "UFW (node6 — AI Primary)"
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 22/tcp
    ufw allow 51820/udp
    # AI Proxy sadece WG mesh'ten (node1 çağırır)
    ufw allow in on wg0 from 10.10.0.0/24 to any port 8001 proto tcp
    ufw_enable
}

setup_ai_proxy_service() {
    local node_dir="${1}"
    log_step "AI Proxy Primary servis"
    cp "${node_dir}/systemd/teqlif-ai-proxy.service" /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable teqlif-ai-proxy
    log_ok "teqlif-ai-proxy enable edildi"
}

install_node_exporter() {
    log_step "node_exporter"
    local VER="1.8.2"
    curl -fsSL "https://github.com/prometheus/node_exporter/releases/download/v${VER}/node_exporter-${VER}.linux-amd64.tar.gz" \
        | tar xz -C /tmp/
    mv "/tmp/node_exporter-${VER}.linux-amd64/node_exporter" /usr/local/bin/
    cat > /etc/systemd/system/node-exporter.service <<EOF
[Unit]
Description=Prometheus Node Exporter
[Service]
Type=simple
User=tucibeyin
ExecStart=/usr/local/bin/node_exporter --web.listen-address=10.10.0.6:9100
Restart=always
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now node-exporter
    log_ok "node_exporter aktif (10.10.0.6:9100)"
}

main "$@"
