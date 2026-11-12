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
    clone_repo_node101 "${REPO_DIR}"
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
    setup_sysctl_node101
    setup_sshd_hardening_node101
    ufw_node101
    setup_crowdsec
    install_restic
    setup_offsite_dirs
    setup_offsite_services "${NODE_DIR}"
    install_teqlif_agent   "${NODE_DIR}"
    install_node_exporter "10.10.0.101"
    setup_wg_sudoers
    install_teqlif_restart_node101
    setup_sudoers_node101

    if [ -n "${SECRETS_FILE:-}" ]; then
        apply_secrets "${SECRETS_FILE}" \
            /project/teqlif/config \
            /etc/teqlif-offsite \
            /etc/wireguard
    fi

    print_summary "${NODE_ID}" "${WG_IP}" \
        "Repo her zaman /var/www/teqlif.com'da — git pull otomatik yapıldı" \
        "node2'de: wg_add_node101.sh çalıştır" \
        "nodeMonitor'da: wg_add_node101.sh çalıştır" \
        "wg-quick up wg0 && systemctl enable wg-quick@wg0" \
        "restic init: sudo -u teqlif-backup restic init (RESTIC_REPOSITORY + RESTIC_PASSWORD)" \
        "htpasswd oluştur: htpasswd -B /etc/teqlif-offsite/htpasswd teqlif" \
        "apply_secrets ile restic.env + wg0.conf doldur" \
        "systemctl start restic-rest-server teqlif-agent" \
        "node2'de offsite_sync.sh ilk test: systemctl start teqlif-offsite-sync" \
        "nodeMonitor'da sudo teqlif-restart (prometheus + agent config güncellendi)"
}

# ── Repo klonlama (node101) ───────────────────────────────────────────────────
# node101 servis scriptlerini ve agent config'ini repo'dan okur.
# Repo public olduğu için token gereksiz; opsiyonel olarak GITHUB_TOKEN verilebilir.
# Deploy key alternatifi: SSH_KEY_PATH=/home/tucibeyin/.ssh/github_key
clone_repo_node101() {
    local repo_dir="${1}"
    log_step "Git repo (node101)"
    if [ -d "${repo_dir}/.git" ]; then
        log_info "Repo mevcut: ${repo_dir} — git pull"
        sudo -u tucibeyin git -C "${repo_dir}" pull --ff-only 2>/dev/null || true
        return 0
    fi
    mkdir -p "${repo_dir}"
    chown tucibeyin:tucibeyin "${repo_dir}"
    local deploy_key="${SSH_KEY_PATH:-/home/tucibeyin/.ssh/github_key}"
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        sudo -u tucibeyin git clone \
            "https://${GITHUB_TOKEN}@github.com/tucibeyin/teqlif.git" "${repo_dir}"
    elif [ -f "${deploy_key}" ]; then
        sudo -u tucibeyin \
            GIT_SSH_COMMAND="ssh -i ${deploy_key} -o StrictHostKeyChecking=accept-new" \
            git clone git@github.com:tucibeyin/teqlif.git "${repo_dir}"
    else
        # Public repo — token/key gerektirmez
        sudo -u tucibeyin git clone \
            https://github.com/tucibeyin/teqlif.git "${repo_dir}"
    fi
    chown -R tucibeyin:tucibeyin "${repo_dir}"
    log_ok "Repo klonlandı: ${repo_dir}"
}

# ── node101 özel paketler ─────────────────────────────────────────────────────
install_base_packages_node101() {
    log_step "Temel paketler (node101)"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get upgrade -y -qq
    apt-get install -y -qq \
        curl wget git btop \
        ufw \
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
        mount -o noatime /dev/vdb /mnt/data
        grep -q '/mnt/data' /etc/fstab \
            || echo '/dev/vdb  /mnt/data  ext4  defaults,noatime  0  2' >> /etc/fstab
        log_ok "/mnt/data bağlandı (noatime)"
    else
        log_err "/dev/vdb bulunamadı — disk eklendiğinden emin ol"
        exit 1
    fi
}

# ── Sysctl + IO (node101 — HDD backup workload) ──────────────────────────────
setup_sysctl_node101() {
    log_step "sysctl + IO scheduler (node101)"
    cat > /etc/sysctl.d/99-teqlif-node101.conf <<'EOF'
vm.swappiness = 10
vm.dirty_ratio = 20
vm.dirty_background_ratio = 5
vm.dirty_writeback_centisecs = 1500
fs.file-max = 262144
EOF
    sysctl -p /etc/sysctl.d/99-teqlif-node101.conf
    # vd* sanal diskler için mq-deadline
    cat > /etc/udev/rules.d/60-hdd-scheduler.rules <<'EOF'
ACTION=="add|change", KERNEL=="vd[a-z]", ATTR{queue/scheduler}="mq-deadline"
EOF
    for dev in /sys/block/vd*; do
        [ -f "${dev}/queue/scheduler" ] && echo mq-deadline > "${dev}/queue/scheduler" 2>/dev/null || true
    done
    # fstrim HDD'de gereksiz
    systemctl mask fstrim.timer 2>/dev/null || true
    # journald limit — 818MB default SSD israfını önle
    mkdir -p /etc/systemd/journald.conf.d
    cat > /etc/systemd/journald.conf.d/teqlif-node101.conf <<'EOF'
[Journal]
SystemMaxUse=200M
SystemMaxFiles=10
RuntimeMaxUse=50M
Compress=yes
EOF
    systemctl restart systemd-journald
    # apt-daily-upgrade: 06:00+60m → offsite_sync 06:30 ile çakışır, 10:00'a al
    mkdir -p /etc/systemd/system/apt-daily-upgrade.timer.d
    cat > /etc/systemd/system/apt-daily-upgrade.timer.d/teqlif-timing.conf <<'EOF'
[Timer]
OnCalendar=
OnCalendar=*-*-* 10:00
RandomizedDelaySec=15m
EOF
    log_ok "sysctl + mq-deadline scheduler + journald limit + apt timing aktif"
}

# ── CrowdSec (node101 — sadece SSH, nginx/http collection yok) ───────────────
setup_crowdsec() {
    log_step "CrowdSec (node101 — SSH only)"
    if ! command -v cscli &>/dev/null; then
        install -d /etc/apt/keyrings
        curl -fsSL https://packagecloud.io/crowdsec/crowdsec/gpgkey \
            | gpg --dearmor -o /etc/apt/keyrings/crowdsec.gpg 2>/dev/null || true
        echo "deb [signed-by=/etc/apt/keyrings/crowdsec.gpg] \
https://packagecloud.io/crowdsec/crowdsec/debian/ \
$(. /etc/os-release; echo "$VERSION_CODENAME") main" \
            > /etc/apt/sources.list.d/crowdsec.list
        apt-get update -qq
        apt-get install -y -qq crowdsec crowdsec-firewall-bouncer
    else
        log_info "CrowdSec zaten kurulu"
    fi
    cscli hub update 2>/dev/null || true
    cscli collections install crowdsecurity/linux crowdsecurity/sshd --force 2>/dev/null || true
    # Kümülatif ban
    python3 - <<'PY'
import re, pathlib
p = pathlib.Path('/etc/crowdsec/profiles.yaml')
c = p.read_text()
c = c.replace('#duration_expr:', 'duration_expr:')
c = re.sub(r'   duration: 4h\n', '', c)
p.write_text(c)
PY
    systemctl enable --now crowdsec crowdsec-firewall-bouncer
    systemctl restart crowdsec
    log_ok "CrowdSec aktif (SSH: kümülatif ban)"
}

# ── SSH sertleştirme (node101) ────────────────────────────────────────────────
# 01- öneki cloud-init'in 50-cloud-init.conf'undan önce yüklenir; first-match kazanır.
setup_sshd_hardening_node101() {
    log_step "SSH sertleştirme (node101)"
    mkdir -p /etc/ssh/sshd_config.d
    # 01-* öneki ile cloud-init'in 50-cloud-init.conf'undan önce yüklenir;
    # OpenSSH first-match semantiği: 01- kazanır, 50- görmezden gelinir.
    local harden_conf=/etc/ssh/sshd_config.d/01-teqlif-hardening.conf
    # Eski 99- dosyasını temizle (önceki bootstrap versiyonu)
    rm -f /etc/ssh/sshd_config.d/99-teqlif-hardening.conf
    cat > "${harden_conf}" <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
EOF
    chmod 600 "${harden_conf}"
    # Sözdizimi denetimi
    sshd -t 2>&1 || { log_err "sshd config geçersiz — hardening dosyası kaldırılıyor"; rm "${harden_conf}"; return 1; }
    systemctl reload ssh || systemctl reload sshd || true
    sshd -T 2>/dev/null | grep -i passwordauthentication
    log_ok "SSH sertleştirme aktif (PasswordAuthentication no)"
}

# ── UFW ───────────────────────────────────────────────────────────────────────
ufw_node101() {
    log_step "UFW (node101 — dışa kapalı, IPv6 kapalı)"
    # IPv6 devre dışı (node101 IPv4-only)
    sed -i 's/^IPV6=yes/IPV6=no/' /etc/default/ufw
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 22/tcp
    ufw allow 51820/udp
    # Restic REST server: yalnız node2 (10.10.0.2)
    ufw allow in on wg0 from 10.10.0.2 to any port 8000 proto tcp
    # node_exporter: yalnız nodeMonitor (10.10.0.99)
    ufw allow in on wg0 from 10.10.0.99 to any port 9100 proto tcp
    # teqlif-agent gossip: node2 + nodeMonitor
    ufw allow in on wg0 from 10.10.0.2  to any port 19100 proto tcp comment 'teqlif-agent gossip node2'
    ufw allow in on wg0 from 10.10.0.99 to any port 19100 proto tcp comment 'teqlif-agent gossip nodeMonitor'
    ufw_enable
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
    # /mnt/data mount point'i root'a ait olmalı; alt dizinler servis kullanıcılarına
    chown root:root /mnt/data
    chmod 755 /mnt/data
    # restic repo dizini: --private-repos HTTP user=teqlif → /mnt/data/teqlif/
    # restic-rest-server User=teqlif-backup; root:root 755 altında yazamaz — önceden oluştur
    mkdir -p /mnt/data/teqlif
    chown teqlif-backup:teqlif-backup /mnt/data/teqlif
    chmod 700 /mnt/data/teqlif
    # Yardımcı dizinler HDD üzerinde
    mkdir -p \
        /mnt/data/tmp \
        /mnt/data/cache/restic
    chown -R teqlif-backup:teqlif-backup \
        /mnt/data/tmp \
        /mnt/data/cache/restic
    chmod 700 /mnt/data/tmp /mnt/data/cache/restic
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
    cp "${node_dir}/resources/scripts/notify_backup_failed.sh" /usr/local/bin/
    chmod +x /usr/local/bin/notify_backup_failed.sh
    for f in "${node_dir}/systemd/"*.service "${node_dir}/systemd/"*.timer; do
        [ -f "${f}" ] && cp "${f}" /etc/systemd/system/ || true
    done
    systemctl daemon-reload
    # restic-rest-server: enable ama başlatma apply_secrets sonraya bırakılır
    systemctl enable restic-rest-server
    # prune + verify timer'ları enable et; RESTIC_PASSWORD placeholder ile ilk atış başarısız
    # olur ama zararsız — gerçek şifre Adım 10 (Key Escrow) sonrası restic.env'e yazılacak
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
    local agent_src="${REPO_DIR}/deploy/scale/V2.1/teqlif-agent"
    if [ -d "${agent_src}" ]; then
        rsync -a --delete \
            --exclude '__pycache__' --exclude '*.pyc' \
            --exclude 'configs/' --exclude 'setup/' \
            "${agent_src}/" /opt/teqlif-agent/
        # schedule.yaml ve cluster.yaml agent dizinine kopyala (agent.py bunları okur)
        cp "${REPO_DIR}/deploy/scale/V2.1/schedule.yaml" /opt/teqlif-agent/schedule.yaml
        cp "${REPO_DIR}/deploy/scale/V2.1/cluster.yaml"  /opt/teqlif-agent/cluster.yaml
        python3 -m venv /opt/teqlif-agent/venv
        /opt/teqlif-agent/venv/bin/pip install --quiet --upgrade pip
        /opt/teqlif-agent/venv/bin/pip install --quiet \
            aiohttp aiosqlite pyyaml asyncpg aioredis "redis>=4.2.0"
        chown -R teqlif-agent:teqlif-agent /opt/teqlif-agent
    else
        log_warn "Agent dizini bulunamadı: ${agent_src} — manuel kur"
    fi
    # Agent config → /etc/teqlif-agent/config.yaml (load_config() varsayılan yolu)
    local cfg_src="${agent_src}/configs/node101.yaml"
    if [ -f "${cfg_src}" ]; then
        install -m 640 -o teqlif-agent -g teqlif-agent "${cfg_src}" /etc/teqlif-agent/config.yaml
    fi
    # Env dosyası (redis_url boş — gossip-only; Telegram secrets.env'den doldurulur)
    # İDEMPOTENT: mevcut dolmuş token'ları silmez; yalnız boş/eksikse yazar.
    mkdir -p /etc/teqlif-agent
    if [ ! -f /etc/teqlif-agent/env ] || ! grep -q 'TELEGRAM_BOT_TOKEN=' /etc/teqlif-agent/env 2>/dev/null; then
        cat > /etc/teqlif-agent/env <<'EOF'
REDIS_URL=
TELEGRAM_BOT_TOKEN=
TELEGRAM_CHAT_ID=
EOF
        chmod 600 /etc/teqlif-agent/env
        chown root:teqlif-agent /etc/teqlif-agent/env
    fi
    # Systemd
    cp "${node_dir}/systemd/teqlif-agent.service" /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable teqlif-agent
    log_ok "teqlif-agent enable edildi (gossip-only, Redis yok)"
}

# ── teqlif-restart (gerçek script) ───────────────────────────────────────────
# Tüm node'larda yetkili script scripts/teqlif-restart.sh'tır.
# setup/teqlif-restart eski kopyadır — bootstrap bunu kurmaz.
install_teqlif_restart_node101() {
    log_step "teqlif-restart (scripts/teqlif-restart.sh)"
    local src="${REPO_DIR}/deploy/scale/V2.1/scripts/teqlif-restart.sh"
    local dst="/usr/local/sbin/teqlif-restart"
    if [ -f "${src}" ]; then
        install -m 755 "${src}" "${dst}"
        log_ok "teqlif-restart kuruldu (${dst})"
    else
        log_warn "scripts/teqlif-restart.sh bulunamadı — atlanıyor"
    fi
}

setup_sudoers_node101() {
    log_step "sudoers — tucibeyin passwordless teqlif-restart"
    local sudoers_file="/etc/sudoers.d/90-teqlif-node101"
    cat > "${sudoers_file}" <<'EOF'
# teqlif V2.1 — node101 operasyonel komutları
tucibeyin ALL=(root) NOPASSWD: /usr/local/sbin/teqlif-restart
EOF
    chmod 440 "${sudoers_file}"
    visudo -cf "${sudoers_file}" && log_ok "sudoers eklendi (${sudoers_file})" \
        || { log_warn "sudoers syntax hatası — siliniyor"; rm -f "${sudoers_file}"; }
}

main "$@"
