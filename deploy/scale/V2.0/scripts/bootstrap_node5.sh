#!/bin/bash
# bootstrap_node5.sh — teqlif V2.0 Core PRIMARY (OVH SBG, 10.10.0.5)
# Çalıştır: sudo bash bootstrap_node5.sh
#
# ⚠  HA KURULUM SIRASI:
#   1. Bu script çalıştır (node5)
#   2. bootstrap_node6.sh çalıştır (node6)
#   3. node5'te pg_hba.conf düzenle + replication slot oluştur (plan §4.3)
#   4. node6'da pg_basebackup çalıştır (plan §4.6)
#   5. Her iki node'da Keepalived başlat (plan §5.6)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

NODE_ID="node5"
WG_IP="10.10.0.5"
REPO_DIR="${REPO_DIR:-/var/www/teqlif.com}"
NODE_DIR="${REPO_DIR}/deploy/scale/V2.0/${NODE_ID}"
SECRETS_FILE="${SECRETS_FILE:-}"
PG_VERSION="17"

main() {
    check_root
    check_debian
    echo -e "${BOLD}${CYAN}teqlif V2.0 — ${NODE_ID} bootstrap (${WG_IP}) [CORE PRIMARY]${NC}"

    install_base_packages
    install_pgdg_repo
    setup_user "${SSH_PUBKEY:-}"
    setup_directories
    setup_ntp
    setup_autoupdates
    setup_limits
    setup_swap 8
    clone_repo "${REPO_DIR}"
    setup_logrotate    "${NODE_DIR}"
    setup_auditd       "${NODE_DIR}"
    setup_thp_disable  "${NODE_DIR}"
    setup_fail2ban     "${NODE_DIR}"
    setup_node_conf    "${NODE_DIR}"
    setup_wg_keygen
    setup_wg_config    "${NODE_DIR}"
    # node5/6 non-core değil, WG VIP sudoers gerekmiyor (VIP burada)
    setup_guardian_sudoers "${NODE_DIR}"
    setup_sysctl "${NODE_DIR}"
    ufw_core
    install_postgresql
    install_pgbouncer
    install_redis
    setup_redis_instances "${NODE_DIR}"
    install_keepalived
    setup_venv "${REPO_DIR}"
    setup_env_template \
        "${NODE_DIR}/resources/.env.production.template" \
        "/etc/teqlif/.env.production"
    setup_core_services "${NODE_DIR}"
    install_promtail
    setup_promtail "${NODE_DIR}" "${NODE_ID}"
    setup_guardian "${NODE_DIR}"

    # Secrets uygula (SECRETS_FILE env var verilmişse)
    if [ -n "${SECRETS_FILE:-}" ]; then
        apply_secrets "${SECRETS_FILE}" /etc/teqlif /etc/wireguard /etc/redis /etc/keepalived /etc/pgbouncer
    fi
    print_summary "${NODE_ID}" "${WG_IP}" \
        "/etc/teqlif/.env.production içindeki <placeholder>'ları doldur (§0.5)" \
        "wg0.conf peer <PublicKey> placeholder'larını doldur" \
        "postgresql.conf'u plan §4.3'e göre düzenle (max_wal_senders, wal_level, slot)" \
        "pg_hba.conf'a replication + teqlif satırlarını ekle (plan §4.3)" \
        "PgBouncer: /etc/pgbouncer/pgbouncer.ini + userlist.txt doldur (plan §4.2)" \
        "Redis conf'larındaki <pass> placeholder'larını doldur" \
        "Keepalived: /etc/keepalived/keepalived.conf düzenle + VIP scriptleri doldur (plan §5.4)" \
        "node6 bootstrap tamamlandıktan sonra Faz 4 HA adımlarını uygula" \
        "wg-quick up wg0  →  systemctl enable --now wg-quick@wg0" \
        "systemctl start postgresql pgbouncer redis-core redis-orch redis-guardian" \
        "alembic upgrade head  →  systemctl start teqlif teqlif-worker teqlif-worker-critical teqlif-ai-proxy" \
        "Keepalived: systemctl start keepalived (node6 hazır olunca)"
}

install_pgdg_repo() {
    log_step "PGDG apt repo"
    if [ -f /etc/apt/sources.list.d/pgdg.list ]; then
        log_info "PGDG repo zaten mevcut"; return
    fi
    apt-get install -y -qq gnupg
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
        | gpg --dearmor | tee /usr/share/keyrings/pgdg.gpg > /dev/null
    echo "deb [signed-by=/usr/share/keyrings/pgdg.gpg] https://apt.postgresql.org/pub/repos/apt \
$(. /etc/os-release; echo "$VERSION_CODENAME")-pgdg main" \
        | tee /etc/apt/sources.list.d/pgdg.list
    apt-get update -qq
    log_ok "PGDG repo eklendi"
}

ufw_core() {
    log_step "UFW (core — sadece WireGuard)"
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 22/tcp
    ufw allow 51820/udp
    ufw allow in on wg0 from 10.10.0.0/24
    ufw allow in on wg0 proto udp to any port 9901
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
    # Config şablonları repo'dan kopyalanır (§4.2)
    local pb_src="${NODE_DIR}/resources/pgbouncer"
    if [ -d "${pb_src}" ]; then
        cp "${pb_src}"/* /etc/pgbouncer/ 2>/dev/null || true
    fi
    # Restart drop-in
    local svc="${NODE_DIR}/systemd/pgbouncer.service.d/restart.conf"
    if [ -f "${svc}" ]; then
        mkdir -p /etc/systemd/system/pgbouncer.service.d
        cp "${svc}" /etc/systemd/system/pgbouncer.service.d/restart.conf
    fi
    systemctl daemon-reload
    systemctl enable pgbouncer
    log_ok "PgBouncer kuruldu (/etc/pgbouncer/ doldurulunca başlayabilir)"
}

install_redis() {
    log_step "Redis"
    apt-get install -y -qq redis-server
    systemctl disable --now redis-server 2>/dev/null || true
    log_ok "redis-server kuruldu (varsayılan servis durduruldu)"
}

setup_redis_instances() {
    local node_dir="${1}"
    log_step "Redis 3 instance (core:6379 / orch:6380 / guardian:6382)"
    for svc in redis-core.service redis-orch.service redis-guardian.service; do
        cp "${node_dir}/systemd/${svc}" "/etc/systemd/system/${svc}"
    done
    # Redis conf'lar
    local redis_src="${node_dir}/resources/redis"
    if [ -d "${redis_src}" ]; then
        for conf in "${redis_src}"/*.conf; do
            cp "${conf}" /etc/redis/ 2>/dev/null || true
        done
    fi
    # Guardian sudoers ek: redis + pgbouncer
    cat >> /etc/sudoers.d/guardian-systemctl <<'EOF'
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/systemctl start redis-core
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop redis-core
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart redis-core
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/systemctl reset-failed redis-core
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/systemctl start redis-orch
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop redis-orch
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart redis-orch
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/systemctl reset-failed redis-orch
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/systemctl start redis-guardian
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop redis-guardian
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart redis-guardian
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/systemctl reset-failed redis-guardian
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/systemctl start pgbouncer
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop pgbouncer
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart pgbouncer
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/systemctl reset-failed pgbouncer
EOF
    chmod 440 /etc/sudoers.d/guardian-systemctl
    systemctl daemon-reload
    systemctl enable redis-core redis-orch redis-guardian
    log_ok "Redis instance'ları enable edildi (<pass> doldurulunca başlar)"
}

install_keepalived() {
    log_step "Keepalived"
    apt-get install -y -qq keepalived
    mkdir -p /etc/keepalived/scripts /etc/keepalived/secrets
    chmod 700 /etc/keepalived/secrets
    # Config şablonları
    local kp_src="${NODE_DIR}/resources/keepalived"
    [ -d "${kp_src}" ] && cp -r "${kp_src}"/* /etc/keepalived/ 2>/dev/null || true
    systemctl enable keepalived
    log_ok "Keepalived kuruldu (node6 hazır + config doldurulunca: systemctl start keepalived)"
}

setup_core_services() {
    local node_dir="${1}"
    log_step "Core uygulama servisleri"
    for svc in \
        teqlif.service \
        teqlif-worker.service \
        teqlif-worker-critical.service \
        teqlif-ai-proxy.service \
        postgres-exporter.service; do
        [ -f "${node_dir}/systemd/${svc}" ] \
            && cp "${node_dir}/systemd/${svc}" "/etc/systemd/system/${svc}"
    done
    systemctl daemon-reload
    systemctl enable teqlif teqlif-worker teqlif-worker-critical
    log_ok "Core servisler enable edildi (.env + DB hazır olunca başlayabilir)"
}

main "$@"
