#!/bin/bash
# bootstrap_node5.sh — teqlif V2.1 Staging + AI Secondary (ZAP Münster DE, 10.10.0.5)
# KVM VPS | Staging stack (izole) + AI Proxy Secondary

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

NODE_ID="node5"
WG_IP="10.10.0.5"
REPO_DIR="${REPO_DIR:-/var/www/teqlif.com}"
NODE_DIR="${REPO_DIR}/deploy/scale/V2.1/${NODE_ID}"
SECRETS_FILE="${SECRETS_FILE:-}"
PG_VERSION="17"
MINIO_RELEASE="${MINIO_RELEASE:-RELEASE.2024-11-07T00-52-20Z}"
LIVEKIT_VER="${LIVEKIT_VER:-v1.7.2}"

main() {
    check_root
    check_debian
    echo -e "${BOLD}${CYAN}teqlif V2.1 — ${NODE_ID} bootstrap (${WG_IP}) [STAGING + AI SECONDARY]${NC}"

    install_base_packages
    install_pgdg_repo
    setup_user "${SSH_PUBKEY:-}"
    setup_teqlif_directories
    setup_ntp
    setup_autoupdates
    setup_limits
    setup_swap 4
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
    ufw_node5
    install_postgresql_staging
    install_redis_staging
    install_minio_staging
    install_livekit_staging
    setup_venv "${REPO_DIR}"
    setup_env_template \
        "${NODE_DIR}/resources/.env.staging.template" \
        "/project/teqlif/config/.env.staging"
    setup_env_template \
        "${NODE_DIR}/resources/.env.ai-proxy.template" \
        "/project/teqlif/config/.env.ai-proxy"
    setup_staging_services "${NODE_DIR}"
    setup_ai_proxy_service "${NODE_DIR}"
    install_nginx_staging
    install_certbot
    install_promtail
    setup_promtail "${NODE_DIR}" "${NODE_ID}"
    install_node_exporter

    if [ -n "${SECRETS_FILE:-}" ]; then
        apply_secrets "${SECRETS_FILE}" /project/teqlif/config /etc/wireguard
    fi

    print_summary "${NODE_ID}" "${WG_IP}" \
        "wg_mesh_apply.sh çalıştır" \
        "wg-quick up wg0 && systemctl enable wg-quick@wg0" \
        "Staging PG user + db: createuser teqlif && createdb teqlif_staging" \
        "alembic upgrade head (staging env ile)" \
        "MinIO staging bucket oluştur: teqlif-staging, teqlif-dm-staging" \
        "systemctl start teqlif-staging teqlif-worker-staging teqlif-ai-proxy"
}

ufw_node5() {
    log_step "UFW (node5 — Staging + AI Secondary)"
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 22/tcp
    ufw allow 51820/udp
    # Staging HTTP(S) — Cloudflare proxied üzerinden gelir
    ufw allow 80/tcp
    ufw allow 443/tcp
    # AI Proxy sadece WG mesh'ten
    ufw allow in on wg0 from 10.10.0.0/24 to any port 8001 proto tcp
    ufw_enable
}

install_postgresql_staging() {
    log_step "PostgreSQL ${PG_VERSION} (staging)"
    apt-get install -y -qq "postgresql-${PG_VERSION}" "postgresql-client-${PG_VERSION}"
    log_ok "PostgreSQL ${PG_VERSION} kuruldu"
}

install_redis_staging() {
    log_step "Redis (staging — tek instance :6379)"
    apt-get install -y -qq redis-server
    # Staging için tek Redis (staging_redis_pass ile)
    cat > /etc/redis/redis-staging.conf <<'EOF'
bind 127.0.0.1
port 6379
requirepass <staging_redis_pass>
daemonize no
loglevel notice
logfile /project/teqlif/logs/redis-staging.log
dir /project/teqlif/data/redis
dbfilename dump-staging.rdb
save 900 1
maxmemory 512mb
maxmemory-policy allkeys-lru
EOF
    mkdir -p /project/teqlif/data/redis
    chown tucibeyin:tucibeyin /project/teqlif/data/redis
    systemctl disable --now redis-server 2>/dev/null || true
    cat > /etc/systemd/system/teqlif-redis-staging.service <<'EOF'
[Unit]
Description=teqlif Redis Staging
After=network.target
[Service]
Type=simple
User=tucibeyin
ExecStart=/usr/bin/redis-server /etc/redis/redis-staging.conf
Restart=always
RestartSec=3
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable teqlif-redis-staging
    log_ok "teqlif-redis-staging enable edildi"
}

install_minio_staging() {
    log_step "MinIO (staging, port 9100)"
    curl -fsSL "https://dl.min.io/server/minio/release/linux-amd64/archive/minio.${MINIO_RELEASE}" \
        -o /usr/local/bin/minio
    chmod +x /usr/local/bin/minio
    curl -fsSL https://dl.min.io/client/mc/release/linux-amd64/mc -o /usr/local/bin/mc
    chmod +x /usr/local/bin/mc
    mkdir -p /project/teqlif/data/minio/data
    chown -R tucibeyin:tucibeyin /project/teqlif/data/minio
    cat > /project/teqlif/config/.env.minio-staging <<'ENVEOF'
MINIO_ROOT_USER=<minio_staging_root_user>
MINIO_ROOT_PASSWORD=<minio_staging_root_password>
ENVEOF
    chmod 600 /project/teqlif/config/.env.minio-staging
    cat > /etc/systemd/system/teqlif-minio-staging.service <<'EOF'
[Unit]
Description=teqlif MinIO Staging
After=network.target
[Service]
Type=simple
User=tucibeyin
EnvironmentFile=/project/teqlif/config/.env.minio-staging
ExecStart=/usr/local/bin/minio server /project/teqlif/data/minio/data --address 127.0.0.1:9100 --console-address 127.0.0.1:9101 --json
Restart=always
RestartSec=5
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable teqlif-minio-staging
    log_ok "teqlif-minio-staging enable edildi"
}

install_livekit_staging() {
    log_step "LiveKit (staging, port 7890)"
    curl -fsSL "https://github.com/livekit/livekit/releases/download/${LIVEKIT_VER}/livekit_linux_amd64.tar.gz" \
        | tar xz -C /tmp/
    mv /tmp/livekit-server /usr/local/bin/livekit-server
    chmod +x /usr/local/bin/livekit-server
    cat > /project/teqlif/config/livekit-staging.yaml <<'EOF'
port: 7890
rtc:
  tcp_port: 7891
  use_external_ip: true
redis:
  address: 127.0.0.1:6379
  db: 2
  password: <staging_redis_pass>
keys:
  <livekit_staging_api_key>: <livekit_staging_api_secret>
logging:
  level: debug
  json: true
EOF
    cat > /etc/systemd/system/teqlif-livekit-staging.service <<'EOF'
[Unit]
Description=teqlif LiveKit Staging
After=network.target
[Service]
Type=simple
User=tucibeyin
ExecStart=/usr/local/bin/livekit-server --config /project/teqlif/config/livekit-staging.yaml
Restart=always
RestartSec=5
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable teqlif-livekit-staging
    log_ok "teqlif-livekit-staging enable edildi"
}

setup_staging_services() {
    local node_dir="${1}"
    log_step "Staging uygulama servisleri"
    for svc in teqlif-staging.service teqlif-worker-staging.service; do
        cp "${node_dir}/systemd/${svc}" /etc/systemd/system/
    done
    systemctl daemon-reload
    systemctl enable teqlif-staging teqlif-worker-staging
    log_ok "Staging servisleri enable edildi"
}

setup_ai_proxy_service() {
    local node_dir="${1}"
    log_step "AI Proxy Secondary servis"
    cp "${node_dir}/systemd/teqlif-ai-proxy.service" /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable teqlif-ai-proxy
    log_ok "teqlif-ai-proxy enable edildi"
}

install_nginx_staging() {
    log_step "nginx (staging ingress)"
    apt-get install -y -qq nginx
    cat > /etc/nginx/conf.d/teqlif-staging.conf <<'EOF'
server {
    listen 443 ssl;
    server_name staging.teqlif.com;
    ssl_certificate     /etc/ssl/teqlif/cf-origin.crt;
    ssl_certificate_key /etc/ssl/teqlif/cf-origin.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    client_max_body_size 5m;
    proxy_http_version 1.1;
    proxy_set_header Upgrade    $http_upgrade;
    proxy_set_header Connection $connection_upgrade;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $http_cf_connecting_ip;
    proxy_set_header X-Forwarded-For $http_cf_connecting_ip;
    proxy_set_header X-Forwarded-Proto $scheme;
    location / {
        proxy_pass http://127.0.0.1:8000;
    }
}
server {
    listen 80;
    server_name staging.teqlif.com;
    return 301 https://$host$request_uri;
}
EOF
    mkdir -p /etc/ssl/teqlif
    touch /etc/ssl/teqlif/cf-origin.crt /etc/ssl/teqlif/cf-origin.key
    chmod 600 /etc/ssl/teqlif/cf-origin.key
    systemctl enable nginx
    log_ok "nginx (staging) enable edildi"
}

install_certbot() {
    apt-get install -y -qq certbot python3-certbot-nginx
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
ExecStart=/usr/local/bin/node_exporter --web.listen-address=10.10.0.5:9100
Restart=always
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now node-exporter
    log_ok "node_exporter aktif (10.10.0.5:9100)"
}

main "$@"
