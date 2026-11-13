#!/bin/bash
# _common.sh — teqlif V2.1 bootstrap ortak fonksiyonlar
# Doğrudan çalıştırılmaz; bootstrap_nodeX.sh tarafından source edilir.

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
log_info() { echo -e "${CYAN}[INFO]${NC} $*"; }
log_ok()   { echo -e "${GREEN}[ OK ]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_err()  { echo -e "${RED}[ERR ]${NC} $*" >&2; }
log_step() { echo -e "\n${BOLD}${BLUE}──── $* ────${NC}"; }

# ── Cleanup (trap EXIT) ───────────────────────────────────────────────────────
CLEANUP_DONE=0
cleanup() {
    [ "${CLEANUP_DONE}" -eq 1 ] && return; CLEANUP_DONE=1
    log_step "Cleanup"
    apt-get clean -qq 2>/dev/null || true
    apt-get autoremove -y -qq 2>/dev/null || true
    rm -rf /tmp/teqlif-bootstrap-*
    log_ok "Geçici dosyalar ve apt cache temizlendi"
}
trap cleanup EXIT

# ── Temel kontroller ──────────────────────────────────────────────────────────
check_root() {
    [ "$(id -u)" -eq 0 ] || { log_err "Root olarak çalıştırın: sudo bash $0"; exit 1; }
}

check_debian() {
    grep -qi 'debian\|ubuntu' /etc/os-release \
        || { log_err "Bu script Debian/Ubuntu içindir"; exit 1; }
}

# ── Temel paketler ────────────────────────────────────────────────────────────
install_base_packages() {
    log_step "Temel paketler"
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
        nvme-cli smartmontools \
        polkitd
    log_ok "Paketler kuruldu"
}

# ── Kullanıcı ve SSH ──────────────────────────────────────────────────────────
setup_user() {
    local pubkey="${1:-}"
    log_step "Kullanıcı ve SSH"
    if ! id tucibeyin &>/dev/null; then
        adduser --disabled-password --gecos "" tucibeyin
        usermod -aG sudo tucibeyin
        log_ok "tucibeyin kullanıcısı oluşturuldu"
    else
        log_info "tucibeyin zaten var"
    fi
    mkdir -p /home/tucibeyin/.ssh
    if [ -n "${pubkey}" ]; then
        echo "${pubkey}" >> /home/tucibeyin/.ssh/authorized_keys
        sort -u /home/tucibeyin/.ssh/authorized_keys -o /home/tucibeyin/.ssh/authorized_keys
    fi
    chmod 700 /home/tucibeyin/.ssh
    chmod 600 /home/tucibeyin/.ssh/authorized_keys 2>/dev/null || true
    chown -R tucibeyin:tucibeyin /home/tucibeyin/.ssh
    # Renkli prompt
    grep -q "PS1=" /home/tucibeyin/.bashrc 2>/dev/null \
        || echo "PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '" \
            >> /home/tucibeyin/.bashrc
    # SSH sertleştirme
    sed -i 's/^#*\s*PermitRootLogin.*/PermitRootLogin no/'              /etc/ssh/sshd_config
    sed -i 's/^#*\s*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
    sed -i 's/^#*\s*MaxAuthTries.*/MaxAuthTries 3/'                      /etc/ssh/sshd_config
    sed -i 's/^#*\s*X11Forwarding.*/X11Forwarding no/'                  /etc/ssh/sshd_config
    grep -q "^AllowUsers" /etc/ssh/sshd_config \
        || echo "AllowUsers tucibeyin" >> /etc/ssh/sshd_config
    systemctl restart sshd
    log_ok "SSH sertleştirildi (root girişi kapalı, parola devre dışı)"
}

# ── teqlif'e özel dizinler ────────────────────────────────────────────────────
# Bare metal node'larda çok proje çalışabileceğinden teqlif verileri
# /project/teqlif/config, /project/teqlif/data, /project/teqlif/logs altında izole tutulur.
setup_teqlif_directories() {
    log_step "teqlif dizin yapısı"
    mkdir -p /var/www/teqlif.com
    mkdir -p /project/teqlif/config
    mkdir -p /project/teqlif/data/{minio/data,redis}
    mkdir -p /project/teqlif/logs/{api,worker}
    chmod 700 /project/teqlif/config
    chmod 755 /project/teqlif/logs
    chown -R tucibeyin:tucibeyin \
        /var/www/teqlif.com \
        /project/teqlif/config \
        /project/teqlif/data \
        /project/teqlif/logs
    log_ok "teqlif dizinleri hazır (/project/teqlif/config, /project/teqlif/data, /project/teqlif/logs)"
}

# ── NTP + Timezone ────────────────────────────────────────────────────────────
setup_ntp() {
    log_step "NTP + Timezone"
    timedatectl set-timezone UTC
    systemctl enable --now chrony
    log_ok "Timezone=UTC, chrony aktif"
}

# ── Otomatik güvenlik güncellemeleri ─────────────────────────────────────────
setup_autoupdates() {
    log_step "Otomatik güvenlik güncellemeleri"
    DEBIAN_FRONTEND=noninteractive dpkg-reconfigure -plow unattended-upgrades
    log_ok "Unattended-upgrades aktif (yalnızca güvenlik)"
}

# ── Dosya sınırları ───────────────────────────────────────────────────────────
setup_limits() {
    log_step "LimitNOFILE"
    cat > /etc/security/limits.d/teqlif.conf <<'EOF'
tucibeyin soft nofile 65535
tucibeyin hard nofile 65535
root      soft nofile 65535
root      hard nofile 65535
EOF
    for conf in /etc/systemd/system.conf /etc/systemd/user.conf; do
        sed -i 's/^#*DefaultLimitNOFILE=.*/DefaultLimitNOFILE=65535/' "${conf}"
        grep -q "^DefaultLimitNOFILE" "${conf}" \
            || echo "DefaultLimitNOFILE=65535" >> "${conf}"
    done
    systemctl daemon-reload
    log_ok "LimitNOFILE=65535"
}

# ── Logrotate ─────────────────────────────────────────────────────────────────
setup_logrotate() {
    log_step "Logrotate"
    cp "${SCRIPT_DIR}/resources/logrotate.d/teqlif" /etc/logrotate.d/teqlif
    log_ok "Logrotate yapılandırıldı"
}

# ── journald kota ──────────────────────────────────────────────────────────────
setup_journald() {
    log_step "journald kota"
    local conf_dir="/etc/systemd/journald.conf.d"
    mkdir -p "${conf_dir}"
    cp "${SCRIPT_DIR}/resources/journald.conf.d/teqlif.conf" "${conf_dir}/teqlif.conf"
    systemctl restart systemd-journald
    journalctl --vacuum-size=200M >/dev/null 2>&1 || true
    log_ok "journald SystemMaxUse=200M, MaxRetentionSec=14day"
}

# ── Auditd ────────────────────────────────────────────────────────────────────
setup_auditd() {
    log_step "Auditd"
    cat > /etc/audit/rules.d/teqlif.rules <<'EOF'
-w /project/teqlif/config/          -p wa -k teqlif_secrets
-w /etc/wireguard/       -p wa -k wireguard_config
-w /home/tucibeyin/.ssh/ -p wa -k ssh_keys
-w /etc/sudoers          -p wa -k sudoers_change
-w /bin/sudo             -p x  -k sudo_exec
-a always,exit -F arch=b64 -S execve -F uid=0 -k root_commands
EOF
    systemctl enable --now auditd
    log_ok "Auditd aktif"
}

# ── THP disable ───────────────────────────────────────────────────────────────
setup_thp_disable() {
    log_step "Transparent Hugepages"
    cat > /etc/systemd/system/thp-disable.service <<'EOF'
[Unit]
Description=Disable Transparent Huge Pages
DefaultDependencies=no
After=sysinit.target local-fs.target
Before=basic.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c "echo never > /sys/kernel/mm/transparent_hugepage/enabled && echo never > /sys/kernel/mm/transparent_hugepage/defrag"
RemainAfterExit=yes

[Install]
WantedBy=basic.target
EOF
    systemctl daemon-reload
    systemctl enable --now thp-disable
    log_ok "THP devre dışı"
}

# ── CrowdSec ──────────────────────────────────────────────────────────────────
setup_crowdsec() {
    log_step "CrowdSec"
    if ! command -v cscli &>/dev/null; then
        install -d /etc/apt/keyrings
        curl -fsSL https://packagecloud.io/crowdsec/crowdsec/gpgkey \
            | gpg --dearmor -o /etc/apt/keyrings/crowdsec.gpg
        echo "deb [signed-by=/etc/apt/keyrings/crowdsec.gpg] \
https://packagecloud.io/crowdsec/crowdsec/debian/ \
$(. /etc/os-release; echo "$VERSION_CODENAME") main" \
            > /etc/apt/sources.list.d/crowdsec.list
        apt-get update -qq
        apt-get install -y -qq crowdsec crowdsec-firewall-bouncer
    else
        log_info "CrowdSec zaten kurulu"
    fi
    cscli collections install \
        crowdsecurity/linux \
        crowdsecurity/sshd \
        crowdsecurity/nginx \
        crowdsecurity/base-http-scenarios \
        crowdsecurity/http-cve \
        2>/dev/null || true
    systemctl enable --now crowdsec crowdsec-firewall-bouncer
    # Kümülatif ban: (tekrar_sayısı + 1) × 4 saat (duration_expr, CrowdSec ≥ v1.5)
    python3 - <<'PY'
import re, pathlib
p = pathlib.Path('/etc/crowdsec/profiles.yaml')
c = p.read_text()
c = c.replace('#duration_expr:', 'duration_expr:')
c = re.sub(r'   duration: 4h\n', '', c)
p.write_text(c)
PY
    systemctl restart crowdsec
    log_ok "CrowdSec + firewall-bouncer aktif (kümülatif ban)"
}

# ── Repo klonlama veya doğrulama ──────────────────────────────────────────────
clone_repo() {
    local repo_dir="${1}"
    log_step "Git repo"
    if [ -d "${repo_dir}/.git" ]; then
        log_info "Repo mevcut: ${repo_dir} — git pull"
        sudo -u tucibeyin git -C "${repo_dir}" pull --ff-only 2>/dev/null || true
        return 0
    fi
    mkdir -p "${repo_dir}"
    chown tucibeyin:tucibeyin "${repo_dir}"
    local deploy_key="${DEPLOY_KEY_PATH:-/home/tucibeyin/.ssh/github_key}"
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        sudo -u tucibeyin git clone \
            "https://${GITHUB_TOKEN}@github.com/tucibeyin/teqlif.git" "${repo_dir}"
    elif [ -f "${deploy_key}" ]; then
        sudo -u tucibeyin \
            GIT_SSH_COMMAND="ssh -i ${deploy_key} -o StrictHostKeyChecking=accept-new" \
            git clone git@github.com:tucibeyin/teqlif.git "${repo_dir}"
    else
        log_err "Deploy key bulunamadı: ${deploy_key}"
        log_err "Önce setup_github_deploy_key çalıştırılmalı."
        return 1
    fi
    chown -R tucibeyin:tucibeyin "${repo_dir}"
    log_ok "Repo klonlandı: ${repo_dir}"
}


# ── WireGuard anahtar üretimi ─────────────────────────────────────────────────
setup_wg_keygen() {
    log_step "WireGuard anahtar üretimi"
    mkdir -p /etc/wireguard
    chmod 700 /etc/wireguard
    if [ ! -f /etc/wireguard/privatekey ]; then
        wg genkey | tee /etc/wireguard/privatekey | wg pubkey > /etc/wireguard/pubkey
        chmod 600 /etc/wireguard/privatekey
        log_ok "Anahtar çifti üretildi: /etc/wireguard/{privatekey,pubkey}"
    else
        log_info "WireGuard anahtarı zaten mevcut"
    fi
}

# ── WireGuard config kopyalama ────────────────────────────────────────────────
setup_wg_config() {
    local node_dir="${1}"
    log_step "WireGuard config"
    local src="${node_dir}/resources/wireguard/wg0.conf"
    [ -f "${src}" ] || { log_warn "wg0.conf bulunamadı: ${src}"; return; }
    cp "${src}" /etc/wireguard/wg0.conf
    local privkey
    privkey="$(cat /etc/wireguard/privatekey)"
    sed -i "s|<privatekey>|${privkey}|g" /etc/wireguard/wg0.conf
    chmod 600 /etc/wireguard/wg0.conf
    log_ok "wg0.conf kopyalandı (<privatekey> dolduruldu)"
}

# ── WG peer sudoers (streaming node ekleme için) ─────────────────────────────
setup_wg_sudoers() {
    log_step "WG peer sudoers"
    cat > /etc/sudoers.d/teqlif-wg <<'EOF'
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/wg set wg0 peer * allowed-ips *
tucibeyin ALL=(ALL) NOPASSWD: /usr/sbin/wg-quick save wg0
EOF
    chmod 440 /etc/sudoers.d/teqlif-wg
    visudo -c -f /etc/sudoers.d/teqlif-wg
    log_ok "teqlif-wg sudoers eklendi"
}

# ── Redis VIP sudoers (node2: ip addr + iptables + wg show) ──────────────────
setup_redis_vip_sudoers_node2() {
    log_step "Redis VIP sudoers (node2)"
    cat > /etc/sudoers.d/teqlif-redis-vip <<'EOF'
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/wg show wg0 dump
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/ip addr add 10.10.0.1/32 dev lo
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/ip addr del 10.10.0.1/32 dev lo
tucibeyin ALL=(ALL) NOPASSWD: /sbin/iptables
EOF
    chmod 440 /etc/sudoers.d/teqlif-redis-vip
    visudo -c -f /etc/sudoers.d/teqlif-redis-vip
    log_ok "teqlif-redis-vip sudoers eklendi (node2)"
}

# ── Redis VIP sudoers (node3/4/5/6: wg show dump için) ───────────────────────
setup_redis_vip_sudoers_client() {
    log_step "Redis VIP sudoers (client node)"
    cat > /etc/sudoers.d/teqlif-redis-vip <<'EOF'
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/wg show wg0 dump
EOF
    chmod 440 /etc/sudoers.d/teqlif-redis-vip
    visudo -c -f /etc/sudoers.d/teqlif-redis-vip
    log_ok "teqlif-redis-vip sudoers eklendi (client node)"
}

# ── HAProxy Redis HA proxy (streaming node'ları: node3/node4) ─────────────────
# 127.0.0.1:6379 → node1-redis (primary) / node2-redis (backup)
# LiveKit livekit.yaml'daki redis.address=127.0.0.1:6379 bu proxy'e bağlanır.
install_haproxy() {
    log_step "HAProxy"
    apt-get install -y -qq haproxy
    log_ok "HAProxy kuruldu"
}

setup_haproxy_redis_proxy() {
    local node_dir="${1}"
    log_step "HAProxy Redis HA proxy config"
    local cfg_src="${node_dir}/resources/livekit/haproxy.cfg"
    [ -f "${cfg_src}" ] || { log_err "haproxy.cfg şablonu bulunamadı: ${cfg_src}"; return 1; }
    mkdir -p /etc/haproxy
    cp "${cfg_src}" /etc/haproxy/haproxy.cfg
    chmod 640 /etc/haproxy/haproxy.cfg
    chown root:haproxy /etc/haproxy/haproxy.cfg 2>/dev/null || true
    # apply_secrets /etc/haproxy'yi de tarar — <core_redis_pass> sonra ikame edilir.
    # Şimdi sadece enable et; apply_secrets + manuel restart print_summary'de.
    systemctl enable haproxy
    log_ok "HAProxy enable edildi (apply_secrets sonrası başlatılacak)"
}

# ── apt-daily-upgrade timer zamanlaması (MAINT-04) ───────────────────────────
# Varsayılan 06:00+60m penceresi offsite backup bloğuyla (06:30-07:30) çakışır.
# 07:45 UTC'ye çekince backup + ML eğitim bitiminden sonra çalışır.
setup_apt_timing() {
    log_step "apt-daily-upgrade timer zamanlaması (07:45 UTC)"
    mkdir -p /etc/systemd/system/apt-daily-upgrade.timer.d
    cat > /etc/systemd/system/apt-daily-upgrade.timer.d/teqlif-timing.conf <<'EOF'
[Timer]
OnCalendar=
OnCalendar=*-*-* 07:45:00 UTC
RandomizedDelaySec=15m
EOF
    systemctl daemon-reload
    systemctl restart apt-daily-upgrade.timer 2>/dev/null || true
    log_ok "apt-daily-upgrade → 07:45 UTC (±15 dakika)"
}

# ── mdcheck_continue timer zamanlaması — yalnız node2 (MAINT-04) ─────────────
# OnCalendar=daily + RandomizedDelaySec=12h → 00:00–12:00 arası ateşleniyor.
# Ayın 1. haftasında 06:46 UTC'de backup bloğuna bindi (gözlemlendi).
# 07:35 UTC'ye çekilince offsite_sync (~07:00 UTC biter) sonrasına düşer.
setup_mdcheck_timing() {
    if ! systemctl list-unit-files mdcheck_continue.timer &>/dev/null; then
        log_warn "mdcheck_continue.timer mevcut değil, atlanıyor"
        return
    fi
    log_step "mdcheck_continue timer zamanlaması (07:35 UTC)"
    mkdir -p /etc/systemd/system/mdcheck_continue.timer.d
    cat > /etc/systemd/system/mdcheck_continue.timer.d/teqlif-timing.conf <<'EOF'
[Timer]
OnCalendar=
OnCalendar=*-*-* 07:35:00 UTC
RandomizedDelaySec=15m
EOF
    systemctl daemon-reload
    log_ok "mdcheck_continue → 07:35 UTC (±15 dakika)"
}

# ── Sysctl uygulama ───────────────────────────────────────────────────────────
setup_sysctl() {
    local node_dir="${1}"
    log_step "Sysctl"
    [ -f "${node_dir}/resources/sysctl.d/99-teqlif.conf" ] \
        || { log_warn "99-teqlif.conf bulunamadı"; return; }
    cp "${node_dir}/resources/sysctl.d/99-teqlif.conf" /etc/sysctl.d/99-teqlif.conf
    sysctl --system -q
    log_ok "Sysctl uygulandı"
}

# ── node.conf ─────────────────────────────────────────────────────────────────
setup_node_conf() {
    local node_dir="${1}"
    log_step "node.conf"
    [ -f "${node_dir}/resources/node.conf" ] \
        || { log_warn "node.conf bulunamadı"; return; }
    cp "${node_dir}/resources/node.conf" /project/teqlif/config/node.conf
    log_ok "node.conf → /project/teqlif/config/node.conf"
}

# ── PGDG apt repo ─────────────────────────────────────────────────────────────
install_pgdg_repo() {
    if [ -f /etc/apt/sources.list.d/pgdg.list ]; then
        log_info "PGDG repo zaten mevcut"; return
    fi
    log_step "PGDG apt repo"
    apt-get install -y -qq gnupg
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
        | gpg --dearmor | tee /usr/share/keyrings/pgdg.gpg > /dev/null
    echo "deb [signed-by=/usr/share/keyrings/pgdg.gpg] https://apt.postgresql.org/pub/repos/apt \
$(. /etc/os-release; echo "$VERSION_CODENAME")-pgdg main" \
        | tee /etc/apt/sources.list.d/pgdg.list
    apt-get update -qq
    log_ok "PGDG repo eklendi"
}

# ── Grafana apt repo (promtail) ───────────────────────────────────────────────
install_grafana_repo() {
    if [ -f /etc/apt/sources.list.d/grafana.list ]; then
        log_info "Grafana repo zaten mevcut"; return
    fi
    log_step "Grafana apt repo"
    apt-get install -y -qq gnupg
    curl -fsSL https://apt.grafana.com/gpg.key \
        | gpg --dearmor | tee /usr/share/keyrings/grafana.gpg > /dev/null
    echo "deb [signed-by=/usr/share/keyrings/grafana.gpg] https://apt.grafana.com stable main" \
        | tee /etc/apt/sources.list.d/grafana.list
    apt-get update -qq
    log_ok "Grafana repo eklendi"
}

# ── Promtail ──────────────────────────────────────────────────────────────────
install_promtail() {
    install_grafana_repo
    log_step "Promtail"
    apt-get install -y -qq promtail
    log_ok "Promtail kuruldu"
}

setup_promtail() {
    local node_dir="${1}"
    local node_id="${2}"
    local tenant="${3:-teqlif}"   # varsayılan tenant: teqlif; yeni proje eklenince override edilir
    log_step "Promtail config (tenant=${tenant})"
    mkdir -p /var/lib/promtail /etc/promtail
    local cfg="${node_dir}/resources/promtail/config.yml"
    [ -f "${cfg}" ] || { log_warn "Promtail config bulunamadı: ${cfg}"; return; }
    cp "${cfg}" /etc/promtail/config.yml
    # tenant_id'yi config'e yaz (template'te placeholder varsa override eder)
    sed -i "s|tenant_id:.*|tenant_id: ${tenant}|g" /etc/promtail/config.yml
    # Promtail journal erişimi için gruplara ekle
    usermod -aG systemd-journal promtail 2>/dev/null || true
    usermod -aG adm promtail 2>/dev/null || true
    # systemd drop-in: promtail ek grupları
    mkdir -p /etc/systemd/system/promtail.service.d
    cat > /etc/systemd/system/promtail.service.d/override.conf <<EOF
[Service]
SupplementaryGroups=systemd-journal adm
User=tucibeyin
EOF
    systemctl daemon-reload
    systemctl enable --now promtail
    log_ok "Promtail aktif (node=${node_id}, tenant=${tenant} → Loki 10.10.0.2:3100)"
}

# ── Python venv + requirements ────────────────────────────────────────────────
setup_venv() {
    local repo_dir="${1}"
    log_step "Python venv"
    if [ ! -x "${repo_dir}/.venv/bin/uvicorn" ]; then
        python3 -m venv "${repo_dir}/.venv"
        "${repo_dir}/.venv/bin/pip" install --upgrade pip -q
        "${repo_dir}/.venv/bin/pip" install -r "${repo_dir}/backend/requirements.txt" -q
        chown -R tucibeyin:tucibeyin "${repo_dir}/.venv"
        log_ok "venv + requirements kuruldu"
    else
        log_info "venv zaten mevcut"
    fi
}

# ── .env template kopyalama ───────────────────────────────────────────────────
setup_env_template() {
    local src="${1}"
    local dest="${2}"
    log_step ".env: $(basename ${dest})"
    [ -f "${src}" ] || { log_warn ".env template bulunamadı: ${src}"; return; }
    cp "${src}" "${dest}"
    chmod 600 "${dest}"
    chown tucibeyin:tucibeyin "${dest}"
    log_ok "${dest} kopyalandı"
}

# ── Swap dosyası ──────────────────────────────────────────────────────────────
setup_swap() {
    local size_gb="${1:-4}"
    local swapfile="/swapfile"
    log_step "Swap (${size_gb}G)"
    if swapon --show | grep -q "${swapfile}" 2>/dev/null; then
        log_info "Swap zaten aktif: ${swapfile}"; return
    fi
    if [ ! -f "${swapfile}" ]; then
        fallocate -l "${size_gb}G" "${swapfile}"
        chmod 600 "${swapfile}"
        mkswap "${swapfile}"
    fi
    swapon "${swapfile}"
    grep -q "${swapfile}" /etc/fstab \
        || echo "${swapfile} none swap sw 0 0" >> /etc/fstab
    log_ok "Swap aktif: ${size_gb}G"
}

# ── node_exporter (tüm node'lar için ortak — DRY) ────────────────────────────
install_node_exporter() {
    local listen_addr="${1:?listen_addr gerekli (örn. 10.10.0.2)}"
    local VER="1.8.2"
    log_step "node_exporter (${listen_addr}:9100)"

    if ! /usr/local/bin/node_exporter --version 2>&1 | grep -q "${VER}"; then
        # Çalışıyorsa önce durdur (mv üzerinde Text file busy önlemi)
        systemctl stop node-exporter 2>/dev/null || true
        curl -fsSL "https://github.com/prometheus/node_exporter/releases/download/v${VER}/node_exporter-${VER}.linux-amd64.tar.gz" \
            | tar xz -C /tmp/
        mv "/tmp/node_exporter-${VER}.linux-amd64/node_exporter" /usr/local/bin/
        rm -rf "/tmp/node_exporter-${VER}.linux-amd64"
    fi

    # Service dosyasını her çalıştırmada yaz — listen_addr değişmiş olabilir
    cat > /etc/systemd/system/node-exporter.service <<EOF
[Unit]
Description=Prometheus Node Exporter
[Service]
Type=simple
User=tucibeyin
ExecStart=/usr/local/bin/node_exporter --web.listen-address=${listen_addr}:9100
Restart=always
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now node-exporter
    log_ok "node_exporter aktif (${listen_addr}:9100)"
}

# ── UFW reset + enable ────────────────────────────────────────────────────────
ufw_enable() {
    log_step "UFW aktive"
    ufw --force enable
    log_ok "UFW aktif"
}

# ── Secrets uygula ────────────────────────────────────────────────────────────
apply_secrets() {
    local secrets_file="${1:?Secrets dosyası belirtilmeli}"
    shift
    local config_dirs=("$@")

    [ -f "${secrets_file}" ] || { log_err "Secrets dosyası bulunamadı: ${secrets_file}"; return 1; }

    log_step "Secrets uygulanıyor"
    local applied=0
    local skipped=0

    while IFS='=' read -r key value || [ -n "${key}" ]; do
        [[ "${key}" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${key// }" ]] && continue
        [[ -z "${value}" ]] && { ((skipped++)); continue; }

        key="${key#"${key%%[![:space:]]*}"}"; key="${key%"${key##*[![:space:]]}"}"
        value="${value#"${value%%[![:space:]]*}"}"; value="${value%"${value##*[![:space:]]}"}"

        # Sed replacement'ta özel karakterleri kaçır (& \ |)
        local escaped_val="${value//\\/\\\\}"
        escaped_val="${escaped_val//&/\\&}"
        escaped_val="${escaped_val//|/\\|}"

        local found=0
        for dir in "${config_dirs[@]}"; do
            [ -d "${dir}" ] || continue
            while IFS= read -r -d '' file; do
                if grep -qF "<${key}>" "${file}" 2>/dev/null; then
                    sed -i "s|<${key}>|${escaped_val}|g" "${file}"
                    found=1
                fi
            done < <(find "${dir}" -type f -print0)
        done

        if [ "${found}" -eq 1 ]; then
            log_ok "  ${key}"
            applied=$((applied + 1))
        else
            skipped=$((skipped + 1))
        fi
    done < "${secrets_file}"

    log_ok "Secrets uygulandı: ${applied} başarılı, ${skipped} atlandı"

    # Config dosyaları normalize: tucibeyin sahipliği + 700/600 izinleri
    if [ -d /project/teqlif/config ]; then
        chown -R tucibeyin:tucibeyin /project/teqlif/config
        find /project/teqlif/config -type d -exec chmod 700 {} +
        find /project/teqlif/config -type f -exec chmod 600 {} +
        log_ok "Config dosyaları normalize edildi (tucibeyin 700/600)"
    fi

    # TLS private key: root:tucibeyin 640 — nginx root olarak okur, tucibeyin backup alabilir
    if [ -d /etc/ssl/teqlif ]; then
        find /etc/ssl/teqlif -name '*.key' -exec chown root:tucibeyin {} + -exec chmod 640 {} + 2>/dev/null || true
        find /etc/ssl/teqlif -name '*.crt' -exec chmod 644 {} + 2>/dev/null || true
        log_ok "TLS izinleri normalize edildi (/etc/ssl/teqlif *.key → root:tucibeyin 640)"
    fi

    # WireGuard: dizin 710 (tucibeyin traverse, ls yapamaz), dosyalar root:tucibeyin 640
    # rsync explicit dosya path'iyle çalışır (dizin read izni gerekmez)
    # wg-quick root olarak okur; tucibeyin yalnız bilinen dosyalara erişebilir
    if [ -d /etc/wireguard ]; then
        chown root:tucibeyin /etc/wireguard && chmod 710 /etc/wireguard 2>/dev/null || true
        for _wgf in /etc/wireguard/privatekey /etc/wireguard/wg0.conf /etc/wireguard/pubkey; do
            [ -f "${_wgf}" ] && chown root:tucibeyin "${_wgf}" && chmod 640 "${_wgf}" 2>/dev/null || true
        done
        log_ok "WireGuard izinleri normalize edildi (/etc/wireguard 710, privatekey+wg0.conf → root:tucibeyin 640)"
    fi

    if command -v shred &>/dev/null; then
        shred -u "${secrets_file}"
        log_ok "Secrets dosyası güvenli silindi: ${secrets_file}"
    else
        rm -f "${secrets_file}"
        log_warn "Secrets dosyası silindi (shred yok): ${secrets_file}"
    fi
}

# ── Özet yazdır ───────────────────────────────────────────────────────────────
print_summary() {
    local node_id="${1}"
    local wg_ip="${2}"
    shift 2
    local next_steps=("$@")
    echo ""
    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
    printf "${BOLD}${GREEN}║  %-50s  ║${NC}\n" "${node_id} bootstrap TAMAMLANDI"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}WireGuard Public Key (secrets.env Bölüm 3'e ekle):${NC}"
    cat /etc/wireguard/pubkey 2>/dev/null && echo "" || true
    if [ ${#next_steps[@]} -gt 0 ]; then
        echo -e "${YELLOW}Sonraki adımlar:${NC}"
        local i=1
        for step in "${next_steps[@]}"; do
            echo -e "  ${i}. ${step}"
            ((i++))
        done
    fi
    echo ""
}
