#!/bin/bash
# bootstrap_gateway2.sh — teqlif V2.0 Gateway #2 (Deluxhost AMS, 10.10.0.9)
# Çalıştır: sudo bash bootstrap_gateway2.sh

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

NODE_ID="gateway2"
WG_IP="10.10.0.9"
REPO_DIR="${REPO_DIR:-/var/www/teqlif.com}"
NODE_DIR="${REPO_DIR}/deploy/scale/V2.0/${NODE_ID}"

main() {
    check_root
    check_debian
    echo -e "${BOLD}${CYAN}teqlif V2.0 — ${NODE_ID} bootstrap (${WG_IP})${NC}"

    install_base_packages
    setup_user "${SSH_PUBKEY:-}"
    setup_directories
    setup_ntp
    setup_autoupdates
    setup_limits
    clone_repo "${REPO_DIR}"
    setup_logrotate    "${NODE_DIR}"
    setup_auditd       "${NODE_DIR}"
    setup_thp_disable  "${NODE_DIR}"
    setup_fail2ban     "${NODE_DIR}"
    setup_node_conf    "${NODE_DIR}"
    setup_wg_keygen
    setup_wg_config    "${NODE_DIR}"
    setup_wg_sudoers   "${NODE_DIR}"
    setup_guardian_sudoers "${NODE_DIR}"
    setup_sysctl "${NODE_DIR}"
    ufw_gateway
    setup_nginx "${NODE_DIR}"
    install_promtail
    setup_promtail "${NODE_DIR}" "${NODE_ID}"
    setup_guardian "${NODE_DIR}"

    print_summary "${NODE_ID}" "${WG_IP}" \
        "wg0.conf peer <PublicKey> placeholder'larını doldur" \
        "CF Origin Certificate'i /etc/ssl/teqlif/cf-origin.{crt,key} konumuna kopyala" \
        "nginx sites config'i kontrol et: /etc/nginx/sites-available/gateway" \
        "wg-quick up wg0  →  systemctl enable --now wg-quick@wg0" \
        "systemctl start teqlif-guardian" \
        "nginx -t && systemctl reload nginx"
}

ufw_gateway() {
    log_step "UFW (gateway)"
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 22/tcp
    ufw allow 51820/udp
    ufw allow in on wg0 from 10.10.0.0/24
    ufw allow in on wg0 proto udp to any port 9901
    for cidr in \
        103.21.244.0/22 103.22.200.0/22 103.31.4.0/22 \
        104.16.0.0/13 104.24.0.0/14 108.162.192.0/18 \
        131.0.72.0/22 141.101.64.0/18 162.158.0.0/15 \
        172.64.0.0/13 173.245.48.0/20 188.114.96.0/20 \
        190.93.240.0/20 197.234.240.0/22 198.41.128.0/17; do
        ufw allow proto tcp from "${cidr}" to any port 80,443
    done
    ufw_enable
}

setup_nginx() {
    local node_dir="${1}"
    log_step "nginx"
    apt-get install -y -qq nginx
    mkdir -p /etc/systemd/system/nginx.service.d
    cat > /etc/systemd/system/nginx.service.d/restart.conf <<'EOF'
[Service]
Restart=always
RestartSec=5
EOF
    mkdir -p /etc/ssl/teqlif
    chmod 700 /etc/ssl/teqlif
    local nginx_src="${node_dir}/resources/nginx"
    [ -d "${nginx_src}" ] && cp -r "${nginx_src}"/* /etc/nginx/ 2>/dev/null || true
    systemctl daemon-reload
    systemctl enable nginx
    log_ok "nginx kuruldu"
}

main "$@"
