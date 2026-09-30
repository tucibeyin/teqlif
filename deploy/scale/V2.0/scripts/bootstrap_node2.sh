#!/bin/bash
# bootstrap_node2.sh — teqlif V2.0 AI Proxy Primary (10.10.0.3)
# Çalıştır: sudo bash bootstrap_node2.sh

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

NODE_ID="node2"
WG_IP="10.10.0.3"
REPO_DIR="${REPO_DIR:-/var/www/teqlif.com}"
NODE_DIR="${REPO_DIR}/deploy/scale/V2.0/${NODE_ID}"
SECRETS_FILE="${SECRETS_FILE:-}"

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
    ufw_ai_proxy
    setup_venv "${REPO_DIR}"
    setup_env_template \
        "${NODE_DIR}/resources/.env.production.template" \
        "/etc/teqlif/.env.production"
    setup_ai_proxy "${NODE_DIR}"
    install_promtail
    setup_promtail "${NODE_DIR}" "${NODE_ID}"
    setup_guardian "${NODE_DIR}"

    # Secrets uygula (SECRETS_FILE env var verilmişse)
    if [ -n "${SECRETS_FILE:-}" ]; then
        apply_secrets "${SECRETS_FILE}" /etc/teqlif /etc/wireguard
    fi
    print_summary "${NODE_ID}" "${WG_IP}" \
        "wg0.conf peer <PublicKey> placeholder'larını doldur" \
        "/etc/teqlif/.env.production içindeki <placeholder>'ları doldur" \
        "wg-quick up wg0  →  systemctl enable --now wg-quick@wg0" \
        "systemctl start teqlif-ai-proxy teqlif-guardian"
}

ufw_ai_proxy() {
    log_step "UFW (AI proxy — WG only)"
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 22/tcp
    ufw allow 51820/udp
    ufw allow in on wg0 from 10.10.0.0/24
    ufw allow in on wg0 proto udp to any port 9901
    ufw_enable
}

setup_ai_proxy() {
    local node_dir="${1}"
    log_step "AI Proxy servisi"
    cp "${node_dir}/systemd/teqlif-ai-proxy.service" \
       /etc/systemd/system/teqlif-ai-proxy.service
    systemctl daemon-reload
    systemctl enable teqlif-ai-proxy
    log_ok "teqlif-ai-proxy enable edildi"
}

main "$@"
