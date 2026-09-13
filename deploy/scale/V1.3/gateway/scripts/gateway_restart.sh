#!/usr/bin/env bash
# gateway deploy — git pull → nginx reload → summary
set -euo pipefail

REPO_DIR="/var/www/teqlif.com"

R="\033[0m"; B="\033[1m"; D="\033[2m"
G="\033[0;32m"; RE="\033[0;31m"; Y="\033[1;33m"
HR="${B}\033[0;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${R}"

svc_state() { systemctl is-active "$1" 2>/dev/null || echo "unknown"; }

FAILED=()

# ── Başlık ────────────────────────────────────────────────────────────────────
echo ""
echo -e "$HR"
printf "${B}  gateway Deploy  \033[0;36mEDGE PROXY${R}  ${D}%s${R}\n" "$(date '+%Y-%m-%d %H:%M:%S')"
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

# ── 2/3 nginx reload ──────────────────────────────────────────────────────────
echo -e "${B}[2/3] nginx reload${R}"
echo -ne "  ${D}Config test (nginx -t)...${R} "
if nginx -t 2>/dev/null; then
    echo -e "${G}✓${R}"
    echo -ne "  ${D}Reload...${R} "
    if systemctl reload nginx 2>/dev/null; then
        sleep 1
        st=$(svc_state nginx)
        [[ "$st" == "active" ]] && echo -e "${G}✓${R}" || { echo -e "${RE}✗ (${st})${R}"; FAILED+=(nginx); }
    else
        echo -e "${RE}✗ (reload başarısız)${R}"
        FAILED+=(nginx)
    fi
else
    echo -e "${RE}✗ — nginx config hatası, reload iptal edildi.${R}"
    echo ""
    nginx -t 2>&1 | sed 's/^/  /'
    FAILED+=(nginx)
fi
echo ""

# ── 3/3 Sonuç özeti ───────────────────────────────────────────────────────────
echo -e "${B}[3/3] Servis özeti${R}"
echo ""

for svc in nginx node_exporter promtail; do
    st=$(svc_state "$svc")
    if [[ "$st" == "active" ]]; then
        pid=$(systemctl show "$svc" --property=MainPID --value 2>/dev/null || echo "?")
        printf "  ${G}${B}✓ %-8s${R}  ${B}%-30s${R}  ${D}pid=%s${R}\n" "ACTIVE" "$svc" "$pid"
    else
        printf "  ${RE}${B}✗ %-8s${R}  ${B}%s${R}\n" "${st^^}" "$svc"
        [[ " ${FAILED[*]} " != *" $svc "* ]] && FAILED+=("$svc")
    fi
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
echo ""
exit 1
