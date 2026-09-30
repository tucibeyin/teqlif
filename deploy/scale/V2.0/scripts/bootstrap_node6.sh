#!/bin/bash
# bootstrap_node6.sh — teqlif V2.0 Core STANDBY (Deluxhost AMS, 10.10.0.7)
# Çalıştır: sudo bash bootstrap_node6.sh
#
# ⚠  node5 bootstrap bittikten SONRA çalıştır.
#    pg_basebackup + Keepalived: node5 hazır + WireGuard mesh kurulu olmalı.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

NODE_ID="node6"
WG_IP="10.10.0.7"
REPO_DIR="${REPO_DIR:-/var/www/teqlif.com}"
NODE_DIR="${REPO_DIR}/deploy/scale/V2.0/${NODE_ID}"
SECRETS_FILE="${SECRETS_FILE:-}"
PG_VERSION="17"

main() {
    check_root
    check_debian
    echo -e "${BOLD}${CYAN}teqlif V2.0 — ${NODE_ID} bootstrap (${WG_IP}) [CORE STANDBY]${NC}"

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
    setup_guardian_sudoers "${NODE_DIR}"
    setup_sysctl "${NODE_DIR}"
    ufw_core
    install_postgresql
    install_pgbouncer
    install_redis
    setup_redis_instances "${NODE_DIR}"
    install_keepalived
    setup_env_template \
        "${NODE_DIR}/resources/.env.production.template" \
        "/etc/teqlif/.env.production"
    setup_standby_notes
    install_promtail
    setup_promtail "${NODE_DIR}" "${NODE_ID}"
    setup_guardian "${NODE_DIR}"

    # Secrets uygula (SECRETS_FILE env var verilmişse)
    if [ -n "${SECRETS_FILE:-}" ]; then
        apply_secrets "${SECRETS_FILE}" /etc/teqlif /etc/wireguard /etc/redis /etc/keepalived /etc/pgbouncer
    fi
    print_summary "${NODE_ID}" "${WG_IP}" \
        "/etc/teqlif/.env.production içindeki <placeholder>'ları doldur" \
        "wg0.conf peer <PublicKey> placeholder'larını doldur" \
        "Redis conf'larındaki <pass> placeholder'larını doldur" \
        "node5 PG replication slot + pg_hba.conf hazır olduktan sonra pg_basebackup çalıştır (plan §4.6)" \
        "PgBouncer: /etc/pgbouncer/ doldur (plan §4.2)" \
        "Keepalived: /etc/keepalived/keepalived.conf düzenle (plan §5.4)" \
        "wg-quick up wg0  →  systemctl enable --now wg-quick@wg0" \
        "Faz 4 HA adımları tamamlandıktan sonra: systemctl start postgresql pgbouncer redis-core redis-orch redis-guardian keepalived" \
        "systemctl start teqlif-guardian"
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
    # Standby'da PG'yi henüz başlatma — pg_basebackup ile doldurulacak
    systemctl stop postgresql 2>/dev/null || true
    log_ok "PostgreSQL kuruldu (pg_basebackup bekliyor)"
}

install_pgbouncer() {
    log_step "PgBouncer"
    apt-get install -y -qq pgbouncer
    local pb_src="${NODE_DIR}/resources/pgbouncer"
    [ -d "${pb_src}" ] && cp "${pb_src}"/* /etc/pgbouncer/ 2>/dev/null || true
    local svc="${NODE_DIR}/systemd/pgbouncer.service.d/restart.conf"
    if [ -f "${svc}" ]; then
        mkdir -p /etc/systemd/system/pgbouncer.service.d
        cp "${svc}" /etc/systemd/system/pgbouncer.service.d/restart.conf
    fi
    systemctl daemon-reload
    systemctl enable pgbouncer
    log_ok "PgBouncer kuruldu"
}

install_redis() {
    log_step "Redis"
    apt-get install -y -qq redis-server
    systemctl disable --now redis-server 2>/dev/null || true
}

setup_redis_instances() {
    local node_dir="${1}"
    log_step "Redis 3 instance (core:6379 / orch:6380 / guardian:6382)"
    for svc in redis-core.service redis-orch.service redis-guardian.service; do
        cp "${node_dir}/systemd/${svc}" "/etc/systemd/system/${svc}"
    done
    local redis_src="${node_dir}/resources/redis"
    [ -d "${redis_src}" ] && cp "${redis_src}"/*.conf /etc/redis/ 2>/dev/null || true
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
    log_ok "Redis instance'ları enable edildi"
}

install_keepalived() {
    log_step "Keepalived"
    apt-get install -y -qq keepalived
    mkdir -p /etc/keepalived/scripts /etc/keepalived/secrets
    chmod 700 /etc/keepalived/secrets
    local kp_src="${NODE_DIR}/resources/keepalived"
    [ -d "${kp_src}" ] && cp -r "${kp_src}"/* /etc/keepalived/ 2>/dev/null || true
    systemctl enable keepalived
    log_ok "Keepalived kuruldu"
}

setup_standby_notes() {
    log_step "Standby notları"
    log_warn "=== PostgreSQL Standby Kurulum Sırası ==="
    log_warn "1. node5'te pg_hba.conf + replication slot hazır olmalı"
    log_warn "2. node5 + node6 WireGuard mesh kurulu ve çalışıyor olmalı"
    log_warn "3. Şu komutu çalıştır (plan §4.6):"
    log_warn "   pg_basebackup -h 10.10.0.5 -U replicator -D /var/lib/postgresql/17/main -P -R"
    log_warn "4. systemctl start postgresql"
    log_warn "5. Her iki node'da: systemctl start keepalived"
}

main "$@"
