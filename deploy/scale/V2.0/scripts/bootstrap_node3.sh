#!/bin/bash
# bootstrap_node3.sh — teqlif V2.0 Staging Tam İzole (ZAP VA, 10.10.0.4)
# Çalıştır: sudo bash bootstrap_node3.sh

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

NODE_ID="node3"
WG_IP="10.10.0.4"
REPO_DIR="${REPO_DIR:-/var/www/teqlif.com}"
NODE_DIR="${REPO_DIR}/deploy/scale/V2.0/${NODE_ID}"
MINIO_RELEASE="${MINIO_RELEASE:-RELEASE.2024-11-07T00-52-20Z}"
MC_RELEASE="${MC_RELEASE:-RELEASE.2024-11-07T00-52-20Z}"
LIVEKIT_VER="${LIVEKIT_VER:-v1.7.2}"
PG_VERSION="17"

main() {
    check_root
    check_debian
    echo -e "${BOLD}${CYAN}teqlif V2.0 — ${NODE_ID} bootstrap (${WG_IP}) [tam izole staging]${NC}"

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
    ufw_staging
    install_postgresql
    setup_postgresql_local
    install_redis
    setup_redis_staging "${NODE_DIR}"
    install_minio
    setup_minio_staging "${NODE_DIR}"
    install_livekit
    setup_livekit_staging "${NODE_DIR}"
    setup_venv "${REPO_DIR}"
    setup_env_template \
        "${NODE_DIR}/resources/.env.staging.template" \
        "/etc/teqlif/.env.staging"
    setup_staging_services "${NODE_DIR}"
    install_promtail
    setup_promtail "${NODE_DIR}" "${NODE_ID}"
    setup_guardian "${NODE_DIR}"

    print_summary "${NODE_ID}" "${WG_IP}" \
        "/etc/teqlif/.env.staging içindeki <placeholder>'ları doldur" \
        "wg0.conf peer <PublicKey> placeholder'larını doldur" \
        "/etc/redis/redis-staging.conf içindeki <staging_redis_pass>'ı doldur" \
        "/etc/livekit/livekit-staging.yaml içindeki <placeholder>'ları doldur" \
        "firebase-service-account.json + AuthKey_*.p8 → /etc/teqlif/ konumuna kopyala" \
        "CF Origin cert: /etc/ssl/teqlif/cf-origin.{crt,key}" \
        "wg-quick up wg0  →  systemctl enable --now wg-quick@wg0" \
        "alembic upgrade head  (staging DB)" \
        "systemctl start redis-staging minio-staging livekit-staging teqlif-staging teqlif-worker-staging teqlif-worker-critical-staging teqlif-ai-proxy teqlif-guardian"
}

ufw_staging() {
    log_step "UFW (staging)"
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 22/tcp
    ufw allow 51820/udp
    ufw allow in on wg0 from 10.10.0.0/24
    ufw allow in on wg0 proto udp to any port 9901
    ufw allow 80/tcp     # nginx → staging.teqlif.com
    ufw allow 443/tcp    # nginx → tüm staging domain'ler
    # LiveKit portları (staging)
    ufw allow 7880/tcp
    ufw allow 7881/tcp
    ufw allow 7882/udp
    ufw allow 3478/udp
    ufw allow 5349/tcp
    ufw allow 50000:60000/udp
    # MinIO doğrudan erişimi engelle — yalnızca nginx :443
    ufw deny 9000/tcp
    ufw_enable
}

install_postgresql() {
    log_step "PostgreSQL ${PG_VERSION}"
    if ! command -v psql &>/dev/null; then
        apt-get install -y -qq "postgresql-${PG_VERSION}"
    else
        log_info "PostgreSQL zaten kurulu"
    fi
}

setup_postgresql_local() {
    log_step "PostgreSQL lokal yapılandırma"
    sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '127.0.0.1'/" \
        "/etc/postgresql/${PG_VERSION}/main/postgresql.conf" 2>/dev/null || true
    systemctl restart postgresql
    # DB ve kullanıcı oluştur (idempotent)
    sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='teqlif'" \
        | grep -q 1 || \
        sudo -u postgres psql -c "CREATE USER teqlif WITH ENCRYPTED PASSWORD '<staging_pg_pass>';"
    sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='teqlif_staging'" \
        | grep -q 1 || \
        sudo -u postgres psql -c "CREATE DATABASE teqlif_staging OWNER teqlif;"
    log_ok "PostgreSQL hazır (teqlif_staging lokal)"
    log_warn "PostgreSQL kullanıcı şifresi: ALTER USER teqlif WITH PASSWORD '<staging_pg_pass>';"
}

install_redis() {
    log_step "Redis"
    apt-get install -y -qq redis-server
    systemctl disable --now redis-server 2>/dev/null || true
    log_ok "redis-server kuruldu (varsayılan servis durduruldu)"
}

setup_redis_staging() {
    local node_dir="${1}"
    log_step "Redis staging config"
    cp "${node_dir}/resources/redis/redis-staging.conf" /etc/redis/redis-staging.conf
    cp "${node_dir}/systemd/redis-staging.service" /etc/systemd/system/redis-staging.service
    systemctl daemon-reload
    systemctl enable redis-staging
    log_ok "redis-staging enable edildi (<staging_redis_pass> doldurulunca: systemctl start redis-staging)"
}

install_minio() {
    log_step "MinIO ${MINIO_RELEASE}"
    if ! command -v minio &>/dev/null; then
        curl -fsSL \
            "https://github.com/minio/minio/releases/download/${MINIO_RELEASE}/minio.linux-amd64.${MINIO_RELEASE}" \
            -o /usr/local/bin/minio
        chmod 755 /usr/local/bin/minio
        # mc client
        curl -fsSL \
            "https://dl.min.io/client/mc/release/linux-amd64/archive/mc.${MC_RELEASE}" \
            -o /usr/local/bin/mc
        chmod 755 /usr/local/bin/mc
        log_ok "minio + mc kuruldu"
    else
        log_info "MinIO zaten kurulu"
    fi
    mkdir -p /var/lib/minio-staging /var/log/teqlif/minio
    chown tucibeyin:tucibeyin /var/lib/minio-staging /var/log/teqlif/minio
}

setup_minio_staging() {
    local node_dir="${1}"
    log_step "MinIO staging servis"
    cp "${node_dir}/systemd/minio-staging.service" /etc/systemd/system/minio-staging.service
    systemctl daemon-reload
    systemctl enable minio-staging
    log_ok "minio-staging enable edildi (.env.staging doldurulunca: systemctl start minio-staging)"
}

install_livekit() {
    log_step "LiveKit ${LIVEKIT_VER}"
    if ! command -v livekit-server &>/dev/null; then
        curl -fsSL \
            "https://github.com/livekit/livekit/releases/download/${LIVEKIT_VER}/livekit_linux_amd64.tar.gz" \
            | tar -xz -C /usr/local/bin livekit-server
        chmod 755 /usr/local/bin/livekit-server
        log_ok "livekit-server ${LIVEKIT_VER} kuruldu"
    else
        log_info "livekit-server zaten mevcut"
    fi
}

setup_livekit_staging() {
    local node_dir="${1}"
    log_step "LiveKit staging config"
    mkdir -p /etc/livekit /etc/ssl/teqlif
    chmod 700 /etc/ssl/teqlif
    cp "${node_dir}/resources/livekit/livekit.yaml" /etc/livekit/livekit-staging.yaml
    cp "${node_dir}/systemd/livekit-staging.service" /etc/systemd/system/livekit-staging.service
    systemctl daemon-reload
    systemctl enable livekit-staging
    log_ok "livekit-staging enable edildi (yaml doldurulunca başlar)"
}

setup_staging_services() {
    local node_dir="${1}"
    log_step "Staging uygulama servisleri"
    for svc in \
        teqlif-staging.service \
        teqlif-worker-staging.service \
        teqlif-worker-critical-staging.service \
        teqlif-ai-proxy.service; do
        cp "${node_dir}/systemd/${svc}" "/etc/systemd/system/${svc}"
    done
    # nginx
    apt-get install -y -qq nginx
    mkdir -p /etc/systemd/system/nginx.service.d
    cat > /etc/systemd/system/nginx.service.d/restart.conf <<'EOF'
[Service]
Restart=always
RestartSec=5
EOF
    local nginx_src="${node_dir}/resources/nginx/sites-available/staging"
    if [ -f "${nginx_src}" ]; then
        cp "${nginx_src}" /etc/nginx/sites-available/staging
        ln -sf /etc/nginx/sites-available/staging /etc/nginx/sites-enabled/staging
    fi
    # Guardian sudoers ek: staging servisleri
    cat >> /etc/sudoers.d/guardian-systemctl <<'EOF'
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/systemctl start redis-staging
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop redis-staging
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart redis-staging
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/systemctl reset-failed redis-staging
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/systemctl start minio-staging
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop minio-staging
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart minio-staging
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/systemctl reset-failed minio-staging
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/systemctl start livekit-staging
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop livekit-staging
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart livekit-staging
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/systemctl reset-failed livekit-staging
EOF
    chmod 440 /etc/sudoers.d/guardian-systemctl
    systemctl daemon-reload
    systemctl enable teqlif-staging teqlif-worker-staging \
        teqlif-worker-critical-staging teqlif-ai-proxy nginx
    log_ok "Tüm staging servisleri enable edildi"
}

main "$@"
