#!/bin/bash
# bootstrap_node3.sh — teqlif V2.1 LiveKit Streaming #1 (OVH Frankfurt DE, 10.10.0.3)
# KVM VPS, UDP-yoğun

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

NODE_ID="node3"
WG_IP="10.10.0.3"
REPO_DIR="${REPO_DIR:-/var/www/teqlif.com}"
NODE_DIR="${REPO_DIR}/deploy/scale/V2.1/${NODE_ID}"
SECRETS_FILE="${SECRETS_FILE:-}"
LIVEKIT_VER="${LIVEKIT_VER:-v1.7.2}"

main() {
    check_root
    check_debian
    echo -e "${BOLD}${CYAN}teqlif V2.1 — ${NODE_ID} bootstrap (${WG_IP}) [STREAMING]${NC}"

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
    ufw_streaming
    install_livekit
    setup_livekit      "${NODE_DIR}"
    install_certbot
    install_promtail
    setup_promtail "${NODE_DIR}" "${NODE_ID}"
    install_node_exporter

    if [ -n "${SECRETS_FILE:-}" ]; then
        apply_secrets "${SECRETS_FILE}" /project/teqlif/config /etc/wireguard
    fi

    print_summary "${NODE_ID}" "${WG_IP}" \
        "wg_mesh_apply.sh çalıştır" \
        "wg-quick up wg0 && systemctl enable wg-quick@wg0" \
        "certbot certonly --standalone -d stream.teqlif.com (LE cert)" \
        "systemctl start teqlif-livekit"
}

ufw_streaming() {
    log_step "UFW (streaming)"
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 22/tcp
    ufw allow 51820/udp
    ufw allow 443/tcp
    ufw allow 443/udp
    ufw allow 3478/udp
    ufw allow 50000:60000/udp
    # LiveKit API sadece WG'den
    ufw allow in on wg0 from 10.10.0.0/24 to any port 7880 proto tcp
    ufw allow in on wg0 from 10.10.0.0/24 to any port 7881 proto tcp
    ufw_enable
}

install_livekit() {
    log_step "LiveKit Server (${LIVEKIT_VER})"
    curl -fsSL "https://github.com/livekit/livekit/releases/download/${LIVEKIT_VER}/livekit_linux_amd64.tar.gz" \
        | tar xz -C /tmp/
    mv /tmp/livekit-server /usr/local/bin/livekit-server
    chmod +x /usr/local/bin/livekit-server
    log_ok "LiveKit ${LIVEKIT_VER} kuruldu"
}

setup_livekit() {
    local node_dir="${1}"
    log_step "LiveKit config"
    mkdir -p /project/teqlif/config /project/teqlif/logs/livekit
    cp "${node_dir}/resources/livekit/livekit.yaml" /project/teqlif/config/livekit.yaml
    cp "${node_dir}/systemd/teqlif-livekit.service" /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable teqlif-livekit
    log_ok "teqlif-livekit enable edildi"
}

install_certbot() {
    log_step "Certbot"
    apt-get install -y -qq certbot
    log_ok "Certbot kuruldu"
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
ExecStart=/usr/local/bin/node_exporter --web.listen-address=10.10.0.3:9100
Restart=always
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now node-exporter
    log_ok "node_exporter aktif (10.10.0.3:9100)"
}

main "$@"
