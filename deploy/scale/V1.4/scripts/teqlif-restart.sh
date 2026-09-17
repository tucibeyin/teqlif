#!/usr/bin/env bash
# deploy/scale/V1.4/scripts/teqlif-restart.sh
# teqlif-restart — V1.4 mimarisinde wg0 IP adresine bakarak node'u tespit eder 
# ve o node'a ait restart scriptini çalıştırır.
#
# Kullanım:
#   sudo teqlif-restart
#
# Kurulum (her node'da bir kez):
#   sudo install -m 755 /var/www/teqlif.com/deploy/scale/V1.4/scripts/teqlif-restart.sh \
#        /usr/local/bin/teqlif-restart

set -euo pipefail

REPO_DIR="/var/www/teqlif.com"

# ── Node tespiti ──────────────────────────────────────────────────────────────
detect_node() {
    # 1. WireGuard IP'si (10.10.0.X) ile kesin tespit (Node 1, 2, 3, 4, 5)
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

    # 2. WireGuard yoksa Gateway'dir
    # (Nginx servisi çalışıyor mu diye kontrol edebiliriz)
    if systemctl is-active nginx &>/dev/null; then
        echo "gateway"
        return 0
    fi

    echo "unknown"
}

NODE=$(detect_node)

if [[ "$NODE" == "unknown" ]]; then
    echo "Hata: Bu sunucunun V1.4 rolü (Node1-5 veya Gateway) tespit edilemedi." >&2
    exit 1
fi

SCRIPT="$REPO_DIR/deploy/scale/V1.4/$NODE/resources/${NODE}_services.sh"

if [[ ! -f "$SCRIPT" ]]; then
    echo "Hata: $SCRIPT bulunamadı. V1.4 altyapısı bu node için tam kurulmamış olabilir." >&2
    exit 1
fi

chmod +x "$SCRIPT"
exec bash "$SCRIPT" restart
