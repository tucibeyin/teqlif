#!/usr/bin/env bash
# teqlif-restart — node'u tespit eder, o node'a ait restart scriptini çalıştırır.
#
# Kullanım:
#   sudo teqlif-restart
#
# Kurulum (her node'da bir kez):
#   sudo install -m 755 /var/www/teqlif.com/deploy/scale/V1.3/scripts/teqlif-restart.sh \
#        /usr/local/bin/teqlif-restart

set -euo pipefail

REPO_DIR="/var/www/teqlif.com"

# ── Node tespiti ──────────────────────────────────────────────────────────────
# Her node'un kendine özgü bir servisi var; varlığına bakarak tespit edilir.
detect_node() {
    if systemctl cat teqlif.service &>/dev/null && \
       ! systemctl cat teqlif-staging.service &>/dev/null; then
        echo "node1"
    elif systemctl cat cf-failover.service &>/dev/null; then
        echo "node2"
    elif systemctl cat teqlif-staging.service &>/dev/null; then
        echo "node3"
    else
        echo "gateway"
    fi
}

NODE=$(detect_node)
SCRIPT="$REPO_DIR/deploy/scale/V1.3/$NODE/scripts/${NODE}_restart.sh"

if [[ ! -f "$SCRIPT" ]]; then
    echo "Hata: $SCRIPT bulunamadı." >&2
    exit 1
fi

chmod +x "$SCRIPT"
exec bash "$SCRIPT"
