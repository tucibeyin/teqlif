#!/bin/bash
# wg_add_node101.sh — node101 WireGuard peer'ini node2 ve nodeMonitor'a ekle
#
# Kullanım (her hedef node'da ayrı ayrı çalıştır):
#   node2:        sudo bash wg_add_node101.sh
#   nodeMonitor:  sudo bash wg_add_node101.sh
#
# Önkoşul: node101 bootstrap tamamlanmış ve pubkey alınmış olmalı.
#   node101'de pubkey: cat /etc/wireguard/pubkey
#   Bu scripte geçir: NODE101_PUBKEY=<pubkey> sudo bash wg_add_node101.sh

set -euo pipefail

NODE101_WG_IP="10.10.0.101"
NODE101_PUBLIC_IP="195.206.234.142"
NODE101_PUBKEY="${NODE101_PUBKEY:-}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'

if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}[ERR ] Root olarak çalıştırın: sudo bash $0${NC}" >&2
    exit 1
fi

if [ -z "${NODE101_PUBKEY}" ]; then
    echo -e "${RED}[ERR ] NODE101_PUBKEY eksik.${NC}" >&2
    echo "  Kullanım: NODE101_PUBKEY=<pubkey> sudo bash $0" >&2
    echo "  node101'de pubkey al: cat /etc/wireguard/pubkey" >&2
    exit 1
fi

echo -e "${CYAN}[INFO]${NC} node101 peer ekleniyor (${NODE101_WG_IP})..."

# Çalışan wg0'a ekle (kalıcı değil — test için)
if ip link show wg0 &>/dev/null; then
    wg set wg0 peer "${NODE101_PUBKEY}" \
        allowed-ips "${NODE101_WG_IP}/32" \
        endpoint "${NODE101_PUBLIC_IP}:51820" \
        persistent-keepalive 25
    echo -e "${GREEN}[ OK ]${NC} wg0 peer eklendi (geçici)"
fi

# wg0.conf dosyasına kalıcı ekle
WG_CONF=/etc/wireguard/wg0.conf
if grep -q "${NODE101_WG_IP}" "${WG_CONF}" 2>/dev/null; then
    echo -e "${YELLOW}[WARN]${NC} node101 peer zaten wg0.conf'ta — atlanıyor"
else
    cat >> "${WG_CONF}" <<EOF

# node101 (Offsite Backup — DELUXHOST NL)
[Peer]
PublicKey = ${NODE101_PUBKEY}
AllowedIPs = ${NODE101_WG_IP}/32
Endpoint = ${NODE101_PUBLIC_IP}:51820
PersistentKeepalive = 25
EOF
    echo -e "${GREEN}[ OK ]${NC} wg0.conf güncellendi"
fi

# Config kaydet (wg-quick)
wg-quick save wg0 2>/dev/null || true

echo ""
echo -e "${GREEN}Bitti.${NC} Bağlantı testi:"
echo "  ping -c 3 ${NODE101_WG_IP}"
echo "  curl -s http://${NODE101_WG_IP}:8000/  (restic-rest-server hazırsa)"
