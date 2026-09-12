#!/usr/bin/env bash
# teqlif-restart — Teqlif stack'ini yeniden başlatır, tüm süreci canlı izler.
#
# Kullanım:
#   sudo teqlif-restart             # production (node1)
#   sudo teqlif-restart staging     # staging    (node3)
#
# Kurulum (VPS'te bir kez):
#   sudo install -m 755 /var/www/teqlif.com/deploy/scale/V1.3/scripts/teqlif-restart.sh \
#        /usr/local/bin/teqlif-restart

set -euo pipefail

ENV="${1:-prod}"

case "$ENV" in
    prod|production)
        MAIN_SVC="teqlif"
        WORKER_SVC="teqlif-worker"
        WORKER_CRIT_SVC="teqlif-worker-critical"
        ENV_LABEL="PRODUCTION"
        HEADER_CLR="\033[0;31m"   # kırmızı
        ;;
    staging)
        MAIN_SVC="teqlif-staging"
        WORKER_SVC="teqlif-worker-staging"
        WORKER_CRIT_SVC="teqlif-worker-critical-staging"
        ENV_LABEL="STAGING"
        HEADER_CLR="\033[0;33m"   # sarı
        ;;
    *)
        echo "Hata: geçersiz ortam '$ENV'. Kullanım: teqlif-restart [prod|staging]" >&2
        exit 1
        ;;
esac

# ── renkler ────────────────────────────────────────────────────────────────────
R="\033[0m"     # reset
B="\033[1m"     # bold
D="\033[2m"     # dim
G="\033[0;32m"  # yeşil
RE="\033[0;31m" # kırmızı
Y="\033[1;33m"  # sarı
C="\033[0;36m"  # cyan

HR="${B}${HEADER_CLR}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${R}"

# ── 1. BAŞLIK ─────────────────────────────────────────────────────────────────
echo ""
echo -e "$HR"
printf "${B}  Teqlif Restart  ${HEADER_CLR}%-10s${R}  ${D}%s${R}\n" \
       "$ENV_LABEL" "$(date '+%Y-%m-%d %H:%M:%S')"
echo -e "$HR"
echo ""

# ── 2. MEVCUT DURUM ───────────────────────────────────────────────────────────
svc_state() { systemctl is-active "$1" 2>/dev/null || echo "unknown"; }

printf "${B}%-50s %s${R}\n" "Servis" "Durum"
echo -e "${D}$(printf '─%.0s' {1..60})${R}"
for svc in "$MAIN_SVC" "$WORKER_SVC" "$WORKER_CRIT_SVC"; do
    st=$(svc_state "$svc")
    if   [[ "$st" == "active"   ]]; then clr="$G"
    elif [[ "$st" == "inactive" ]]; then clr="$D"
    else                                  clr="$RE"
    fi
    printf "  %-48s ${clr}%s${R}\n" "$svc" "$st"
done
echo ""

# ── 3. RESTART ────────────────────────────────────────────────────────────────
SINCE="$(date '+%Y-%m-%d %H:%M:%S')"

echo -e "${B}[START]${R} ${D}Restart başlatılıyor...${R}"
echo -e "  ${D}► ExecStartPre-1  alembic upgrade head${R}"
echo -e "  ${D}► ExecStartPre-2  sync_main.py${R}"
echo -e "  ${D}► ExecStart       uvicorn${R}"
echo ""

systemctl restart "$MAIN_SVC" &
RESTART_PID=$!

# journal canlı göster (restart tamamlanana kadar)
echo -e "${C}${B}─── canlı journal ──────────────────────────────────────────────────────${R}"

journalctl -u "$MAIN_SVC" -f --since "$SINCE" --no-pager --output=short-precise 2>/dev/null &
JOURNAL_PID=$!

# servis kararlı duruma gelene kadar bekle (max 5 dk)
MAX_WAIT=300
WAITED=0
while (( WAITED < MAX_WAIT )); do
    sleep 3
    WAITED=$(( WAITED + 3 ))
    st=$(svc_state "$MAIN_SVC")
    if [[ "$st" == "active" || "$st" == "failed" || "$st" == "inactive" ]]; then
        break
    fi
done

sleep 1  # son journal satırlarının yazılması için
kill "$JOURNAL_PID" 2>/dev/null || true
wait "$JOURNAL_PID" 2>/dev/null || true
wait "$RESTART_PID" 2>/dev/null || true

echo -e "${C}${B}────────────────────────────────────────────────────────────────────────${R}"
echo ""

# ── 4. SONUÇ ─────────────────────────────────────────────────────────────────
echo -e "${B}[STATUS]${R}"
echo ""

FAILED=()

report_service() {
    local svc="$1"
    local st
    st=$(svc_state "$svc")

    if [[ "$st" == "active" ]]; then
        local pid started
        pid=$(systemctl show "$svc" --property=MainPID   --value 2>/dev/null || echo "?")
        started=$(systemctl show "$svc" --property=ActiveEnterTimestamp --value 2>/dev/null \
            | sed 's/ [A-Z]*$//' | awk '{print $2, $3}')
        printf "  ${G}${B}✓ ACTIVE${R}   ${B}%-42s${R}  ${D}pid=%-6s  %s${R}\n" \
               "$svc" "$pid" "$started"
    else
        printf "  ${RE}${B}✗ %-8s${R}  ${B}%s${R}\n" "${st^^}" "$svc"
        FAILED+=("$svc")
    fi
}

report_service "$MAIN_SVC"
report_service "$WORKER_SVC"
report_service "$WORKER_CRIT_SVC"

echo ""

# ── 5. BAŞARI / HATA ─────────────────────────────────────────────────────────
if (( ${#FAILED[@]} == 0 )); then
    echo -e "$HR"
    echo -e "${G}${B}  ✓  Restart başarılı — tüm servisler aktif.${R}"
    echo -e "$HR"
    echo ""
    exit 0
fi

# ── 6. HATA RAPORU ───────────────────────────────────────────────────────────
echo -e "${RE}${B}  ✗  ${#FAILED[@]} servis başlatılamadı: ${FAILED[*]}${R}"
echo ""

for svc in "${FAILED[@]}"; do
    echo -e "${RE}${B}━━━━━━ Hata Raporu: ${svc} $(printf '━%.0s' {1..40})${R}"
    echo ""

    echo -e "${B}▸ systemctl status:${R}"
    systemctl status "$svc" --no-pager -l 2>&1 || true
    echo ""

    echo -e "${B}▸ Son 200 satır journal (en güncel altta):${R}"
    journalctl -u "$svc" --no-pager -n 200 --output=short-precise 2>&1 || true
    echo ""

    echo -e "${RE}${B}$(printf '━%.0s' {1..72})${R}"
    echo ""
done

# StartLimitBurst notu
echo -e "${Y}Servis sürekli çöküyorsa StartLimitBurst aşılmış olabilir.${R}"
echo -e "${Y}Sayacı sıfırlamak için:${R}"
for svc in "${FAILED[@]}"; do
    echo -e "  ${D}sudo systemctl reset-failed ${svc}${R}"
done
echo ""
exit 1
