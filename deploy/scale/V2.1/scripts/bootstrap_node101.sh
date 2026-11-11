#!/bin/bash
# bootstrap_node101.sh — teqlif V2.1 Offsite Backup (DELUXHOST NL, 10.10.0.101)
# KVM 2 vCPU | 2.9 GiB RAM | 10 GB SSD + 1 TB HDD (/mnt/data)
# Restic REST Server — append-only, sadece node2'den yazma

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

NODE_ID="node101"
WG_IP="10.10.0.101"
REPO_DIR="${REPO_DIR:-/var/www/teqlif.com}"
NODE_DIR="${REPO_DIR}/deploy/scale/V2.1/${NODE_ID}"
SECRETS_FILE="${SECRETS_FILE:-}"

main() {
    check_root
    check_debian
    echo -e "${BOLD}${CYAN}teqlif V2.1 — ${NODE_ID} bootstrap (${WG_IP}) [OFFSITE-BACKUP]${NC}"

    install_base_packages_node101
    setup_user "${SSH_PUBKEY:-}"
    setup_teqlif_directories
    setup_ntp
    setup_autoupdates
    setup_limits
    setup_swap 2
    setup_logrotate
    setup_auditd
    setup_thp_disable
    mount_data_disk
    setup_node_conf   "${NODE_DIR}"
    setup_wg_keygen
    setup_wg_config   "${NODE_DIR}"
    ufw_node101
    install_fail2ban
    install_restic
    setup_offsite_dirs
    setup_offsite_services "${NODE_DIR}"
    install_teqlif_agent   "${NODE_DIR}"
    install_node_exporter_node101
    setup_wg_sudoers

    if [ -n "${SECRETS_FILE:-}" ]; then
        apply_secrets "${SECRETS_FILE}" \
            /project/teqlif/config \
            /etc/teqlif-offsite \
            /etc/wireguard
    fi

    print_summary "${NODE_ID}" "${WG_IP}" \
        "node2'de: wg_add_node101.sh çalıştır" \
        "nodeMonitor'da: wg_add_node101.sh çalıştır" \
        "wg-quick up wg0 && systemctl enable wg-quick@wg0" \
        "restic init (ilk kez): RESTIC_REPOSITORY + RESTIC_PASSWORD ile" \
        "htpasswd dosyasını oluştur: htpasswd -B /etc/teqlif-offsite/htpasswd tucibeyin" \
        "systemctl enable --now restic-rest-server teqlif-agent" \
        "systemctl enable --now teqlif-offsite-prune.timer teqlif-offsite-verify.timer" \
        "node2'de offsite_sync.sh test: systemctl start teqlif-offsite-sync" \
        "nodeMonitor'da prometheus.yml güncelle ve sudo teqlif-restart"
}

# ── node101 özel paketler ─────────────────────────────────────────────────────
install_base_packages_node101() {
    log_step "Temel paketler (node101)"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get upgrade -y -qq
    apt-get install -y -qq \
        curl wget git btop \
        ufw fail2ban \
        wireguard wireguard-tools \
        chrony \
        htop iotop nethogs \
        unattended-upgrades apt-listchanges \
        rsync logrotate \
        jq \
        python3 python3-pip python3-venv python3-dev \
        build-essential \
        auditd \
        apache2-utils \
        polkitd
    log_ok "Paketler kuruldu"
}

# ── /mnt/data HDD bağlama ────────────────────────────────────────────────────
mount_data_disk() {
    log_step "/mnt/data disk kontrolü"
    if mountpoint -q /mnt/data; then
        log_info "/mnt/data zaten bağlı"
        return 0
    fi
    # /dev/vdb ext4 olarak formatlanmış ve fstab'da girilmiş varsayımı
    if [ -b /dev/vdb ]; then
        if ! blkid /dev/vdb | grep -q ext4; then
            log_warn "/dev/vdb ext4 değil — mkfs.ext4 çalıştırılıyor"
            mkfs.ext4 -F /dev/vdb
        fi
        mkdir -p /mnt/data
        mount /dev/vdb /mnt/data
        grep -q '/mnt/data' /etc/fstab \
            || echo '/dev/vdb  /mnt/data  ext4  defaults,noatime  0  2' >> /etc/fstab
        log_ok "/mnt/data bağlandı"
    else
        log_err "/dev/vdb bulunamadı — disk eklendiğinden emin ol"
        exit 1
    fi
}

# ── UFW ───────────────────────────────────────────────────────────────────────
ufw_node101() {
    log_step "UFW (node101 — dışa kapalı)"
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 22/tcp
    ufw allow 51820/udp
    # Restic REST server sadece WireGuard ağından erişilebilir
    ufw allow in on wg0 to 10.10.0.101 port 8000 proto tcp
    ufw allow in on wg0 to 10.10.0.101 port 9100 proto tcp
    ufw_enable
}

# ── fail2ban ──────────────────────────────────────────────────────────────────
install_fail2ban() {
    log_step "fail2ban"
    apt-get install -y -qq fail2ban
    cat > /etc/fail2ban/jail.d/teqlif.conf <<'EOF'
[sshd]
enabled  = true
port     = ssh
filter   = sshd
logpath  = /var/log/auth.log
maxretry = 5
bantime  = 3600
findtime = 600
EOF
    systemctl enable --now fail2ban
    log_ok "fail2ban aktif (SSH: 5 deneme / 10 dk → 1 saat ban)"
}

# ── restic + restic-rest-server ───────────────────────────────────────────────
install_restic() {
    log_step "restic + restic-rest-server"
    # Debian 13 (trixie) native paketleri
    apt-get install -y -qq restic restic-rest-server
    log_ok "restic + restic-rest-server kuruldu"
}

# ── Offsite dizinleri ─────────────────────────────────────────────────────────
setup_offsite_dirs() {
    log_step "Offsite dizin yapısı"
    # Dedicated kullanıcı
    if ! id teqlif-backup &>/dev/null; then
        useradd --system --no-create-home --shell /sbin/nologin teqlif-backup
        log_ok "teqlif-backup kullanıcısı oluşturuldu"
    fi
    # Repo ve yardımcı dizinler HDD üzerinde
    mkdir -p \
        /mnt/data/restic-repo \
        /mnt/data/tmp \
        /mnt/data/cache/restic
    chown -R teqlif-backup:teqlif-backup \
        /mnt/data/restic-repo \
        /mnt/data/tmp \
        /mnt/data/cache/restic
    chmod 700 /mnt/data/restic-repo /mnt/data/tmp /mnt/data/cache/restic
    # Config dizini
    mkdir -p /etc/teqlif-offsite
    chmod 750 /etc/teqlif-offsite
    chown root:teqlif-backup /etc/teqlif-offsite
    # Log dizini
    mkdir -p /var/log/teqlif-offsite
    chown teqlif-backup:teqlif-backup /var/log/teqlif-offsite
    # restic.env template → operatör doldurur
    local env_src="${NODE_DIR}/resources/env/restic.env.template"
    if [ -f "${env_src}" ] && [ ! -f /etc/teqlif-offsite/restic.env ]; then
        cp "${env_src}" /etc/teqlif-offsite/restic.env
        chown root:teqlif-backup /etc/teqlif-offsite/restic.env
        chmod 640 /etc/teqlif-offsite/restic.env
        log_warn "restic.env şablonu kopyalandı — apply_secrets ile doldurun"
    fi
    log_ok "Offsite dizinleri hazır"
}

# ── Systemd servisleri ────────────────────────────────────────────────────────
setup_offsite_services() {
    local node_dir="${1}"
    log_step "Offsite systemd servisleri"
    chmod +x "${node_dir}/resources/scripts/"*.sh
    for f in "${node_dir}/systemd/"*.service "${node_dir}/systemd/"*.timer; do
        [ -f "${f}" ] && cp "${f}" /etc/systemd/system/ || true
    done
    systemctl daemon-reload
    # restic-rest-server: enable ama başlatma apply_secrets sonraya bırakılır
    systemctl enable restic-rest-server
    systemctl enable teqlif-offsite-prune.timer teqlif-offsite-verify.timer
    log_ok "Offsite servisler enable edildi (htpasswd + restic.env sonrası başlat)"
}

# ── teqlif-agent ─────────────────────────────────────────────────────────────
install_teqlif_agent() {
    local node_dir="${1}"
    log_step "teqlif-agent"
    if ! id teqlif-agent &>/dev/null; then
        useradd --system --no-create-home --shell /sbin/nologin teqlif-agent
    fi
    mkdir -p /var/lib/teqlif-agent /var/log/teqlif-agent /opt/teqlif-agent
    chown teqlif-agent:teqlif-agent /var/lib/teqlif-agent /var/log/teqlif-agent
    # Agent kodu repo içinden
    if [ -d "${REPO_DIR}/agent" ]; then
        rsync -a --delete "${REPO_DIR}/agent/" /opt/teqlif-agent/
        python3 -m venv /opt/teqlif-agent/venv
        /opt/teqlif-agent/venv/bin/pip install --upgrade pip -q
        /opt/teqlif-agent/venv/bin/pip install -r /opt/teqlif-agent/requirements.txt -q
        chown -R teqlif-agent:teqlif-agent /opt/teqlif-agent
    else
        log_warn "Agent dizini bulunamadı: ${REPO_DIR}/agent — manuel kur"
    fi
    # Agent config
    local cfg_src="${REPO_DIR}/deploy/scale/V2.1/teqlif-agent/configs/node101.yaml"
    if [ -f "${cfg_src}" ]; then
        cp "${cfg_src}" /opt/teqlif-agent/agent.yaml
        chown teqlif-agent:teqlif-agent /opt/teqlif-agent/agent.yaml
        chmod 640 /opt/teqlif-agent/agent.yaml
    fi
    # Env dosyası (redis_url boş — gossip-only)
    mkdir -p /etc/teqlif-agent
    cat > /etc/teqlif-agent/env <<'EOF'
REDIS_URL=
EOF
    chmod 600 /etc/teqlif-agent/env
    chown root:teqlif-agent /etc/teqlif-agent/env
    # Systemd
    cp "${node_dir}/systemd/teqlif-agent.service" /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable teqlif-agent
    log_ok "teqlif-agent enable edildi (gossip-only, Redis yok)"
}

# ── node_exporter ─────────────────────────────────────────────────────────────
install_node_exporter_node101() {
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
ExecStart=/usr/local/bin/node_exporter --web.listen-address=10.10.0.101:9100
Restart=always
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now node-exporter
    log_ok "node_exporter aktif (10.10.0.101:9100)"
}

main "$@"
