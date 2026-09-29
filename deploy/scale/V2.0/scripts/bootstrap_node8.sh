#!/bin/bash
# bootstrap_node8.sh — teqlif V2.0 Storage Secondary / MinIO (OVH SBG, 10.10.0.12)
# Çalıştır: sudo bash bootstrap_node8.sh
# node7 ile özdeş kurulum; Site Replication node7 sonrası yapılır.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

NODE_ID="node8"
WG_IP="10.10.0.12"
REPO_DIR="${REPO_DIR:-/var/www/teqlif.com}"
NODE_DIR="${REPO_DIR}/deploy/scale/V2.0/${NODE_ID}"
MINIO_RELEASE="${MINIO_RELEASE:-RELEASE.2024-11-07T00-52-20Z}"
MC_RELEASE="${MC_RELEASE:-RELEASE.2024-11-07T00-52-20Z}"

main() {
    check_root
    check_debian
    echo -e "${BOLD}${CYAN}teqlif V2.0 — ${NODE_ID} bootstrap (${WG_IP}) [STORAGE SECONDARY]${NC}"

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
    setup_hdd_udev
    check_swap_storage
    ufw_storage
    install_minio
    setup_minio "${NODE_DIR}"
    setup_nginx "${NODE_DIR}"
    install_promtail
    setup_promtail "${NODE_DIR}" "${NODE_ID}"
    setup_guardian "${NODE_DIR}"

    print_summary "${NODE_ID}" "${WG_IP}" \
        "wg0.conf peer <PublicKey> placeholder'larını doldur" \
        "/etc/teqlif/.env.production içindeki MINIO_ROOT_USER/PASSWORD doldur" \
        "CF Origin cert: /etc/ssl/teqlif/cf-origin.{crt,key}" \
        "nginx sites config: /etc/nginx/sites-available/minio kontrol et" \
        "node7 MinIO başladıktan sonra Site Replication kur (plan §6.5)" \
        "wg-quick up wg0  →  systemctl enable --now wg-quick@wg0" \
        "systemctl start minio  →  nginx -t && systemctl start nginx" \
        "systemctl start teqlif-guardian"
}

setup_hdd_udev() {
    log_step "HDD udev optimizasyonu"
    cat > /etc/udev/rules.d/60-teqlif-hdd.rules <<'EOF'
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", \
  ATTR{queue/scheduler}="mq-deadline", \
  ATTR{queue/read_ahead_kb}="2048", \
  ATTR{queue/nr_requests}="128"
EOF
    udevadm control --reload-rules && udevadm trigger
    log_ok "HDD scheduler + readahead optimizasyonu uygulandı"
}

check_swap_storage() {
    log_step "Swap kontrolü (storage node)"
    if swapon --show | grep -q swap; then
        log_ok "Swap mevcut"
    else
        log_warn "Swap bulunamadı — 2G swapfile oluşturuluyor"
        setup_swap 2
    fi
}

ufw_storage() {
    log_step "UFW (storage — 80/443 açık + flood koruması)"
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 22/tcp
    ufw allow 51820/udp
    ufw allow in on wg0 from 10.10.0.0/24
    ufw allow in on wg0 proto udp to any port 9901
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw_enable
    apt-get install -y -qq iptables-persistent
    iptables -I INPUT -p tcp --dport 443 \
        -m hashlimit --hashlimit-name https_flood \
        --hashlimit-above 60/min --hashlimit-burst 80 \
        --hashlimit-mode srcip -j DROP
    iptables -I INPUT -p tcp --dport 80 \
        -m hashlimit --hashlimit-name http_flood \
        --hashlimit-above 60/min --hashlimit-burst 80 \
        --hashlimit-mode srcip -j DROP
    netfilter-persistent save
    log_ok "UFW + iptables hashlimit aktif"
}

install_minio() {
    log_step "MinIO ${MINIO_RELEASE}"
    if ! command -v minio &>/dev/null; then
        curl -fsSL \
            "https://github.com/minio/minio/releases/download/${MINIO_RELEASE}/minio.linux-amd64.${MINIO_RELEASE}" \
            -o /usr/local/bin/minio
        chmod 755 /usr/local/bin/minio
        curl -fsSL \
            "https://dl.min.io/client/mc/release/linux-amd64/archive/mc.${MC_RELEASE}" \
            -o /usr/local/bin/mc
        chmod 755 /usr/local/bin/mc
        log_ok "minio + mc kuruldu"
    else
        log_info "MinIO zaten kurulu"
    fi
    mkdir -p /etc/teqlif /var/log/teqlif/minio /etc/ssl/teqlif
    chmod 700 /etc/ssl/teqlif
    chown tucibeyin:tucibeyin /var/log/teqlif/minio
    setup_env_template \
        "${NODE_DIR}/resources/.env.production.template" \
        "/etc/teqlif/.env.production"
}

setup_minio() {
    local node_dir="${1}"
    log_step "MinIO servis"
    cp "${node_dir}/systemd/minio.service" /etc/systemd/system/minio.service
    cat >> /etc/sudoers.d/guardian-systemctl <<'EOF'
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/systemctl start minio
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop minio
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart minio
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/systemctl reset-failed minio
EOF
    chmod 440 /etc/sudoers.d/guardian-systemctl
    systemctl daemon-reload
    systemctl enable minio
    log_ok "minio.service enable edildi"
}

setup_nginx() {
    local node_dir="${1}"
    log_step "nginx (S3 proxy)"
    apt-get install -y -qq nginx
    mkdir -p /var/cache/nginx/storage
    chown www-data:www-data /var/cache/nginx/storage
    mkdir -p /etc/systemd/system/nginx.service.d
    cat > /etc/systemd/system/nginx.service.d/restart.conf <<'EOF'
[Service]
Restart=always
RestartSec=5
EOF
    local nginx_src="${node_dir}/resources/nginx"
    [ -d "${nginx_src}" ] && cp -r "${nginx_src}"/* /etc/nginx/ 2>/dev/null || true
    cat >> /etc/sudoers.d/guardian-systemctl <<'EOF'
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/systemctl reload nginx
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart nginx
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/systemctl reset-failed nginx
EOF
    chmod 440 /etc/sudoers.d/guardian-systemctl
    systemctl daemon-reload
    systemctl enable nginx
    log_ok "nginx kuruldu"
}

main "$@"
