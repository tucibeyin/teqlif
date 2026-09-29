#!/bin/bash
# bootstrap_node1.sh — teqlif V2.0 Stream #1 / LiveKit (10.10.0.1)
# Çalıştır: sudo bash bootstrap_node1.sh

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

NODE_ID="node1"
WG_IP="10.10.0.1"
REPO_DIR="${REPO_DIR:-/var/www/teqlif.com}"
NODE_DIR="${REPO_DIR}/deploy/scale/V2.0/${NODE_ID}"
LIVEKIT_VER="${LIVEKIT_VER:-v1.7.2}"

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
    ufw_stream
    setup_livekit "${NODE_DIR}"
    install_promtail
    setup_promtail "${NODE_DIR}" "${NODE_ID}"
    setup_guardian "${NODE_DIR}"

    print_summary "${NODE_ID}" "${WG_IP}" \
        "wg0.conf peer <PublicKey> placeholder'larını doldur" \
        "/etc/livekit/livekit.yaml içindeki <placeholder>'ları doldur (Redis pass, API key/secret)" \
        "CF Origin cert: /etc/ssl/teqlif/cf-origin.{crt,key}" \
        "wg-quick up wg0  →  systemctl enable --now wg-quick@wg0" \
        "systemctl start livekit teqlif-guardian"
}

ufw_stream() {
    log_step "UFW (stream/LiveKit)"
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 22/tcp
    ufw allow 51820/udp
    ufw allow in on wg0 from 10.10.0.0/24
    ufw allow in on wg0 proto udp to any port 9901
    ufw allow 7880/tcp
    ufw allow 7881/tcp
    ufw allow 7882/udp
    ufw allow 3478/udp
    ufw allow 5349/tcp
    ufw allow 50000:60000/udp
    ufw_enable
}

setup_livekit() {
    local node_dir="${1}"
    log_step "LiveKit ${LIVEKIT_VER}"
    if ! command -v livekit-server &>/dev/null; then
        curl -fsSL \
            "https://github.com/livekit/livekit/releases/download/${LIVEKIT_VER}/livekit_linux_amd64.tar.gz" \
            | tar -xz -C /usr/local/bin livekit-server
        chmod 755 /usr/local/bin/livekit-server
        log_ok "livekit-server ${LIVEKIT_VER} kuruldu"
    else
        log_info "livekit-server zaten mevcut"
    fi
    mkdir -p /etc/livekit /etc/ssl/teqlif
    chmod 700 /etc/ssl/teqlif
    local yaml_src="${node_dir}/resources/livekit/livekit.yaml"
    if [ -f "${yaml_src}" ]; then
        cp "${yaml_src}" /etc/livekit/livekit.yaml
        log_ok "livekit.yaml kopyalandı"
    fi
    cp "${node_dir}/systemd/livekit.service" /etc/systemd/system/livekit.service
    # Guardian sudoers ek: livekit
    cat >> /etc/sudoers.d/guardian-systemctl <<'EOF'
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/systemctl start livekit
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop livekit
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart livekit
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/systemctl reset-failed livekit
EOF
    chmod 440 /etc/sudoers.d/guardian-systemctl
    systemctl daemon-reload
    systemctl enable livekit
    log_ok "livekit.service enable edildi (yaml doldurulunca: systemctl start livekit)"
}

main "$@"
