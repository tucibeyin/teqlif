#!/bin/bash
# wg_mesh_apply.sh — teqlif V2.1 WireGuard full mesh kurulumu
# Tüm node'larda bootstrap tamamlandıktan sonra çalıştırılır.
# Gereksinim: secrets.env Bölüm 3 dolu (tüm pubkey'ler)
#
# Çalıştır (lokal makineden):
#   SECRETS_FILE=./secrets.env bash wg_mesh_apply.sh

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
log_info() { echo -e "${CYAN}[INFO]${NC} $*"; }
log_ok()   { echo -e "${GREEN}[ OK ]${NC} $*"; }
log_err()  { echo -e "${RED}[ERR ]${NC} $*" >&2; }
log_step() { echo -e "\n${BOLD}──── $* ────${NC}"; }

SECRETS_FILE="${SECRETS_FILE:?SECRETS_FILE ortam değişkeni belirtilmeli}"
[ -f "${SECRETS_FILE}" ] || { log_err "Secrets dosyası bulunamadı: ${SECRETS_FILE}"; exit 1; }

# secrets.env'den değer oku
get_secret() {
    local key="${1}"
    grep "^${key}=" "${SECRETS_FILE}" | cut -d'=' -f2- | tr -d ' '
}

# Node tanımları
declare -A NODE_IPS=(
    [node1]="193.70.46.74"
    [node2]="135.125.223.43"
    [node3]="51.75.74.124"
    [node4]="135.125.175.223"
    [node5]="45.146.252.165"
    [node6]="5.249.165.10"
    [node101]="195.206.234.142"
)
declare -A NODE_WG_IPS=(
    [node1]="10.10.0.1"
    [node2]="10.10.0.2"
    [node3]="10.10.0.3"
    [node4]="10.10.0.4"
    [node5]="10.10.0.5"
    [node6]="10.10.0.6"
    [node101]="10.10.0.101"
)
# node101 yalnız node2 ve nodeMonitor ile peer'lanır (tam mesh'e dahil değil)
NODE101_PEERS=(node2 nodeMonitor)

# Pubkey'leri yükle
declare -A PUBKEYS
for node in node1 node2 node3 node4 node5 node6; do
    PUBKEYS[${node}]="$(get_secret "${node}_pubkey")"
    if [ -z "${PUBKEYS[${node}]}" ]; then
        log_err "secrets.env içinde ${node}_pubkey boş — önce bootstrap tamamla"
        exit 1
    fi
done
# node101 pubkey opsiyonel (bootstrap tamamlanmışsa)
PUBKEYS[node101]="$(get_secret "node101_pubkey" 2>/dev/null || true)"

log_step "WireGuard mesh pubkey'leri doğrulandı"
for node in node1 node2 node3 node4 node5 node6; do
    log_info "${node}: ${PUBKEYS[${node}]}"
done
[ -n "${PUBKEYS[node101]:-}" ] && log_info "node101: ${PUBKEYS[node101]}" || log_info "node101: (henüz yok — atlanacak)"

# wg0.conf'u doldur ve WG başlat
apply_wg_to_node() {
    local target_node="${1}"
    local target_ip="${NODE_IPS[${target_node}]}"
    local target_wg="${NODE_WG_IPS[${target_node}]}"
    local ssh_key="${SSH_KEY:-~/.ssh/${target_node}}"

    log_step "wg_mesh → ${target_node} (${target_ip})"

    local cmd=""
    for peer_node in node1 node2 node3 node4 node5 node6; do
        [ "${peer_node}" = "${target_node}" ] && continue
        local pubkey="${PUBKEYS[${peer_node}]}"
        cmd+="sed -i 's|<${peer_node}_pubkey>|${pubkey}|g' /etc/wireguard/wg0.conf; "
    done

    # WG başlat
    cmd+="systemctl enable --now wg-quick@wg0 2>/dev/null || wg-quick up wg0 2>/dev/null || true; "
    cmd+="wg show wg0 | grep -c peer || true"

    ssh -i "${ssh_key}" -o StrictHostKeyChecking=no \
        "tucibeyin@${target_ip}" "sudo bash -c '${cmd}'"

    log_ok "${target_node} WG mesh hazır"
}

# node101 → node2+nodeMonitor peer ekleme (tam mesh'e dahil değil)
apply_wg_node101() {
    [ -n "${PUBKEYS[node101]:-}" ] || { log_info "node101_pubkey eksik — node101 WG adımı atlanıyor"; return; }
    local node101_pubkey="${PUBKEYS[node101]}"
    local ssh_key="${SSH_KEY:-${HOME}/.ssh/node105}"

    log_step "wg_mesh → node101 (offsite, partial peer)"

    # node101'in wg0.conf'unda node2 ve nodeMonitor pubkey'lerini doldur
    local cmd=""
    cmd+="sed -i 's|<node2_pubkey>|${PUBKEYS[node2]}|g' /etc/wireguard/wg0.conf; "
    # nodeMonitor pubkey
    local nm_pubkey
    nm_pubkey="$(get_secret "nodemonitor_pubkey" 2>/dev/null || true)"
    [ -n "${nm_pubkey}" ] && cmd+="sed -i 's|<nodemonitor_pubkey>|${nm_pubkey}|g' /etc/wireguard/wg0.conf; "
    cmd+="systemctl restart wg-quick@wg0 2>/dev/null || wg-quick down wg0; wg-quick up wg0; "
    cmd+="wg show wg0 | grep -c peer || true"

    ssh -i "${ssh_key}" -o StrictHostKeyChecking=no \
        "tucibeyin@195.206.234.142" "sudo bash -c '${cmd}'"

    # node2 ve nodeMonitor'a node101 peer ekle
    for peer in node2 nodeMonitor; do
        local peer_ip="${NODE_IPS[${peer}]:-}"
        local peer_key="${SSH_KEY:-~/.ssh/${peer}}"
        [ -z "${peer_ip}" ] && continue
        log_info "node101 peer → ${peer}"
        ssh -i "${peer_key}" -o StrictHostKeyChecking=no \
            "tucibeyin@${peer_ip}" "sudo bash -c \"
                grep -q '${node101_pubkey}' /etc/wireguard/wg0.conf 2>/dev/null && { echo 'zaten var'; exit 0; }
                printf '\n# node101 (Offsite Backup)\n[Peer]\nPublicKey = ${node101_pubkey}\nAllowedIPs = 10.10.0.101/32\nEndpoint = 195.206.234.142:51820\nPersistentKeepalive = 25\n' >> /etc/wireguard/wg0.conf
                wg set wg0 peer '${node101_pubkey}' allowed-ips '10.10.0.101/32' endpoint '195.206.234.142:51820' persistent-keepalive 25 2>/dev/null || true
                echo 'peer eklendi'
            \""
        log_ok "${peer} → node101 peer eklendi"
    done

    log_ok "node101 WG partial mesh hazır"
}

# Bağlantı testi
test_wg_mesh() {
    log_step "Mesh bağlantı testi"
    local ok=0
    local fail=0
    for node in node1 node2 node3 node4 node5 node6; do
        local ip="${NODE_IPS[${node}]}"
        local wg="${NODE_WG_IPS[${node}]}"
        local ssh_key="${SSH_KEY:-~/.ssh/${node}}"
        # node1'den diğerlerine ping testi
        if [ "${node}" = "node1" ]; then
            for peer in node2 node3 node4 node5 node6; do
                local peer_wg="${NODE_WG_IPS[${peer}]}"
                if ssh -i "${ssh_key}" -o StrictHostKeyChecking=no \
                    "tucibeyin@${ip}" "ping -c1 -W2 ${peer_wg}" &>/dev/null; then
                    log_ok "  node1 → ${peer} (${peer_wg}): OK"
                    ((ok++))
                else
                    log_err "  node1 → ${peer} (${peer_wg}): BAŞARISIZ"
                    ((fail++))
                fi
            done
            break
        fi
    done
    # node101 bağlantı testi
    if [ -n "${PUBKEYS[node101]:-}" ]; then
        if ssh -o ConnectTimeout=5 node2 "ping -c1 -W2 10.10.0.101" &>/dev/null; then
            log_ok "  node2 → node101 (10.10.0.101): OK"
            ((ok++))
        else
            log_err "  node2 → node101 (10.10.0.101): BAŞARISIZ"
            ((fail++))
        fi
    fi
    echo ""
    log_info "Test sonucu: ${ok} başarılı, ${fail} başarısız"
}

# Ana akış
log_step "WireGuard mesh uygulanıyor (6 node + node101)"
for node in node1 node2 node3 node4 node5 node6; do
    apply_wg_to_node "${node}"
done
apply_wg_node101

echo ""
read -r -p "Bağlantı testi yapalım mı? (node1'den tüm peer'lara ping) [y/N] " confirm
[ "${confirm}" = "y" ] || [ "${confirm}" = "Y" ] && test_wg_mesh || true

echo ""
echo -e "${GREEN}WireGuard mesh tamamlandı.${NC}"
echo -e "Kontrol: ${CYAN}ssh tucibeyin@193.70.46.74 'wg show wg0'${NC}"
