#!/bin/bash
# bootstrap_node9.sh — teqlif V2.0 Monitor + Backup + ClickHouse (OVH KS-1-B, 10.10.0.13)
# Çalıştır: sudo bash bootstrap_node9.sh
#
# Donanım: 32 vCore, 64GB RAM, 3.5TB RAID-1 HDD + 150GB SSD (root)
# Rol: Prometheus, Loki, Alertmanager, Grafana, PostgreSQL WAL backup,
#      ClickHouse analytics, MinIO cold archive, B2 off-site backup

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

NODE_ID="node9"
WG_IP="10.10.0.13"
REPO_DIR="${REPO_DIR:-/var/www/teqlif.com}"
NODE_DIR="${REPO_DIR}/deploy/scale/V2.0/${NODE_ID}"
PG_VERSION="17"
PROMETHEUS_VER="${PROMETHEUS_VER:-2.54.1}"
LOKI_VER="${LOKI_VER:-3.2.0}"
ALERTMANAGER_VER="${ALERTMANAGER_VER:-0.27.0}"
MC_RELEASE="${MC_RELEASE:-RELEASE.2024-11-07T00-52-20Z}"

main() {
    check_root
    check_debian
    echo -e "${BOLD}${CYAN}teqlif V2.0 — ${NODE_ID} bootstrap (${WG_IP}) [MONITOR + BACKUP]${NC}"

    install_base_packages
    install_pgdg_repo
    setup_user "${SSH_PUBKEY:-}"
    setup_directories
    setup_directories_node9
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
    ufw_monitor
    install_postgresql_backup
    install_monitoring_stack
    install_clickhouse
    install_mc_client
    setup_backup_scripts "${NODE_DIR}"
    setup_env_template \
        "${NODE_DIR}/resources/.env.production.template" \
        "/etc/teqlif/.env.production"
    install_promtail
    setup_promtail "${NODE_DIR}" "${NODE_ID}"
    setup_guardian "${NODE_DIR}"

    print_summary "${NODE_ID}" "${WG_IP}" \
        "wg0.conf peer <PublicKey> placeholder'larını doldur" \
        "/etc/teqlif/.env.production içindeki <placeholder>'ları doldur (DB backup için PG creds gerekli)" \
        "Prometheus: /etc/prometheus/prometheus.yml scrape hedeflerini doldur (plan §10.3)" \
        "Alertmanager: /etc/alertmanager/alertmanager.yml Telegram webhook doldur" \
        "Loki: /etc/loki/loki.yaml zaten hazır" \
        "ClickHouse: /etc/clickhouse-server/ yapılandırmasını kontrol et (plan §4.8)" \
        "Backup scripts: /etc/teqlif/.env.production içindeki B2_BUCKET + RCLONE_CONFIG doldur" \
        "rclone config: rclone config → B2 hesabı ekle (plan §10.6.7)" \
        "/opt/teqlif/backups/postgres → /data/teqlif_backups/postgres symlink kontrol et (plan §10.6.1)" \
        "wg-quick up wg0  →  systemctl enable --now wg-quick@wg0" \
        "systemctl start prometheus loki alertmanager grafana-server" \
        "systemctl start teqlif-pg-receivewal teqlif-guardian" \
        "Grafana: http://10.10.0.13:3000 (admin/admin → şifre değiştir)"
}

install_pgdg_repo() {
    log_step "PGDG apt repo"
    [ -f /etc/apt/sources.list.d/pgdg.list ] && { log_info "PGDG repo zaten var"; return; }
    apt-get install -y -qq gnupg
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
        | gpg --dearmor | tee /usr/share/keyrings/pgdg.gpg > /dev/null
    echo "deb [signed-by=/usr/share/keyrings/pgdg.gpg] https://apt.postgresql.org/pub/repos/apt \
$(. /etc/os-release; echo "$VERSION_CODENAME")-pgdg main" \
        | tee /etc/apt/sources.list.d/pgdg.list
    apt-get update -qq
    log_ok "PGDG repo eklendi"
}

setup_directories_node9() {
    log_step "node9 backup dizin yapısı"
    # 3.5TB HDD RAID → /data (ayrı mount)
    mkdir -p /data/teqlif_backups/{postgres/{wal,basebackup,dump},redis,minio}
    mkdir -p /data/clickhouse-backups
    # SSD root'a symlink → scriptler /opt/teqlif/backups/ kullanır
    mkdir -p /opt/teqlif
    ln -sfn /data/teqlif_backups /opt/teqlif/backups 2>/dev/null || true
    chown -R tucibeyin:tucibeyin /data/teqlif_backups /data/clickhouse-backups /opt/teqlif
    mkdir -p /var/log/teqlif
    chown tucibeyin:tucibeyin /var/log/teqlif
    log_ok "Backup dizinleri hazır (/data → /opt/teqlif/backups symlink)"
    log_warn "/data bağlantısını kontrol et: df -h /data — HDD RAID ayrı mount olmalı"
}

ufw_monitor() {
    log_step "UFW (monitor — sadece WireGuard)"
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 22/tcp
    ufw allow 51820/udp
    ufw allow in on wg0 from 10.10.0.0/24
    ufw allow in on wg0 proto udp to any port 9901
    # Grafana sadece WireGuard üzerinden (3000 internete AÇILMAZ)
    ufw_enable
}

install_postgresql_backup() {
    log_step "PostgreSQL ${PG_VERSION} (WAL backup alıcı)"
    apt-get install -y -qq "postgresql-${PG_VERSION}" "postgresql-client-${PG_VERSION}"
    systemctl stop postgresql 2>/dev/null || true
    log_ok "PostgreSQL kuruldu (WAL alıcı rolü, prod PG'ye bağlanacak)"
}

install_monitoring_stack() {
    log_step "Prometheus + Loki + Alertmanager + Grafana"
    # Grafana repo (promtail için zaten eklenmişti, loki da buradan)
    install_grafana_repo
    apt-get install -y -qq loki grafana

    # Prometheus
    local prom_url="https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VER}/prometheus-${PROMETHEUS_VER}.linux-amd64.tar.gz"
    if ! command -v prometheus &>/dev/null; then
        local tmp="/tmp/teqlif-bootstrap-prom"
        mkdir -p "${tmp}"
        curl -fsSL "${prom_url}" | tar -xz -C "${tmp}" --strip-components=1
        cp "${tmp}/prometheus" "${tmp}/promtool" /usr/local/bin/
        rm -rf "${tmp}"
        log_ok "Prometheus ${PROMETHEUS_VER} kuruldu"
    else
        log_info "Prometheus zaten kurulu"
    fi

    # Alertmanager
    local am_url="https://github.com/prometheus/alertmanager/releases/download/v${ALERTMANAGER_VER}/alertmanager-${ALERTMANAGER_VER}.linux-amd64.tar.gz"
    if ! command -v alertmanager &>/dev/null; then
        local tmp="/tmp/teqlif-bootstrap-am"
        mkdir -p "${tmp}"
        curl -fsSL "${am_url}" | tar -xz -C "${tmp}" --strip-components=1
        cp "${tmp}/alertmanager" "${tmp}/amtool" /usr/local/bin/
        rm -rf "${tmp}"
        log_ok "Alertmanager ${ALERTMANAGER_VER} kuruldu"
    else
        log_info "Alertmanager zaten kurulu"
    fi

    # Config dosyalarını kopyala
    mkdir -p /etc/prometheus /etc/loki /etc/alertmanager
    local prom_src="${NODE_DIR}/resources/prometheus"
    [ -d "${prom_src}" ] && cp -r "${prom_src}"/* /etc/prometheus/ 2>/dev/null || true
    local loki_src="${NODE_DIR}/resources/loki"
    [ -d "${loki_src}" ] && cp -r "${loki_src}"/* /etc/loki/ 2>/dev/null || true
    local am_src="${NODE_DIR}/resources/alertmanager"
    [ -d "${am_src}" ] && cp -r "${am_src}"/* /etc/alertmanager/ 2>/dev/null || true

    # systemd servis dosyaları (node9/systemd/ → yok, inline oluştur)
    setup_monitoring_services

    systemctl daemon-reload
    systemctl enable prometheus loki alertmanager grafana-server
    log_ok "Monitoring stack enable edildi (config doldurulunca başlar)"
}

setup_monitoring_services() {
    # Prometheus servis
    cat > /etc/systemd/system/prometheus.service <<'EOF'
[Unit]
Description=Prometheus
After=network.target

[Service]
User=tucibeyin
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/data/teqlif_backups/prometheus \
  --storage.tsdb.retention.time=7d \
  --web.listen-address=10.10.0.13:9090
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    mkdir -p /data/teqlif_backups/prometheus
    chown tucibeyin:tucibeyin /data/teqlif_backups/prometheus

    # Alertmanager servis
    cat > /etc/systemd/system/alertmanager.service <<'EOF'
[Unit]
Description=Alertmanager
After=network.target

[Service]
User=tucibeyin
ExecStart=/usr/local/bin/alertmanager \
  --config.file=/etc/alertmanager/alertmanager.yml \
  --storage.path=/data/teqlif_backups/alertmanager \
  --web.listen-address=10.10.0.13:9093
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    mkdir -p /data/teqlif_backups/alertmanager
    chown tucibeyin:tucibeyin /data/teqlif_backups/alertmanager

    # Grafana default port zaten 3000, sadece bind adresini sınırla
    mkdir -p /etc/grafana
    grep -q "^http_addr" /etc/grafana/grafana.ini 2>/dev/null \
        || echo -e "\n[server]\nhttp_addr = 10.10.0.13" >> /etc/grafana/grafana.ini
}

install_clickhouse() {
    log_step "ClickHouse"
    if command -v clickhouse-server &>/dev/null; then
        log_info "ClickHouse zaten kurulu"; return
    fi
    apt-get install -y -qq apt-transport-https ca-certificates
    curl -fsSL 'https://packages.clickhouse.com/rpm/lts/repodata/repomd.xml.key' \
        | gpg --dearmor | tee /usr/share/keyrings/clickhouse-keyring.gpg > /dev/null
    echo "deb [signed-by=/usr/share/keyrings/clickhouse-keyring.gpg] \
https://packages.clickhouse.com/deb stable main" \
        | tee /etc/apt/sources.list.d/clickhouse.list
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        clickhouse-server clickhouse-client
    # Backup disk config
    local ch_src="${NODE_DIR}/resources/clickhouse"
    [ -d "${ch_src}" ] && cp -r "${ch_src}"/* /etc/clickhouse-server/ 2>/dev/null || true
    mkdir -p /data/clickhouse-backups
    chown clickhouse:clickhouse /data/clickhouse-backups
    cat >> /etc/sudoers.d/guardian-systemctl <<'EOF'
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/systemctl start clickhouse-server
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop clickhouse-server
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart clickhouse-server
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/systemctl reset-failed clickhouse-server
EOF
    chmod 440 /etc/sudoers.d/guardian-systemctl
    systemctl enable clickhouse-server
    log_ok "ClickHouse kuruldu (plan §4.8 yapılandırması gerekiyor)"
}

install_mc_client() {
    log_step "MinIO mc client (backup için)"
    if ! command -v mc &>/dev/null; then
        curl -fsSL \
            "https://dl.min.io/client/mc/release/linux-amd64/archive/mc.${MC_RELEASE}" \
            -o /usr/local/bin/mc
        chmod 755 /usr/local/bin/mc
        log_ok "mc kuruldu"
    else
        log_info "mc zaten kurulu"
    fi
    # rclone (B2 off-site için)
    if ! command -v rclone &>/dev/null; then
        curl -fsSL https://rclone.org/install.sh | bash
        log_ok "rclone kuruldu"
    else
        log_info "rclone zaten kurulu"
    fi
}

setup_backup_scripts() {
    local node_dir="${1}"
    log_step "Backup scripts + systemd timer'lar"
    local scripts_src="${node_dir}/resources/scripts"
    if [ -d "${scripts_src}" ]; then
        cp "${scripts_src}"/*.sh /usr/local/bin/
        chmod 755 /usr/local/bin/pg_basebackup.sh \
                  /usr/local/bin/pg_dump_backup.sh \
                  /usr/local/bin/redis_backup.sh \
                  /usr/local/bin/clickhouse_backup.sh \
                  /usr/local/bin/offsite_sync.sh \
                  /usr/local/bin/minio_backup.sh 2>/dev/null || true
        log_ok "Backup scriptleri /usr/local/bin/'e kopyalandı"
    fi
    # systemd timer'lar
    for unit in \
        teqlif-pg-receivewal.service \
        teqlif-pg-basebackup.service teqlif-pg-basebackup.timer \
        teqlif-pg-dump.service teqlif-pg-dump.timer \
        teqlif-redis-backup.service teqlif-redis-backup.timer \
        teqlif-clickhouse-backup.service teqlif-clickhouse-backup.timer \
        teqlif-offsite-sync.service teqlif-offsite-sync.timer \
        teqlif-minio-backup.service teqlif-minio-backup.timer; do
        [ -f "${node_dir}/systemd/${unit}" ] \
            && cp "${node_dir}/systemd/${unit}" "/etc/systemd/system/${unit}"
    done
    systemctl daemon-reload
    systemctl enable \
        teqlif-pg-receivewal \
        teqlif-pg-basebackup.timer \
        teqlif-pg-dump.timer \
        teqlif-redis-backup.timer \
        teqlif-clickhouse-backup.timer \
        teqlif-offsite-sync.timer \
        teqlif-minio-backup.timer
    log_ok "Backup timer'lar enable edildi (.env.production doldurulunca çalışır)"
}

main "$@"
