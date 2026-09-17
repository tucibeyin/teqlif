#!/usr/bin/env bash
# deploy/scale/V1.4/scripts/repair_wireguard.sh
# Wireguard koptuğunda sunucudaki güncel PrivateKey'i koruyarak güncel Public Peer'leri (repodan) içeri aktarır.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
   echo "Bu script root haklarıyla (sudo) çalıştırılmalıdır." 
   exit 1
fi

NODE_NAME=$(hostname -s)
REPO="/var/www/teqlif.com"
TEMPLATE_FILE="$REPO/deploy/scale/V1.4/$NODE_NAME/resources/wg0.conf"

if [[ ! -f "$TEMPLATE_FILE" ]]; then
    # gateway ise özel yol kontrolü
    if [[ "$NODE_NAME" == "gateway" ]]; then
        TEMPLATE_FILE="$REPO/deploy/scale/V1.3/gateway/resources/wg0.conf"
    fi
    if [[ ! -f "$TEMPLATE_FILE" ]]; then
        echo "HATA: $TEMPLATE_FILE bulunamadı! Bu script sadece Node1-5 ve gateway için çalışır."
        exit 1
    fi
fi

if [[ ! -f "/etc/wireguard/wg0.conf" ]]; then
    echo "HATA: /etc/wireguard/wg0.conf bulunamadı. Sunucuda Private Key yok."
    exit 1
fi

# Mevcut Private Key'i Yedekle
PRIV_KEY=$(grep "^PrivateKey" /etc/wireguard/wg0.conf | awk '{print $3}')

if [[ -z "$PRIV_KEY" ]]; then
    echo "HATA: /etc/wireguard/wg0.conf içinde PrivateKey bulunamadı!"
    exit 1
fi

echo "==> Mevcut Private Key korumaya alındı."

# Template'i kopyala
cp "$TEMPLATE_FILE" /etc/wireguard/wg0.conf
chmod 600 /etc/wireguard/wg0.conf

# Template içindeki <..._PRIVATE_KEY> placeholder'ını asıl Private Key ile değiştir
sed -i "s|<[A-Z0-9_]*PRIVATE_KEY>|$PRIV_KEY|g" /etc/wireguard/wg0.conf

echo "==> Yeni Public Key (Peer) listesi Github'dan içeri aktarıldı."

# Ağı yeniden başlat
systemctl restart wg-quick@wg0
echo "==> WireGuard Mesh Ağı yeniden başlatıldı. Başarılı!"
