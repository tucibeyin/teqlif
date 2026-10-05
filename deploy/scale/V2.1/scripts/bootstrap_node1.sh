#!/bin/bash
# bootstrap_node1.sh — teqlif V2.1 Core (OVH Gravelines FR, 10.10.0.1)
# Bare metal NVMe RAID-1 | PostgreSQL + PgBouncer + Redis×3 + MinIO + FastAPI + nginx
# Çalıştır: sudo bash bootstrap_node1.sh
# Ortam: SECRETS_FILE=/tmp/teqlif-secrets.env SSH_PUBKEY="ssh-ed25519 ..."

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

NODE_ID="node1"
WG_IP="10.10.0.1"
REPO_DIR="${REPO_DIR:-/var/www/teqlif.com}"
NODE_DIR="${REPO_DIR}/deploy/scale/V2.1/${NODE_ID}"
SECRETS_FILE="${SECRETS_FILE:-}"
PG_VERSION="17"
LIVEKIT_VER="${LIVEKIT_VER:-v1.13.7}"
MINIO_RELEASE="${MINIO_RELEASE:-RELEASE.2025-09-07T16-13-09Z}"

main() {
    check_root
    check_debian
    echo -e "${BOLD}${CYAN}teqlif V2.1 — ${NODE_ID} bootstrap (${WG_IP}) [CORE]${NC}"

    install_base_packages
    install_pgdg_repo
    setup_user "${SSH_PUBKEY:-}"
    setup_teqlif_directories
    setup_ntp
    setup_autoupdates
    setup_limits
    # NVMe bare metal: swap gerekmiyor (32GB ECC RAM)
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
    setup_nvme_io_scheduler
    ufw_node1
    install_postgresql
    install_pgbouncer
    install_redis
    setup_redis_instances "${NODE_DIR}"
    install_minio
    setup_minio        "${NODE_DIR}"
    setup_venv "${REPO_DIR}"
    setup_env_template \
        "${NODE_DIR}/resources/.env.production.template" \
        "/project/teqlif/config/.env.production"
    setup_core_services "${NODE_DIR}"
    install_nginx
    setup_nginx "${NODE_DIR}"
    install_certbot
    install_promtail
    setup_promtail "${NODE_DIR}" "${NODE_ID}"
    install_node_exporter
    install_postgres_exporter

    if [ -n "${SECRETS_FILE:-}" ]; then
        apply_secrets "${SECRETS_FILE}" \
            /project/teqlif/config /etc/wireguard /project/teqlif/config/redis
    fi

    print_summary "${NODE_ID}" "${WG_IP}" \
        "secrets.env Bölüm 3: pubkey → $(cat /etc/wireguard/pubkey)" \
        "wg_mesh_apply.sh çalıştır (tüm pubkey'ler dolduktan sonra)" \
        "wg-quick up wg0 && systemctl enable wg-quick@wg0" \
        "postgresql.conf: shared_buffers=8GB, work_mem=64MB, huge_pages=on" \
        "pg_hba.conf: teqlif satırı + node2 replicator satırı ekle" \
        "createdb teqlif && createuser teqlif (plan §2.1)" \
        "alembic upgrade head" \
        "certbot certonly --nginx -d uploads.teqlif.com (LE cert)" \
        "Cloudflare origin cert → /etc/ssl/teqlif/cf-origin.{crt,key}" \
        "systemctl start teqlif-redis-core" \
        "systemctl start teqlif-minio && mc alias set + bucket oluştur" \
        "systemctl start teqlif teqlif-worker teqlif-worker-critical"
}

setup_nvme_io_scheduler() {
    log_step "NVMe I/O Scheduler (none)"
    cat > /etc/udev/rules.d/60-nvme-scheduler.rules <<'EOF'
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="none"
EOF
    # Hemen uygula (reboot gerekmez)
    for dev in /sys/block/nvme*/queue/scheduler; do
        [ -f "${dev}" ] && echo none > "${dev}" 2>/dev/null || true
    done
    log_ok "NVMe I/O scheduler = none"
}

ufw_node1() {
    log_step "UFW (node1 — Core)"
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 22/tcp
    ufw allow 51820/udp
    ufw allow 80/tcp
    ufw allow 443/tcp
    # Tüm dahili servisler sadece WG subnet'ten erişilebilir
    ufw allow in on wg0 from 10.10.0.0/24
    ufw_enable
}

install_postgresql() {
    log_step "PostgreSQL ${PG_VERSION}"
    apt-get install -y -qq "postgresql-${PG_VERSION}" "postgresql-client-${PG_VERSION}"
    log_ok "PostgreSQL ${PG_VERSION} kuruldu"
}

install_pgbouncer() {
    log_step "PgBouncer"
    apt-get install -y -qq pgbouncer
    systemctl disable --now pgbouncer 2>/dev/null || true
    log_ok "PgBouncer kuruldu (config sonrası başlatılacak)"
}

install_redis() {
    log_step "Redis"
    apt-get install -y -qq redis-server
    systemctl disable --now redis-server 2>/dev/null || true
    log_ok "redis-server kuruldu (varsayılan servis durduruldu)"
}

setup_redis_instances() {
    local node_dir="${1}"
    log_step "teqlif Redis (core)"
    mkdir -p /project/teqlif/config/redis
    cp "${node_dir}/resources/redis/redis-core.conf" /project/teqlif/config/redis/
    mkdir -p /project/teqlif/data/redis/core
    chown -R tucibeyin:tucibeyin /project/teqlif/data/redis
    cp "${node_dir}/systemd/teqlif-redis-core.service" /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable teqlif-redis-core
    log_ok "teqlif-redis-core enable edildi"
}

install_minio() {
    log_step "MinIO (${MINIO_RELEASE})"
    local base="https://github.com/minio/minio/releases/download/${MINIO_RELEASE}"
    curl -fsSL "${base}/minio.linux-amd64.${MINIO_RELEASE}" -o /usr/local/bin/minio
    chmod +x /usr/local/bin/minio
    # mc (MinIO client)
    local mc_rel="RELEASE.2025-08-13T08-35-41Z"
    curl -fsSL "https://github.com/minio/mc/releases/download/${mc_rel}/mc.linux-amd64.${mc_rel}" -o /usr/local/bin/mc
    chmod +x /usr/local/bin/mc
    log_ok "MinIO + mc kuruldu"
}

setup_minio() {
    local node_dir="${1}"
    log_step "teqlif MinIO config"
    mkdir -p /project/teqlif/data/minio/data
    chown -R tucibeyin:tucibeyin /project/teqlif/data/minio
    # MinIO için ayrı minimal env (sadece root credentials)
    cat > /project/teqlif/config/.env.minio <<'ENVEOF'
MINIO_ROOT_USER=<minio_root_user>
MINIO_ROOT_PASSWORD=<minio_root_password>
ENVEOF
    chmod 600 /project/teqlif/config/.env.minio
    cp "${node_dir}/systemd/teqlif-minio.service" /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable teqlif-minio
    log_ok "teqlif-minio enable edildi (secrets doldurulunca: systemctl start teqlif-minio)"
}

install_nginx() {
    log_step "nginx"
    apt-get install -y -qq nginx
    log_ok "nginx kuruldu"
}

setup_nginx() {
    local node_dir="${1}"
    log_step "nginx config"
    cp "${node_dir}/resources/nginx/nginx.conf" /etc/nginx/nginx.conf
    cp "${node_dir}/resources/nginx/conf.d/"*.conf /etc/nginx/conf.d/
    mkdir -p /etc/ssl/teqlif
    touch /etc/ssl/teqlif/cf-origin.crt /etc/ssl/teqlif/cf-origin.key
    chmod 600 /etc/ssl/teqlif/cf-origin.key
    nginx -t 2>/dev/null || log_warn "nginx config test başarısız (SSL cert eksik, devam ediliyor)"
    systemctl enable nginx
    log_ok "nginx config kopyalandı"
}

install_certbot() {
    log_step "Certbot (Let's Encrypt)"
    apt-get install -y -qq certbot python3-certbot-nginx
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
ExecStart=/usr/local/bin/node_exporter --web.listen-address=10.10.0.1:9100
Restart=always
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now node-exporter
    log_ok "node_exporter aktif (10.10.0.1:9100)"
}

install_postgres_exporter() {
    log_step "postgres_exporter"
    local VER="0.15.0"
    curl -fsSL "https://github.com/prometheus-community/postgres_exporter/releases/download/v${VER}/postgres_exporter-${VER}.linux-amd64.tar.gz" \
        | tar xz -C /tmp/
    mv "/tmp/postgres_exporter-${VER}.linux-amd64/postgres_exporter" /usr/local/bin/
    cp "${NODE_DIR}/systemd/postgres-exporter.service" /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable postgres-exporter
    log_ok "postgres_exporter enable edildi (PG hazır olunca: systemctl start postgres-exporter)"
}

setup_core_services() {
    local node_dir="${1}"
    log_step "teqlif uygulama servisleri"
    for svc in teqlif.service teqlif-worker.service teqlif-worker-critical.service; do
        cp "${node_dir}/systemd/${svc}" /etc/systemd/system/
    done
    systemctl daemon-reload
    systemctl enable teqlif teqlif-worker teqlif-worker-critical
    log_ok "teqlif servisleri enable edildi"
}

main "$@"
