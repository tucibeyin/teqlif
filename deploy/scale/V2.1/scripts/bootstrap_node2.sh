#!/bin/bash
# bootstrap_node2.sh — teqlif V2.1 Backup+ClickHouse+Redis-HA (OVH Saarbrücken DE, 10.10.0.2)
# Bare metal HDD RAID-1 | ClickHouse + Backup + Redis Replica + Failover
# NOT: Prometheus/Grafana/Loki/Alertmanager nodeMonitor'da (10.10.0.99) — burada kurulmaz.

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
    setup_crowdsec
    setup_node_conf    "${NODE_DIR}"
    setup_wg_keygen
    setup_wg_config    "${NODE_DIR}"
    setup_wg_sudoers
    setup_redis_vip_sudoers_node2
    setup_sysctl       "${NODE_DIR}"
    setup_hdd_io_scheduler
    ufw_node2
    install_pg_server
    install_clickhouse
    setup_clickhouse   "${NODE_DIR}"
    install_backup_tools
    setup_backup_services "${NODE_DIR}"
    install_promtail
    setup_promtail "${NODE_DIR}" "${NODE_ID}"
    install_node_exporter
    setup_redis_replica  "${NODE_DIR}"
    setup_redis_failover "${NODE_DIR}"
    setup_dr_app "${NODE_DIR}"

    if [ -n "${SECRETS_FILE:-}" ]; then
        apply_secrets "${SECRETS_FILE}" \
            /project/teqlif/config /etc/wireguard /etc/clickhouse-server /etc/ssl/teqlif /etc/redis
    fi

    print_summary "${NODE_ID}" "${WG_IP}" \
        "wg_mesh_apply.sh çalıştır" \
        "wg-quick up wg0 && systemctl enable wg-quick@wg0" \
        "node1'de replication user ve slot oluştur (plan §3.2)" \
        "systemctl start teqlif-pg-receivewal" \
        "systemctl start clickhouse-server" \
        "Redis failover aktif: systemctl status teqlif-redis-failover.timer" \
        "Restic repo başlatma (Faz 2 sonrası): sudo -u tucibeyin restic init" \
        "Offsite timer başlatma (Faz 2 sonrası): systemctl start teqlif-offsite-sync.timer teqlif-offsite-wal.timer"
}

setup_backup_directories() {
    log_step "Backup dizinleri"
    mkdir -p /project/teqlif/backups/{pg_dump,pg_wal,pg_basebackup,redis,minio,clickhouse,loki,stalwart,uptime_kuma,nodemonitor_config}
    chown -R tucibeyin:tucibeyin /project/teqlif/backups
    chmod -R 700 /project/teqlif/backups
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

install_pg_server() {
    log_step "PostgreSQL ${PG_VERSION} Server + Client (Standby/DR node)"
    apt-get install -y -qq "postgresql-${PG_VERSION}" "postgresql-client-${PG_VERSION}"
    # Cluster standby/DR modunda: servis otomatik başlamayacak
    systemctl disable --now postgresql 2>/dev/null || true
    # conf.d dizinini hazırla (runbook.sh recovery.conf için ihtiyaç duyar)
    mkdir -p "/etc/postgresql/${PG_VERSION}/main/conf.d"
    chown -R postgres:postgres "/etc/postgresql/${PG_VERSION}/main/conf.d"
    log_ok "postgresql-${PG_VERSION} kuruldu, standby modda durduruldu"
}

install_backup_tools() {
    log_step "restic + rclone (backup motorları)"
    apt-get install -y -qq restic
    # rclone — Adım 12'de restic ile değiştirilecek; offsite_sync.sh için şimdilik gerekli
    if ! command -v rclone &>/dev/null; then
        curl -fsSL https://rclone.org/install.sh | bash
    fi
    log_ok "restic $(restic version | awk '{print $2}') + rclone $(rclone --version 2>/dev/null | head -1 | awk '{print $2}') kuruldu"
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

setup_dr_app() {
    local node_dir="${1}"
    log_step "DR uygulama sunucusu (nginx DR config + teqlif-dr.service)"

    # nginx conf güncelle
    cp "${node_dir}/resources/nginx/nginx.conf" /etc/nginx/nginx.conf
    cp "${node_dir}/resources/nginx/conf.d/"*.conf /etc/nginx/conf.d/

    # CF cert dizinini hazırla (apply_secrets doldurur)
    mkdir -p /etc/ssl/teqlif

    # teqlif-dr.service yükle (disabled — sadece DR runbook'u aktif eder)
    cp "${node_dir}/systemd/teqlif-dr.service" /etc/systemd/system/
    systemctl daemon-reload
    # nginx de disabled — sadece DR runbook'u aktif eder
    systemctl disable nginx 2>/dev/null || true

    log_ok "DR nginx config + teqlif-dr.service kuruldu (devre dışı)"
    log_warn ".env.dr eksik: runbook öncesinde /project/teqlif/config/.env.dr dosyasını oluşturun"
    log_warn "  Gerekli değişkenler: DATABASE_URL (127.0.0.1:5432), REDIS_URL, SECRET_KEY vb."
    log_warn "CF origin sertifikası eksik: apply_secrets ile veya manuel olarak yerleştirin:"
    log_warn "  /etc/ssl/teqlif/cf-origin.crt ve cf-origin.key"
}

setup_redis_replica() {
    local node_dir="${1}"
    log_step "Redis Replica konfigürasyonu"
    # Replica veri dizini
    mkdir -p /var/lib/redis-replica
    chown redis:redis /var/lib/redis-replica
    chmod 750 /var/lib/redis-replica
    # Log dizini
    mkdir -p /var/log/redis
    chown redis:adm /var/log/redis 2>/dev/null || chown redis:redis /var/log/redis
    # Şablon → /etc/redis/redis-replica.conf (apply_secrets parola doldurur)
    cp "${node_dir}/resources/redis/redis-replica.conf.template" /etc/redis/redis-replica.conf
    chown root:redis /etc/redis/redis-replica.conf
    chmod 640 /etc/redis/redis-replica.conf
    # Servis dosyası
    cp "${node_dir}/systemd/teqlif-redis-replica.service" /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable teqlif-redis-replica.service
    log_ok "Redis Replica konfigürasyonu kuruldu (apply_secrets ile parola doldur)"
}

setup_redis_failover() {
    local node_dir="${1}"
    log_step "Redis failover timer"
    chmod +x "${node_dir}/resources/scripts/redis_failover.sh"
    cp "${node_dir}/systemd/teqlif-redis-failover.service" /etc/systemd/system/
    cp "${node_dir}/systemd/teqlif-redis-failover.timer"   /etc/systemd/system/
    mkdir -p /var/lib/teqlif-redis-failover
    chown tucibeyin:tucibeyin /var/lib/teqlif-redis-failover
    systemctl daemon-reload
    systemctl enable --now teqlif-redis-failover.timer
    log_ok "Redis failover timer aktif (her 10s)"
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
    # Tüm backup + bakım timer'ları enable (başlatma adım adım print_summary'de)
    systemctl enable \
        teqlif-pg-dump.timer \
        teqlif-pg-basebackup.timer \
        teqlif-pg-wal-cleanup.timer \
        teqlif-redis-backup.timer \
        teqlif-clickhouse-backup.timer \
        teqlif-minio-backup.timer \
        teqlif-loki-backup.timer \
        teqlif-uptime-kuma-backup.timer \
        teqlif-nodemonitor-config-backup.timer \
        teqlif-mail-backup.timer \
        teqlif-offsite-sync.timer \
        teqlif-offsite-wal.timer
    # Backup için minimal env (minio credentials)
    cat > /project/teqlif/config/.env.backup <<'ENVEOF'
MINIO_ROOT_USER=<minio_root_user>
MINIO_ROOT_PASSWORD=<minio_root_password>
TEQLIF_DB_PASSWORD=<teqlif_db_password>
CORE_REDIS_PASS=<core_redis_pass>
REPL_PASSWORD=<teqlif_repl_password>
TELEGRAM_BOT_TOKEN=<telegram_bot_token>
TELEGRAM_CHAT_ID=<telegram_chat_id>
# node101 offsite restic (Faz 2 sonrası doldur)
RESTIC_REST_USER=<restic_rest_user>
RESTIC_REST_PASSWORD=<restic_rest_password>
RESTIC_PASSWORD=<restic_aes_password>
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
