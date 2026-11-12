#!/usr/bin/env bash
# redis_failback.sh — node2 → node1 Redis failback runbook'u
# node1 geri döndüğünde operatör bu scripti çalıştırır.
# Sıra: REPLICAOF → NAT temizliği → fail_count sıfırlama → promoted kaldırma.
# Promoted kaldırılıncaya kadar failover.sh kör kalır; NAT temizliği tamamlanmadan
# promoted silinirse OUTPUT DNAT nedeniyle PING kendi kendine PONG dönüp node1
# çökmelerini kaçırır. Bu nedenle promoted EN SON silinir.
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log_ok()   { echo -e "${GREEN}[ OK ]${NC} $*"; }
log_err()  { echo -e "${RED}[ERR ]${NC} $*" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

STATE_DIR="/var/lib/teqlif-redis-failover"
PROMOTED_FLAG="${STATE_DIR}/promoted"
FAIL_FILE="${STATE_DIR}/fail_count"
MASTER_HOST="10.10.0.1"
MASTER_PORT="6379"

source /project/teqlif/config/.env.backup

# ── 0. promoted bayrağı yok mu? ───────────────────────────────────────────────
if [ ! -f "$PROMOTED_FLAG" ]; then
    log_warn "promoted bayrağı yok — node2 zaten replica modunda, failback gerekmez"
    exit 0
fi

# ── 1. node1 Redis erişilebilir mi? ───────────────────────────────────────────
echo -n "node1 Redis PING... "
if ! redis-cli -h "$MASTER_HOST" -p "$MASTER_PORT" \
        -a "${CORE_REDIS_PASS}" --no-auth-warning PING 2>/dev/null | grep -q PONG; then
    log_err "node1 Redis'e erişilemiyor — failback iptal edildi"
    exit 1
fi
log_ok "node1 Redis PONG"

# ── 2. node2 Redis'i replica moduna al ───────────────────────────────────────
echo "node2 Redis → REPLICAOF ${MASTER_HOST} ${MASTER_PORT} ..."
redis-cli -h 127.0.0.1 -p "$MASTER_PORT" \
    -a "${CORE_REDIS_PASS}" --no-auth-warning \
    REPLICAOF "$MASTER_HOST" "$MASTER_PORT"
log_ok "REPLICAOF komutu gönderildi"

# ── 3. Replikasyon bağlantısını doğrula (en fazla 15 saniye bekle) ────────────
for i in $(seq 1 15); do
    status=$(redis-cli -h 127.0.0.1 -p "$MASTER_PORT" \
        -a "${CORE_REDIS_PASS}" --no-auth-warning \
        INFO replication 2>/dev/null | grep master_link_status | tr -d '\r' | cut -d: -f2)
    if [ "${status:-}" = "up" ]; then
        log_ok "Replikasyon bağlantısı: up (${i}s)"
        break
    fi
    sleep 1
done
if [ "${status:-}" != "up" ]; then
    log_warn "Replikasyon bağlantısı henüz 'up' değil (${status:-?}) — iptables temizliği yine de yapılıyor"
fi

# ── 4. iptables DNAT kurallarını kaldır ───────────────────────────────────────
# PREROUTING
if sudo /sbin/iptables -t nat -C PREROUTING \
        -d 10.10.0.1 -p tcp --dport 6379 \
        -j DNAT --to-destination 10.10.0.2:6379 2>/dev/null; then
    sudo /sbin/iptables -t nat -D PREROUTING \
        -d 10.10.0.1 -p tcp --dport 6379 \
        -j DNAT --to-destination 10.10.0.2:6379
    log_ok "iptables PREROUTING DNAT kaldırıldı"
else
    log_warn "PREROUTING DNAT kuralı zaten yok — atlanıyor"
fi

# OUTPUT
if sudo /sbin/iptables -t nat -C OUTPUT \
        -d 10.10.0.1 -p tcp --dport 6379 \
        -j DNAT --to-destination 127.0.0.1:6379 2>/dev/null; then
    sudo /sbin/iptables -t nat -D OUTPUT \
        -d 10.10.0.1 -p tcp --dport 6379 \
        -j DNAT --to-destination 127.0.0.1:6379
    log_ok "iptables OUTPUT DNAT kaldırıldı"
else
    log_warn "OUTPUT DNAT kuralı zaten yok — atlanıyor"
fi

# lo alias (failover.sh artık eklemez; eski elle kurulum kalıntısı olabilir)
if ip addr show dev lo 2>/dev/null | grep -q "10.10.0.1/32"; then
    sudo /usr/bin/ip addr del 10.10.0.1/32 dev lo
    log_ok "lo alias 10.10.0.1/32 kaldırıldı"
fi

# ── 5. fail_count sıfırla ─────────────────────────────────────────────────────
echo "0" > "$FAIL_FILE"
log_ok "fail_count sıfırlandı"

# ── 6. promoted bayrağını kaldır (en son) ────────────────────────────────────
rm -f "$PROMOTED_FLAG"
log_ok "promoted bayrağı silindi — teqlif-redis-failover.timer artık aktif kontrol yapıyor"

echo ""
log_ok "Failback tamamlandı. Durum kontrol:"
redis-cli -h 127.0.0.1 -p "$MASTER_PORT" \
    -a "${CORE_REDIS_PASS}" --no-auth-warning \
    INFO replication 2>/dev/null | grep -E '(role:|master_host:|master_link_status:)'
