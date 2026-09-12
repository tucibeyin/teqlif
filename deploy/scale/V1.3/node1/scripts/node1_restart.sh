#!/usr/bin/env bash
# node1 deploy — git pull → teqlif (live journal) → check infra → summary
set -euo pipefail

REPO_DIR="/var/www/teqlif.com"

R="\033[0m"; B="\033[1m"; D="\033[2m"
G="\033[0;32m"; RE="\033[0;31m"; Y="\033[1;33m"; C="\033[0;36m"; M="\033[0;35m"
HR="${B}\033[0;31m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${R}"

svc_state() { systemctl is-active "$1" 2>/dev/null || echo "unknown"; }

print_svc() {
    local label="$1" svc="$2" action="$3" st pid started
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
printf "${B}  node1 Deploy  \033[0;31mPRODUCTION${R}  ${D}%s${R}\n" "$(date '+%Y-%m-%d %H:%M:%S')"
echo -e "$HR"
echo ""

# ── 1/4 git pull ──────────────────────────────────────────────────────────────
echo -e "${B}[1/4] git pull${R}"
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

# ── 2/4 Uygulama restart ──────────────────────────────────────────────────────
echo -e "${B}[2/4] Uygulama servisleri restart ediliyor${R}"
echo -e "  ${D}► teqlif          — alembic + sync_main + uvicorn (canlı journal)${R}"
echo -e "  ${D}► teqlif-worker   — otomatik (PartOf)${R}"
echo -e "  ${D}► teqlif-worker-critical — otomatik (PartOf)${R}"
echo ""

SINCE="$(date '+%Y-%m-%d %H:%M:%S')"
echo -e "${C}${B}─── canlı journal: teqlif ──────────────────────────────────────────${R}"

systemctl restart teqlif &
RESTART_PID=$!
journalctl -u teqlif -f --since "$SINCE" --no-pager --output=short-precise 2>/dev/null &
JOURNAL_PID=$!

MAX_WAIT=300; WAITED=0
while (( WAITED < MAX_WAIT )); do
    sleep 3; WAITED=$(( WAITED + 3 ))
    st=$(svc_state teqlif)
    [[ "$st" == "active" || "$st" == "failed" || "$st" == "inactive" ]] && break
done
sleep 1
kill "$JOURNAL_PID" 2>/dev/null || true
wait "$JOURNAL_PID" 2>/dev/null || true
wait "$RESTART_PID" 2>/dev/null || true

echo -e "${C}${B}────────────────────────────────────────────────────────────────────${R}"
echo ""

# ── 3/4 Altyapı durumu ────────────────────────────────────────────────────────
echo -e "${B}[3/4] Altyapı durumu${R}  ${D}(bu servisler restart edilmez)${R}"
echo ""
# PostgreSQL — sisteme göre servis adı değişebilir
PG_SVC="postgresql"
systemctl cat postgresql.service &>/dev/null || PG_SVC=$(systemctl list-units --type=service --no-legend 2>/dev/null | awk '{print $1}' | grep -m1 "^postgres" || echo "postgresql")
for svc in "$PG_SVC" redis minio livekit node_exporter promtail teqlif-backup.timer redis-backup.timer; do
    st=$(svc_state "$svc")
    case "$st" in
        active)          clr="$G" ;;
        inactive|static) clr="$D" ;;
        *)               clr="$RE"; FAILED+=("$svc") ;;
    esac
    printf "  ${clr}%-8s${R}  ${D}[CHECK]${R}  %s\n" "$st" "$svc"
done
echo ""

# ── 4/4 Sonuç özeti ───────────────────────────────────────────────────────────
echo -e "${B}[4/4] Servis özeti${R}"
echo ""
print_svc "RESTART" "teqlif"                   "restart"
print_svc "RESTART" "teqlif-worker"            "PartOf"
print_svc "RESTART" "teqlif-worker-critical"   "PartOf"
echo ""

if (( ${#FAILED[@]} == 0 )); then
    echo -e "$HR"
    echo -e "${G}${B}  ✓  Deploy başarılı — tüm servisler aktif.${R}"
    echo -e "$HR"
    echo ""
    exit 0
fi

# ── Hata raporu ───────────────────────────────────────────────────────────────
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
