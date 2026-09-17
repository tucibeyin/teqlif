#!/usr/bin/env bash
# deploy/scale/V1.4/scripts/teqlif-restart.sh
# teqlif-restart — V1.4 mimarisinde wg0 IP adresine bakarak node'u tespit eder 
# ve o node'a ait tüm servisleri adım adım, durumlarını göstererek yeniden başlatır.

set -euo pipefail

REPO_DIR="/var/www/teqlif.com"

# Renkler
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

detect_node() {
    local wg_ip
    if wg_ip=$(ip -4 addr show wg0 2>/dev/null | grep -oP '(?<=inet\s)10\.10\.0\.\d+'); then
        case "$wg_ip" in
            "10.10.0.1") echo "node1" ; return 0 ;;
            "10.10.0.3") echo "node2" ; return 0 ;;
            "10.10.0.4") echo "node3" ; return 0 ;;
            "10.10.0.5") echo "node5" ; return 0 ;;
            "10.10.0.6") echo "node4" ; return 0 ;;
        esac
    fi

    if systemctl is-active nginx &>/dev/null; then
        echo "gateway"
        return 0
    fi

    echo "unknown"
}

NODE=$(detect_node)

if [[ "$NODE" == "unknown" ]]; then
    echo -e "${RED}Hata: Bu sunucunun V1.4 rolü tespit edilemedi.${RESET}" >&2
    exit 1
fi

SCRIPT="$REPO_DIR/deploy/scale/V1.4/$NODE/resources/${NODE}_services.sh"

if [[ ! -f "$SCRIPT" ]]; then
    echo -e "${RED}Hata: $SCRIPT bulunamadı. V1.4 altyapısı bu node için tam kurulmamış olabilir.${RESET}" >&2
    exit 1
fi

chmod +x "$SCRIPT"

echo -e "\n${CYAN}${BOLD}════════════════════════════════════════════════════════════════════${RESET}"
echo -e "${CYAN}${BOLD} 🚀 TEQLIF RESTART — $NODE Tüm Bileşenleri Yeniden Başlatılıyor ${RESET}"
echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════════════════${RESET}\n"

# İlgili node'un servis listesini `status` komutu çıktısından yakalıyoruz
SERVICES=$(bash "$SCRIPT" status | awk '{print $1}')

# Bütün servisleri sırayla restart et
for svc in $SERVICES; do
    echo -ne "  ${YELLOW}↻${RESET} Yeniden başlatılıyor: ${BOLD}$svc${RESET} ... "
    if sudo systemctl restart "$svc" 2>/dev/null; then
        echo -e "${GREEN}BAŞARILI${RESET}"
    else
        echo -e "${RED}BAŞARISIZ${RESET} (Loglara bak: journalctl -u $svc)"
    fi
done

echo -e "\n${CYAN}${BOLD}════════════════════════════════════════════════════════════════════${RESET}"
echo -e "${CYAN}${BOLD} 📊 $NODE Bileşen Durumları (Sonuç) ${RESET}"
echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════════════════${RESET}\n"

bash "$SCRIPT" status | while read -r line; do
    svc=$(echo "$line" | awk '{print $1}')
    status=$(echo "$line" | cut -d' ' -f2-)
    
    if [[ "$status" == *"active"* ]]; then
        printf "  ${GREEN}✓${RESET} %-35s : ${GREEN}%s${RESET}\n" "$svc" "$status"
    elif [[ "$status" == "kurulu değil" || "$status" == *"not-found"* ]]; then
        printf "  ${YELLOW}⚠${RESET} %-35s : ${YELLOW}%s${RESET}\n" "$svc" "$status"
    else
        printf "  ${RED}✗${RESET} %-35s : ${RED}%s${RESET}\n" "$svc" "$status"
    fi
done

echo -e "\n${GREEN}${BOLD}✓ $NODE yeniden başlatma işlemi tamamlandı.${RESET}\n"
