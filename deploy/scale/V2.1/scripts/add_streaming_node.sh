#!/bin/bash
# add_streaming_node.sh — teqlif V2.1 Plug-and-Play Streaming Node Ekleme
#
# Kullanım:
#   export NEW_NODE_HOST="<yeni-sunucu-ip>"
#   export STREAMING_WG_IP="10.10.0.20"      # bir sonraki boş WG IP
#   export STREAMING_NODE_NAME="stream-3"    # node ismi
#   export SECRETS_FILE="./secrets.env"
#   export SSH_KEY="~/.ssh/stream3"          # opsiyonel
#   bash add_streaming_node.sh
#
# Yaptıkları:
#   1. Yeni node'da bootstrap_node3.sh'ı template olarak çalıştırır (dinamik IP ile)
#   2. Yeni node'un WG pubkey'ini alır
#   3. Mevcut tüm node'lara yeni peer ekler
#   4. Yeni node'a mevcut tüm peer'ları ekler
#   5. WG bağlantısını doğrular

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
log_info() { echo -e "${CYAN}[INFO]${NC} $*"; }
log_ok()   { echo -e "${GREEN}[ OK ]${NC} $*"; }
log_err()  { echo -e "${RED}[ERR ]${NC} $*" >&2; }
log_step() { echo -e "\n${BOLD}──── $* ────${NC}"; }

: "${NEW_NODE_HOST:?NEW_NODE_HOST belirtilmeli (yeni node public IP)}"
: "${STREAMING_WG_IP:?STREAMING_WG_IP belirtilmeli (örn: 10.10.0.20)}"
: "${STREAMING_NODE_NAME:?STREAMING_NODE_NAME belirtilmeli (örn: stream-3)}"
: "${SECRETS_FILE:?SECRETS_FILE belirtilmeli}"

[ -f "${SECRETS_FILE}" ] || { log_err "Secrets dosyası bulunamadı: ${SECRETS_FILE}"; exit 1; }

SSH_KEY="${SSH_KEY:-~/.ssh/id_ed25519}"
REPO_DIR="${REPO_DIR:-/var/www/teqlif.com}"

get_secret() { grep "^${1}=" "${SECRETS_FILE}" | cut -d'=' -f2- | tr -d ' '; }

# Mevcut sabit node'lar
declare -A EXISTING_NODES=(
    [node1]="193.70.46.74:10.10.0.1"
    [node2]="135.125.223.43:10.10.0.2"
    [node3]="51.75.74.124:10.10.0.3"
    [node4]="135.125.175.223:10.10.0.4"
    [node5]="45.146.252.165:10.10.0.5"
    [node6]="5.249.165.10:10.10.0.6"
)

ssh_run() {
    local host="${1}"; shift
    local key="${SSH_KEY}"
    # Streaming node'lar için ayrı key olabilir
    [ -f "${SSH_KEY%/*}/${STREAMING_NODE_NAME}" ] \
        && key="${SSH_KEY%/*}/${STREAMING_NODE_NAME}"
    ssh -i "${key}" -o StrictHostKeyChecking=no "tucibeyin@${host}" "$@"
}

ssh_run_existing() {
    local node_name="${1}"; shift
    local host
    host="$(echo "${EXISTING_NODES[${node_name}]}" | cut -d: -f1)"
    local key="${SSH_KEY%/*}/${node_name}"
    [ -f "${key}" ] || key="${SSH_KEY}"
    ssh -i "${key}" -o StrictHostKeyChecking=no "tucibeyin@${host}" "$@"
}

# ── ADIM 1: Yeni node bootstrap ───────────────────────────────────────────────
log_step "ADIM 1: ${STREAMING_NODE_NAME} (${NEW_NODE_HOST}) bootstrap"

# node3 config'ini template olarak kullan, WG IP'yi değiştir
ssh_run "${NEW_NODE_HOST}" "sudo bash -c '
    # Repo hazırsa doğrudan bootstrap çalıştır, yoksa önce klon gerekli
    if [ -d ${REPO_DIR}/.git ]; then
        git -C ${REPO_DIR} pull --ff-only 2>/dev/null || true
    fi
    # node3 bootstrap scriptini streaming node için kullan (WG IP override ile)
    STREAMING_WG_IP=${STREAMING_WG_IP} \
    NODE_ID=${STREAMING_NODE_NAME} \
    bash ${REPO_DIR}/deploy/scale/V2.1/scripts/bootstrap_streaming_generic.sh
'"

log_ok "Bootstrap tamamlandı"

# ── ADIM 2: Yeni node'un WG pubkey'ini al ────────────────────────────────────
log_step "ADIM 2: WG pubkey alınıyor"
NEW_PUBKEY="$(ssh_run "${NEW_NODE_HOST}" 'cat /etc/wireguard/pubkey')"
[ -n "${NEW_PUBKEY}" ] || { log_err "pubkey alınamadı"; exit 1; }
log_ok "Yeni pubkey: ${NEW_PUBKEY}"

# ── ADIM 3: Mevcut node'lara yeni peer ekle ─────────────────────────────────
log_step "ADIM 3: Mevcut node'lara ${STREAMING_NODE_NAME} (${STREAMING_WG_IP}) ekleniyor"

for node_name in "${!EXISTING_NODES[@]}"; do
    node_info="${EXISTING_NODES[${node_name}]}"
    node_public_ip="$(echo "${node_info}" | cut -d: -f1)"

    log_info "  → ${node_name} (${node_public_ip})"
    ssh_run_existing "${node_name}" "sudo bash -c \"
        wg set wg0 peer ${NEW_PUBKEY} \
            allowed-ips ${STREAMING_WG_IP}/32 \
            endpoint ${NEW_NODE_HOST}:51820 \
            persistent-keepalive 25
        wg-quick save wg0
    \""
    log_ok "  ${node_name}: peer eklendi"
done

# ── ADIM 4: Yeni node'a mevcut peer'ları ekle ───────────────────────────────
log_step "ADIM 4: Yeni node'a mevcut peer'lar ekleniyor"

for node_name in "${!EXISTING_NODES[@]}"; do
    node_info="${EXISTING_NODES[${node_name}]}"
    node_public_ip="$(echo "${node_info}" | cut -d: -f1)"
    node_wg_ip="$(echo "${node_info}" | cut -d: -f2)"
    node_pubkey="$(get_secret "${node_name}_pubkey")"

    [ -n "${node_pubkey}" ] || { log_err "secrets.env'de ${node_name}_pubkey eksik"; continue; }

    log_info "  ← ${node_name} (${node_wg_ip})"
    ssh_run "${NEW_NODE_HOST}" "sudo bash -c \"
        wg set wg0 peer ${node_pubkey} \
            allowed-ips ${node_wg_ip}/32 \
            endpoint ${node_public_ip}:51820 \
            persistent-keepalive 25
        wg-quick save wg0
    \""
    log_ok "  ${node_name}: eklendi"
done

# ── ADIM 5: Bağlantı testi ───────────────────────────────────────────────────
log_step "ADIM 5: Bağlantı testi"

sleep 3
# node1'den yeni node'a ping
NODE1_IP="$(echo "${EXISTING_NODES[node1]}" | cut -d: -f1)"
if ssh -i "${SSH_KEY%/*}/node1" -o StrictHostKeyChecking=no \
    "tucibeyin@${NODE1_IP}" "ping -c1 -W3 ${STREAMING_WG_IP}" &>/dev/null; then
    log_ok "node1 → ${STREAMING_NODE_NAME} (${STREAMING_WG_IP}): BAŞARILI"
else
    log_err "node1 → ${STREAMING_NODE_NAME} (${STREAMING_WG_IP}): BAŞARISIZ — WG handshake bekleniyor olabilir"
fi

echo ""
echo -e "${GREEN}${STREAMING_NODE_NAME} başarıyla eklendi!${NC}"
echo -e "  WG IP  : ${CYAN}${STREAMING_WG_IP}${NC}"
echo -e "  Pubkey : ${CYAN}${NEW_PUBKEY}${NC}"
echo ""
if [ -f "${SECRETS_FILE:-}" ]; then
    echo "${STREAMING_NODE_NAME}_pubkey=${NEW_PUBKEY}" >> "${SECRETS_FILE}"
    log_ok "secrets.env güncellendi: ${STREAMING_NODE_NAME}_pubkey eklendi"
else
    log_info "${STREAMING_NODE_NAME}_pubkey=${NEW_PUBKEY}"
fi
