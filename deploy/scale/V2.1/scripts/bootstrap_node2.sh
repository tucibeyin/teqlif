#!/bin/bash
# bootstrap_node2.sh — teqlif V2.1 Backup+Monitoring+ClickHouse (OVH Saarbrücken DE, 10.10.0.2)
# Bare metal HDD RAID-1 | ClickHouse + Prometheus + Grafana + Loki + Alertmanager + Backup

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

NODE_ID="node2"
WG_IP="10.10.0.2"
REPO_DIR="${REPO_DIR:-/var/www/teqlif.com}"
NODE_DIR="${REPO_DIR}/deploy/scale/V2.1/${NODE_ID}"
SECRETS_FILE="${SECRETS_FILE:-}"
PG_VERSION="17"

main() {
    check_root
    check_debian
    echo -e "${BOLD}${CYAN}teqlif V2.1 — ${NODE_ID} bootstrap (${WG_IP}) [BACKUP+MONITORING]${NC}"

    install_base_packages
    install_pgdg_repo
    setup_user "${SSH_PUBKEY:-}"
    setup_teqlif_directories
    setup_backup_directories
    setup_ntp
    setup_autoupdates
    setup_limits
    # HDD bare metal: 32GB RAM, swap gerekmiyor
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
    setup_hdd_io_scheduler
    ufw_node2
    install_pg_client
    install_clickhouse
    setup_clickhouse   "${NODE_DIR}"
    install_prometheus
    setup_prometheus   "${NODE_DIR}"
    install_grafana
    install_loki
    setup_loki         "${NODE_DIR}"
    install_alertmanager
    setup_alertmanager "${NODE_DIR}"
    install_rclone
    setup_backup_services "${NODE_DIR}"
    install_promtail
    setup_promtail "${NODE_DIR}" "${NODE_ID}"
    install_node_exporter

    if [ -n "${SECRETS_FILE:-}" ]; then
        apply_secrets "${SECRETS_FILE}" \
            /project/teqlif/config /etc/wireguard /etc/clickhouse-server \
            /etc/prometheus
    fi

    print_summary "${NODE_ID}" "${WG_IP}" \
        "wg_mesh_apply.sh çalıştır" \
        "wg-quick up wg0 && systemctl enable wg-quick@wg0" \
        "node1'de replication user ve slot oluştur (plan §3.2)" \
        "systemctl start teqlif-pg-receivewal" \
        "systemctl start clickhouse-server" \
        "systemctl start prometheus loki prometheus-alertmanager grafana-server" \
        "Backup timer'larını etkinleştir: systemctl enable --now teqlif-*.timer" \
        "rclone config → b2backup remote ekle"
}

setup_backup_directories() {
    log_step "Backup dizinleri"
    mkdir -p /project/teqlif/backups/{pg_dump,pg_wal,redis,minio}
    chown -R tucibeyin:tucibeyin /project/teqlif/backups
    log_ok "Backup dizinleri: /project/teqlif/backups/"
}

setup_hdd_io_scheduler() {
    log_step "HDD I/O Scheduler (mq-deadline) + readahead"
    cat > /etc/udev/rules.d/60-hdd-scheduler.rules <<'EOF'
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/scheduler}="mq-deadline"
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/read_ahead_kb}="8192"
EOF
    for dev in /sys/block/sd*/queue/scheduler; do
        [ -f "${dev}" ] && echo mq-deadline > "${dev}" 2>/dev/null || true
    done
    for dev in /sys/block/sd*; do
        [ -d "${dev}" ] && blockdev --setra 8192 "/dev/$(basename ${dev})" 2>/dev/null || true
    done
    log_ok "HDD scheduler=mq-deadline, readahead=8192"
}

ufw_node2() {
    log_step "UFW (node2 — Monitoring)"
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 22/tcp
    ufw allow 51820/udp
    ufw allow in on wg0 from 10.10.0.0/24
    ufw_enable
}

install_pg_client() {
    log_step "PostgreSQL client (pg_dump, pg_receivewal)"
    apt-get install -y -qq "postgresql-client-${PG_VERSION}"
    log_ok "pg_client-${PG_VERSION} kuruldu"
}

install_clickhouse() {
    log_step "ClickHouse"
    apt-get install -y -qq apt-transport-https ca-certificates
    curl -fsSL https://packages.clickhouse.com/rpm/lts/repodata/repomd.xml.key \
        | gpg --dearmor | tee /usr/share/keyrings/clickhouse.gpg > /dev/null
    echo "deb [signed-by=/usr/share/keyrings/clickhouse.gpg] https://packages.clickhouse.com/deb stable main" \
        | tee /etc/apt/sources.list.d/clickhouse.list
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        clickhouse-server clickhouse-client
    log_ok "ClickHouse kuruldu"
}

setup_clickhouse() {
    local node_dir="${1}"
    log_step "ClickHouse config"
    mkdir -p /etc/clickhouse-server/config.d /etc/clickhouse-server/users.d
    cp "${node_dir}/resources/clickhouse/config.d/teqlif.xml" \
        /etc/clickhouse-server/config.d/teqlif.xml
    cp "${node_dir}/resources/clickhouse/users.d/teqlif.xml" \
        /etc/clickhouse-server/users.d/teqlif.xml
    systemctl enable clickhouse-server
    log_ok "ClickHouse config kopyalandı"
}

install_prometheus() {
    log_step "Prometheus"
    install_grafana_repo
    apt-get install -y -qq prometheus
    log_ok "Prometheus kuruldu"
}

setup_prometheus() {
    local node_dir="${1}"
    log_step "Prometheus config"
    cp "${node_dir}/resources/prometheus/prometheus.yml" /etc/prometheus/prometheus.yml
    cp "${node_dir}/resources/prometheus/alert_rules.yml" /etc/prometheus/alert_rules.yml
    systemctl enable --now prometheus
    log_ok "Prometheus aktif"
}

install_grafana() {
    log_step "Grafana"
    install_grafana_repo
    apt-get install -y -qq grafana
    systemctl enable --now grafana-server
    log_ok "Grafana aktif (http://10.10.0.2:3000)"
}

install_loki() {
    log_step "Loki"
    install_grafana_repo
    apt-get install -y -qq loki
    log_ok "Loki kuruldu"
}

setup_loki() {
    local node_dir="${1}"
    log_step "Loki config"
    mkdir -p /var/lib/loki/{chunks,rules,compactor,index}
    cp "${node_dir}/resources/loki/config.yml" /etc/loki/config.yml
    systemctl enable --now loki
    log_ok "Loki aktif"
}

install_alertmanager() {
    log_step "Alertmanager"
    install_grafana_repo
    apt-get install -y -qq prometheus-alertmanager
    log_ok "Alertmanager kuruldu"
}

setup_alertmanager() {
    local node_dir="${1}"
    log_step "Alertmanager config"
    cp "${node_dir}/resources/alertmanager/alertmanager.yml" /etc/prometheus/alertmanager.yml
    systemctl enable prometheus-alertmanager
    log_ok "prometheus-alertmanager enable edildi"
}

install_rclone() {
    log_step "rclone"
    apt-get install -y -qq unzip
    curl -fsSL https://rclone.org/install.sh | bash
    log_ok "rclone kuruldu"
}

setup_backup_services() {
    local node_dir="${1}"
    log_step "Backup systemd servisleri"
    # Script dosyalarını çalıştırılabilir yap
    chmod +x "${node_dir}/resources/scripts/"*.sh
    # Systemd dosyaları
    for f in "${node_dir}/systemd/"*.service "${node_dir}/systemd/"*.timer; do
        [ -f "${f}" ] && cp "${f}" /etc/systemd/system/ || true
    done
    systemctl daemon-reload
    # WAL stream her zaman açık
    systemctl enable teqlif-pg-receivewal
    # Timer'lar enable ama başlatma adım adım yapılır
    systemctl enable \
        teqlif-pg-dump.timer \
        teqlif-redis-backup.timer \
        teqlif-minio-backup.timer \
        teqlif-offsite-sync.timer
    # Backup için minimal env (minio credentials)
    cat > /project/teqlif/config/.env.backup <<'ENVEOF'
MINIO_ROOT_USER=<minio_root_user>
MINIO_ROOT_PASSWORD=<minio_root_password>
TEQLIF_DB_PASSWORD=<teqlif_db_password>
CORE_REDIS_PASS=<core_redis_pass>
REPL_PASSWORD=<teqlif_repl_password>
ENVEOF
    chmod 600 /project/teqlif/config/.env.backup
    log_ok "Backup servisleri enable edildi"
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
ExecStart=/usr/local/bin/node_exporter --web.listen-address=10.10.0.2:9100
Restart=always
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now node-exporter
    log_ok "node_exporter aktif (10.10.0.2:9100)"
}

main "$@"
