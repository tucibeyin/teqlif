#!/usr/bin/env bash
# node2 deploy — git pull → ai-proxy + cf-failover → summary
set -euo pipefail

REPO_DIR="/var/www/teqlif.com"

R="\033[0m"; B="\033[1m"; D="\033[2m"
G="\033[0;32m"; RE="\033[0;31m"; Y="\033[1;33m"; C="\033[0;36m"
HR="${B}\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${R}"

svc_state() { systemctl is-active "$1" 2>/dev/null || echo "unknown"; }

print_svc() {
    local svc="$1" action="$2" st pid started
    st=$(svc_state "$svc")
    if [[ "$st" == "active" ]]; then
        pid=$(systemctl show "$svc" --property=MainPID --value 2>/dev/null || echo "?")
        started=$(systemctl show "$svc" --property=ActiveEnterTimestamp --value 2>/dev/null \
            | sed 's/ [A-Z]*$//' | awk '{print $2,$3}')
        printf "  ${G}${B}✓ %-8s${R}  ${B}%-42s${R}  ${D}[%s] pid=%-6s %s${R}\n" \
               "ACTIVE" "$svc" "$action" "$pid" "$started"
    else
        printf "  ${RE}${B}✗ %-8s${R}  ${B}%-42s${R}  ${D}[%s]${R}\n" \
               "${st^^}" "$svc" "$action"
        FAILED+=("$svc")
    fi
}

FAILED=()

# ── Başlık ────────────────────────────────────────────────────────────────────
echo ""
echo -e "$HR"
printf "${B}  node2 Deploy  \033[0;34mAI PROXY (primary)${R}  ${D}%s${R}\n" "$(date '+%Y-%m-%d %H:%M:%S')"
echo -e "$HR"
echo ""

# ── 1/3 git pull ──────────────────────────────────────────────────────────────
echo -e "${B}[1/3] git pull${R}"
cd "$REPO_DIR"
GIT_BEFORE=$(git rev-parse HEAD)
if ! sudo -u tucibeyin git pull --ff-only 2>&1 | sed 's/^/  /'; then
    echo -e "  ${RE}git pull başarısız — yerel değişiklik veya çakışma var.${R}" >&2
    exit 1
fi
GIT_AFTER=$(git rev-parse HEAD)
if [[ "$GIT_BEFORE" == "$GIT_AFTER" ]]; then
    echo -e "  ${D}Değişiklik yok — zaten güncel.${R}"
else
    CHANGED=$(git diff --name-only "$GIT_BEFORE" "$GIT_AFTER" | wc -l | tr -d ' ')
    echo -e "  ${G}${CHANGED} dosya güncellendi:${R}"
    git log --oneline "$GIT_BEFORE..$GIT_AFTER" | sed 's/^/    /'
fi
echo ""

# ── 2/3 Uygulama restart ──────────────────────────────────────────────────────
echo -e "${B}[2/3] Uygulama servisleri restart ediliyor${R}"
echo ""

for svc in teqlif-ai-proxy cf-failover; do
    echo -ne "  ${D}Restart: ${svc}...${R} "
    if systemctl restart "$svc" 2>/dev/null; then
        sleep 1
        st=$(svc_state "$svc")
        if [[ "$st" == "active" ]]; then
            echo -e "${G}✓${R}"
        else
            echo -e "${RE}✗ (${st})${R}"
            FAILED+=("$svc")
        fi
    else
        echo -e "${RE}✗ (restart komutu başarısız)${R}"
        FAILED+=("$svc")
    fi
done
echo ""

# ── 3/3 Sonuç özeti ───────────────────────────────────────────────────────────
echo -e "${B}[3/3] Servis özeti${R}"
echo ""
print_svc "teqlif-ai-proxy" "restart"
print_svc "cf-failover"     "restart"
echo ""

# Monitoring kontrol
for svc in node_exporter promtail; do
    st=$(svc_state "$svc")
    [[ "$st" == "active" ]] && clr="$G" || { clr="$RE"; FAILED+=("$svc"); }
    printf "  ${clr}%-8s${R}  ${D}[CHECK]${R}  %s\n" "$st" "$svc"
done
echo ""

if (( ${#FAILED[@]} == 0 )); then
    echo -e "$HR"
    echo -e "${G}${B}  ✓  Deploy başarılı — tüm servisler aktif.${R}"
    echo -e "$HR"
    echo ""
    exit 0
fi

echo -e "${RE}${B}  ✗  Başarısız: ${FAILED[*]}${R}"
echo ""
for svc in "${FAILED[@]}"; do
    echo -e "${RE}${B}━━━━━━ Hata: ${svc} $(printf '━%.0s' {1..50})${R}"
    systemctl status "$svc" --no-pager -l 2>&1 || true
    echo ""
    journalctl -u "$svc" --no-pager -n 100 --output=short-precise 2>&1 || true
    echo ""
done
echo -e "${Y}StartLimitBurst aşıldıysa: sudo systemctl reset-failed <servis>${R}"
echo ""
exit 1
