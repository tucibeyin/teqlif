#!/bin/bash
# bootstrap_streaming_generic.sh — teqlif V2.1 Plug-and-Play Streaming Node
# add_streaming_node.sh tarafından çağrılır. Doğrudan çalıştırılmaz.
#
# Ortam değişkenleri (add_streaming_node.sh tarafından set edilir):
#   STREAMING_WG_IP   — yeni node'un WG IP'si (örn: 10.10.0.20)
#   NODE_ID           — node ismi (örn: stream-3)
#   SECRETS_FILE      — /project/teqlif/config altındaki placeholder'ları doldurur (isteğe bağlı)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

: "${STREAMING_WG_IP:?STREAMING_WG_IP belirtilmeli}"
: "${NODE_ID:?NODE_ID belirtilmeli}"

WG_IP="${STREAMING_WG_IP}"
REPO_DIR="${REPO_DIR:-/var/www/teqlif.com}"
# Template olarak node3 config'ini kullan
TEMPLATE_NODE_DIR="${REPO_DIR}/deploy/scale/V2.1/node3"
LIVEKIT_VER="${LIVEKIT_VER:-v1.7.2}"

main() {
    check_root
    check_debian
    echo -e "${BOLD}${CYAN}teqlif V2.1 — ${NODE_ID} bootstrap (${WG_IP}) [STREAMING GENERIC]${NC}"

    install_base_packages
    setup_teqlif_directories
    setup_ntp
    setup_autoupdates
    setup_limits
    setup_swap 4
    # Repo zaten klonlanmış (add_streaming_node.sh kontrolü sağladı)
    setup_logrotate
    setup_auditd
    setup_thp_disable
    setup_fail2ban
    setup_node_conf_generic
    setup_wg_keygen
    setup_wg_config_generic
    setup_wg_sudoers
    setup_sysctl "${TEMPLATE_NODE_DIR}"
    ufw_streaming
    install_livekit
    setup_livekit_generic
    install_certbot
    install_promtail
    setup_promtail_generic
    install_node_exporter_generic

    if [ -n "${SECRETS_FILE:-}" ]; then
        apply_secrets "${SECRETS_FILE}" /project/teqlif/config /etc/wireguard
    fi

    echo ""
    log_ok "Bootstrap tamamlandı: ${NODE_ID} (${WG_IP})"
    log_info "WG pubkey: $(cat /etc/wireguard/pubkey)"
}

# node.conf'u dinamik olarak yaz (template node3'tekini override et)
setup_node_conf_generic() {
    log_step "Node config (${NODE_ID})"
    cat > /project/teqlif/config/node.conf <<EOF
NODE_ID=${NODE_ID}
WG_IP=${WG_IP}
PUBLIC_IP=$(curl -s https://ifconfig.me || hostname -I | awk '{print $1}')
ROLE=streaming
PROVIDER=generic
TYPE=kvm
EOF
    log_ok "/project/teqlif/config/node.conf yazıldı"
}

# wg0.conf'u node3 template'inden alıp bu node'un IP'siyle yaz
setup_wg_config_generic() {
    log_step "WireGuard config (${NODE_ID}, ${WG_IP})"
    local template="${TEMPLATE_NODE_DIR}/resources/wireguard/wg0.conf"
    if [ ! -f "${template}" ]; then
        log_err "WG template bulunamadı: ${template}"
        exit 1
    fi
    cp "${template}" /etc/wireguard/wg0.conf
    # Bu node'un WG IP'sini ve private key'i ayarla
    PRIVKEY="$(cat /etc/wireguard/privkey)"
    sed -i "s|Address = 10\.10\.0\.3/24|Address = ${WG_IP}/24|g" /etc/wireguard/wg0.conf
    sed -i "s|<privatekey>|${PRIVKEY}|g" /etc/wireguard/wg0.conf
    chmod 600 /etc/wireguard/wg0.conf
    log_ok "wg0.conf kopyalandı"
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

# livekit.yaml'ı node3 template'inden kopyala (Redis adresi aynı: node1 core redis db=1)
setup_livekit_generic() {
    log_step "LiveKit config (${NODE_ID})"
    cp "${TEMPLATE_NODE_DIR}/resources/livekit/livekit.yaml" /project/teqlif/config/livekit.yaml
    mkdir -p /project/teqlif/logs/livekit
    cat > /etc/systemd/system/teqlif-livekit.service <<EOF
[Unit]
Description=teqlif LiveKit Streaming (${NODE_ID})
After=network.target wg-quick@wg0.service
Wants=wg-quick@wg0.service
[Service]
Type=simple
User=tucibeyin
ExecStart=/usr/local/bin/livekit-server --config /project/teqlif/config/livekit.yaml
Restart=always
RestartSec=5
LimitNOFILE=65535
StandardOutput=append:/project/teqlif/logs/livekit/livekit.log
StandardError=append:/project/teqlif/logs/livekit/livekit.log
SupplementaryGroups=systemd-journal adm
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable teqlif-livekit
    log_ok "teqlif-livekit enable edildi"
}

install_certbot() {
    apt-get install -y -qq certbot
}

setup_promtail_generic() {
    log_step "Promtail (${NODE_ID})"
    # node3 promtail config'ini kullan, node id'yi değiştir
    local prom_src="${TEMPLATE_NODE_DIR}/resources/promtail/config.yml"
    mkdir -p /project/teqlif/config/promtail
    if [ -f "${prom_src}" ]; then
        sed "s|node3|${NODE_ID}|g" "${prom_src}" > /project/teqlif/config/promtail/config.yml
    fi
    # Promtail binary ve systemd servis kurulumu _common.sh'daki install_promtail + setup_promtail'dan gelir
    install_promtail
    # Manuel config override
    local prom_conf="/etc/promtail/config.yml"
    [ -f /project/teqlif/config/promtail/config.yml ] && \
        cp /project/teqlif/config/promtail/config.yml "${prom_conf}"
    systemctl restart promtail 2>/dev/null || true
    log_ok "Promtail hazır"
}

install_node_exporter_generic() {
    log_step "node_exporter (${NODE_ID}, ${WG_IP})"
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
ExecStart=/usr/local/bin/node_exporter --web.listen-address=${WG_IP}:9100
Restart=always
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now node-exporter
    log_ok "node_exporter aktif (${WG_IP}:9100)"
}

main "$@"
