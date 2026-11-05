#!/usr/bin/env bash
# redis_vip_check.sh — node3, node4, node5, node6 üzerinde çalışır
# (teqlif-redis-vip.timer tarafından her 10 saniyede tetiklenir)
#
# node1 Redis (10.10.0.1:6379) erişilemez olursa WireGuard peer routing'ini
# node2'ye (10.10.0.2:6379) günceller; böylece tüm istemciler 10.10.0.1:6379
# adresini kullanmaya devam eder ve paketler node2'ye yönlendirilir.
#
# Failback (manuel — admin müdahalesi gerekir):
#   VIP_CACHE=/var/lib/teqlif-redis-vip
#   source "$VIP_CACHE/wg_peers.cache"
#   sudo wg set wg0 peer "$NODE1_PUBKEY" allowed-ips 10.10.0.1/32
#   sudo wg set wg0 peer "$NODE2_PUBKEY" allowed-ips 10.10.0.2/32
#   sudo wg-quick save wg0
#   rm -f "$VIP_CACHE/vip_active" "$VIP_CACHE/fail_count"
set -euo pipefail

REDIS_VIP_IP="10.10.0.1"
NODE2_WG_IP="10.10.0.2"
REDIS_PORT="6379"
FAIL_THRESHOLD=3
STATE_DIR="/var/lib/teqlif-redis-vip"
VIP_ACTIVE_FLAG="${STATE_DIR}/vip_active"
FAIL_FILE="${STATE_DIR}/fail_count"
CACHE_FILE="${STATE_DIR}/wg_peers.cache"

mkdir -p "$STATE_DIR"

# ── WireGuard peer key'lerini bul veya cache'den oku ──────────────────────────
# Cache sadece normal operasyon sırasında (10.10.0.1/32 → node1) doldurulur.
# Failover sonrası AllowedIPs değiştiği için cache zorunludur.
if [ ! -f "$CACHE_FILE" ]; then
    DUMP=$(sudo wg show wg0 dump 2>/dev/null) || { logger -t redis-vip "wg show başarısız — atlanıyor"; exit 0; }
    _NODE1_PK=$(echo "$DUMP" | awk 'NR>1 && $4=="10.10.0.1/32" {print $1; exit}')
    _NODE2_PK=$(echo "$DUMP" | awk 'NR>1 && $4=="10.10.0.2/32" {print $1; exit}')
    if [ -n "$_NODE1_PK" ] && [ -n "$_NODE2_PK" ]; then
        printf 'NODE1_PUBKEY=%s\nNODE2_PUBKEY=%s\n' "$_NODE1_PK" "$_NODE2_PK" > "$CACHE_FILE"
    else
        logger -t redis-vip "Peer key'ler bulunamadı — mesh yapılandırmasını kontrol et"
        exit 0
    fi
fi

# shellcheck source=/dev/null
source "$CACHE_FILE"

check_tcp() {
    timeout 1 bash -c "exec 3<>/dev/tcp/$1/$REDIS_PORT" 2>/dev/null
}

# ── VIP aktif durumu: node2 TCP erişimini doğrula ────────────────────────────
if [ -f "$VIP_ACTIVE_FLAG" ]; then
    if check_tcp "$NODE2_WG_IP"; then
        exit 0  # node2 hâlâ yanıt veriyor — VIP gerekli
    fi
    # node2 de erişilemez — routing'i geri yükle (en azından tutarlılık)
    sudo wg set wg0 peer "$NODE1_PUBKEY" allowed-ips "${REDIS_VIP_IP}/32"
    sudo wg set wg0 peer "$NODE2_PUBKEY" allowed-ips "${NODE2_WG_IP}/32"
    sudo wg-quick save wg0 2>/dev/null || true
    rm -f "$VIP_ACTIVE_FLAG" "$FAIL_FILE"
    logger -t redis-vip "node2 de erişilemez — routing geri yüklendi (her iki node da DOWN)"
    exit 0
fi

# ── Normal durum: node1 Redis TCP erişilebilir mi? ───────────────────────────
if check_tcp "$REDIS_VIP_IP"; then
    echo "0" > "$FAIL_FILE"
    exit 0
fi

# ── Erişilemez — sayacı artır ─────────────────────────────────────────────────
current=$(cat "$FAIL_FILE" 2>/dev/null || echo "0")
current=$((current + 1))
echo "$current" > "$FAIL_FILE"
logger -t redis-vip "node1 Redis erişilemez ($current/$FAIL_THRESHOLD)"

if [ "$current" -lt "$FAIL_THRESHOLD" ]; then
    exit 0
fi

# ── Eşik aşıldı — node2 yanıt veriyor mu? ───────────────────────────────────
if ! check_tcp "$NODE2_WG_IP"; then
    logger -t redis-vip "node1 AND node2 Redis erişilemez — failover iptal"
    exit 0
fi

# ── FAILOVER: WireGuard routing'i node2'ye yönlendir ─────────────────────────
logger -t redis-vip "FAILOVER başlıyor: 10.10.0.1 → node2 (${NODE2_WG_IP}) yönlendiriliyor"
sudo wg set wg0 peer "$NODE1_PUBKEY" allowed-ips "0.0.0.1/32"
sudo wg set wg0 peer "$NODE2_PUBKEY" allowed-ips "${NODE2_WG_IP}/32,${REDIS_VIP_IP}/32"
sudo wg-quick save wg0
echo "0" > "$FAIL_FILE"
touch "$VIP_ACTIVE_FLAG"
logger -t redis-vip "VIP aktif: 10.10.0.1 → node2 (${NODE2_WG_IP}) yönlendirildi"
