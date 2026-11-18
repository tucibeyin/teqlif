#!/usr/bin/env bash
# redis_vip_check.sh — node3, node4, node5, node6 üzerinde çalışır
# (teqlif-redis-vip.timer tarafından her 10 saniyede tetiklenir)
#
# node1 Redis (10.10.0.1:6379) erişilemez olursa WireGuard peer routing'ini
# node2'ye (10.10.0.2:6379) günceller; böylece tüm istemciler 10.10.0.1:6379
# adresini kullanmaya devam eder ve paketler node2'ye yönlendirilir.
#
# Loglama: systemd journal-native (stdout/stderr) — log_info/log_warn/log_err.
# Durum geçişi filtresi ($STATE_DIR/last_state) sayesinde aynı durum her 10
# saniyede tekrar log üretmez; yalnızca durum DEĞİŞTİĞİNDE log yazılır.
#
# DRY_RUN=1: wg set ve wg-quick save komutları çalıştırılmaz, yalnızca loglanır.
# Değişken override: STATE_DIR, REDIS_VIP_IP, NODE2_WG_IP (ortam değişkeni).
#
# Failback (manuel — admin müdahalesi gerekir):
#   VIP_CACHE=/var/lib/teqlif-redis-vip
#   source "$VIP_CACHE/wg_peers.cache"
#   sudo wg set wg0 peer "$NODE1_PUBKEY" allowed-ips 10.10.0.1/32
#   sudo wg set wg0 peer "$NODE2_PUBKEY" allowed-ips 10.10.0.2/32
#   sudo wg-quick save wg0
#   rm -f "$VIP_CACHE/vip_active" "$VIP_CACHE/fail_count"
set -euo pipefail

# ── Değişken override desteği (varsayılanlar korunur) ─────────────────────────
STATE_DIR="${STATE_DIR:-/var/lib/teqlif-redis-vip}"
REDIS_VIP_IP="${REDIS_VIP_IP:-10.10.0.1}"
NODE2_WG_IP="${NODE2_WG_IP:-10.10.0.2}"
DRY_RUN="${DRY_RUN:-0}"
REDIS_PORT="${REDIS_PORT:-6379}"
FAIL_THRESHOLD="${FAIL_THRESHOLD:-3}"

VIP_ACTIVE_FLAG="${STATE_DIR}/vip_active"
FAIL_FILE="${STATE_DIR}/fail_count"
CACHE_FILE="${STATE_DIR}/wg_peers.cache"
LAST_STATE_FILE="${STATE_DIR}/last_state"

# ── systemd journal-native log fonksiyonları ─────────────────────────────────
log_info() { printf '[redis-vip] %s\n' "$*"; }
log_warn() { printf '[redis-vip] WARN: %s\n' "$*" >&2; }
log_err()  { printf '[redis-vip] ERROR: %s\n' "$*" >&2; }

# ── DRY_RUN: wg set / wg-quick save komutlarını guard'layan sarmalayıcı ─────
run() {
    if [ "${DRY_RUN}" = "1" ]; then
        log_info "[DRY_RUN] $*"
        return 0
    fi
    "$@"
}

# ── Durum geçişi filtresi: sadece değişimde log üret ─────────────────────────
set_state() {
    local new_state="$1"
    local message="${2:-}"
    local level="${3:-info}"
    local prev
    prev=$(cat "$LAST_STATE_FILE" 2>/dev/null || echo "")
    [ "$prev" = "$new_state" ] && return 0
    if [ -n "$message" ]; then
        case "$level" in
            warn) log_warn "$message" ;;
            err)  log_err  "$message" ;;
            *)    log_info "$message" ;;
        esac
    fi
    printf '%s\n' "$new_state" > "$LAST_STATE_FILE"
}

mkdir -p "$STATE_DIR"

# ── WireGuard peer key'lerini bul veya cache'den oku ──────────────────────────
# Cache sadece normal operasyon sırasında (10.10.0.1/32 → node1) doldurulur.
# Failover sonrası AllowedIPs değiştiği için cache zorunludur.
if [ ! -f "$CACHE_FILE" ]; then
    DUMP=$(sudo wg show wg0 dump 2>/dev/null) || { log_warn "wg show başarısız — atlanıyor"; exit 0; }
    _NODE1_PK=$(echo "$DUMP" | awk 'NR>1 && $4=="10.10.0.1/32" {print $1; exit}')
    _NODE2_PK=$(echo "$DUMP" | awk 'NR>1 && $4=="10.10.0.2/32" {print $1; exit}')
    if [ -n "$_NODE1_PK" ] && [ -n "$_NODE2_PK" ]; then
        printf 'NODE1_PUBKEY=%s\nNODE2_PUBKEY=%s\n' "$_NODE1_PK" "$_NODE2_PK" > "$CACHE_FILE"
    else
        log_warn "Peer key'ler bulunamadı — mesh yapılandırmasını kontrol et"
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
    run sudo wg set wg0 peer "$NODE1_PUBKEY" allowed-ips "${REDIS_VIP_IP}/32"
    run sudo wg set wg0 peer "$NODE2_PUBKEY" allowed-ips "${NODE2_WG_IP}/32"
    run sudo wg-quick save wg0 2>/dev/null || true
    rm -f "$VIP_ACTIVE_FLAG" "$FAIL_FILE"
    set_state "restore_both_down" "node2 de erişilemez — routing geri yüklendi (her iki node da DOWN)" warn
    exit 0
fi

# ── Normal durum: node1 Redis TCP erişilebilir mi? ───────────────────────────
if check_tcp "$REDIS_VIP_IP"; then
    echo "0" > "$FAIL_FILE"
    set_state "node1_up" "" info
    exit 0
fi

# ── Erişilemez — sayacı artır ─────────────────────────────────────────────────
current=$(cat "$FAIL_FILE" 2>/dev/null || echo "0")
current=$((current + 1))
echo "$current" > "$FAIL_FILE"

if [ "$current" -lt "$FAIL_THRESHOLD" ]; then
    set_state "node1_unreachable" "node1 Redis erişilemez ($current/$FAIL_THRESHOLD)" warn
    exit 0
fi

# ── Eşik aşıldı — node2 yanıt veriyor mu? ───────────────────────────────────
if ! check_tcp "$NODE2_WG_IP"; then
    set_state "failover_aborted" "node1 AND node2 Redis erişilemez — failover iptal" err
    exit 0
fi

# ── FAILOVER: WireGuard routing'i node2'ye yönlendir ─────────────────────────
set_state "failover_started" "FAILOVER başlıyor: 10.10.0.1 → node2 (${NODE2_WG_IP}) yönlendiriliyor" warn
run sudo wg set wg0 peer "$NODE1_PUBKEY" allowed-ips "0.0.0.1/32"
run sudo wg set wg0 peer "$NODE2_PUBKEY" allowed-ips "${NODE2_WG_IP}/32,${REDIS_VIP_IP}/32"
run sudo wg-quick save wg0
echo "0" > "$FAIL_FILE"
touch "$VIP_ACTIVE_FLAG"
set_state "vip_active" "VIP aktif: 10.10.0.1 → node2 (${NODE2_WG_IP}) yönlendirildi" info
