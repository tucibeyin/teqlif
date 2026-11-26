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
LIVEKIT_VER="${LIVEKIT_VER:-v1.13.7}"

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
    setup_journald
    setup_auditd
    setup_thp_disable
    setup_crowdsec
    setup_node_conf    "${NODE_DIR}"
    setup_wg_keygen
    setup_wg_config    "${NODE_DIR}"
    setup_wg_sudoers
    setup_redis_vip_sudoers_client
    setup_sysctl       "${NODE_DIR}"
    setup_apt_timing
    ufw_streaming
    install_haproxy
    setup_haproxy_redis_proxy "${NODE_DIR}"
    install_livekit
    setup_livekit      "${NODE_DIR}"
    install_certbot
    setup_certbot_hook "${NODE_DIR}"
    install_nginx
    setup_nginx        "${NODE_DIR}"
    install_promtail
    setup_promtail "${NODE_DIR}" "${NODE_ID}"
    install_node_exporter

    if [ -n "${SECRETS_FILE:-}" ]; then
        apply_secrets "${SECRETS_FILE}" /project/teqlif/config /etc/wireguard /etc/haproxy
    fi

    print_summary "${NODE_ID}" "${WG_IP}" \
        "wg_mesh_apply.sh çalıştır" \
        "wg-quick up wg0 && systemctl enable wg-quick@wg0" \
        "certbot certonly --standalone -d stream3.teqlif.com (TURN cert)" \
        "certbot certonly --standalone -d live2.teqlif.com (LiveKit TLS cert)" \
        "systemctl start haproxy" \
        "systemctl start nginx" \
        "systemctl start teqlif-livekit"
}

ufw_streaming() {
    log_step "UFW (streaming)"
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 22/tcp
    ufw allow 51820/udp
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw allow 443/udp
    ufw allow 3478/udp
    ufw allow 50000:60000/udp
    # LiveKit API sadece WG'den
    ufw allow in on wg0 from 10.10.0.0/24 to any port 7880 proto tcp
    ufw allow in on wg0 from 10.10.0.0/24 to any port 7881 proto tcp
    # LiveKit Prometheus metrikleri (prometheus_port: 6789) sadece WG'den
    ufw allow in on wg0 from 10.10.0.0/24 to any port 6789 proto tcp
    ufw_enable
}

install_livekit() {
    log_step "LiveKit Server (${LIVEKIT_VER})"
    curl -fsSL "https://github.com/livekit/livekit/releases/download/${LIVEKIT_VER}/livekit_${LIVEKIT_VER#v}_linux_amd64.tar.gz" \
        | tar xz -C /tmp/
    mv /tmp/livekit-server /usr/local/bin/livekit-server
    chmod +x /usr/local/bin/livekit-server
    log_ok "LiveKit ${LIVEKIT_VER} kuruldu"
}

setup_livekit() {
    local node_dir="${1}"
    log_step "LiveKit config"
    mkdir -p /project/teqlif/config /project/teqlif/logs/livekit
    chown tucibeyin:tucibeyin /project/teqlif/logs/livekit
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

setup_certbot_hook() {
    local node_dir="${1}"
    log_step "Certbot renewal hook (LiveKit cert sync)"
    local hook_dir="/etc/letsencrypt/renewal-hooks/deploy"
    mkdir -p "${hook_dir}"
    cp "${node_dir}/resources/certbot/renewal-hooks/deploy/copy-livekit-certs.sh" \
        "${hook_dir}/copy-livekit-certs.sh"
    chmod 755 "${hook_dir}/copy-livekit-certs.sh"
    log_ok "Certbot hook kuruldu: ${hook_dir}/copy-livekit-certs.sh"
}

install_nginx() {
    log_step "nginx"
    apt-get install -y -qq nginx
    systemctl stop nginx   # certbot --standalone için portu boşalt
    log_ok "nginx kuruldu"
}

setup_nginx() {
    local node_dir="$1"
    log_step "nginx config (live2.teqlif.com)"
    cp "${node_dir}/resources/nginx/nginx.conf" /etc/nginx/nginx.conf
    mkdir -p /etc/nginx/conf.d
    cp "${node_dir}/resources/nginx/conf.d/livekit.conf" /etc/nginx/conf.d/livekit.conf
    mkdir -p /var/www/html
    systemctl enable nginx
    log_ok "nginx config yazıldı (LE cert sonrası: systemctl start nginx)"
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
